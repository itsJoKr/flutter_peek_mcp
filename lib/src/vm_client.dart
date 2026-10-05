import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'models.dart';
import 'redaction.dart';
import 'vm_uri.dart';

const _kEnableHttpLogging = 'ext.dart.io.httpEnableTimelineLogging';
const _kGetHttpProfile = 'ext.dart.io.getHttpProfile';
const _kGetHttpProfileRequest = 'ext.dart.io.getHttpProfileRequest';

/// Service extensions run on the app's event loop, so they never answer while
/// the app is paused at a breakpoint.
const _rpcTimeout = Duration(seconds: 5);

/// Bodies that are only fetched when a tool asks for them, because they are
/// big and useless as text (for example, every `Image.network` download).
const _binaryContentTypes = [
  'image/',
  'audio/',
  'video/',
  'font/',
  'application/octet-stream',
  'application/pdf',
  'application/zip',
  'application/gzip',
];
const _maxPrefetchBytes = 1024 * 1024;

/// The app's VM service can't be found or reached. The message says why and
/// how to fix it.
class VmConnectionException implements Exception {
  final String message;
  VmConnectionException(this.message);

  @override
  String toString() => message;
}

/// Connects to a running Flutter app through the Dart VM service and keeps
/// rolling in-memory buffers of its console output and HTTP traffic.
///
/// The connection heals itself. A hot restart replaces the app's isolate, which
/// is picked up from isolate events. A full restart writes a new VM service URI,
/// which the background reconnect loop picks up. Buffers survive both, so the
/// output of a crashed app can still be inspected.
///
/// Console history from before the connection is recovered for free: DDS (which
/// `flutter run` always starts) replays its buffered Stdout, Stderr and Logging
/// events to each new subscriber.
class VmClient {
  final String uriFilePath;
  final bool redactHeaders;
  final int maxLogs;
  final int maxHttp;
  final Duration httpPollInterval;
  final Duration reconnectInterval;

  VmClient({
    required this.uriFilePath,
    this.redactHeaders = true,
    this.maxLogs = 2000,
    this.maxHttp = 500,
    this.httpPollInterval = const Duration(milliseconds: 1500),
    this.reconnectInterval = const Duration(seconds: 1),
  });

  VmService? _service;
  String? _isolateId;
  String? _connectedUri;
  String? _manualUri;
  Future<void>? _connecting;
  String? _lastError;
  String? _lastLogged;

  final List<StreamSubscription<Event>> _subscriptions = [];
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  bool _polling = false;

  final List<LogEntry> _logs = [];
  final LinkedHashSet<String> _seenEvents = LinkedHashSet();
  final Map<String, int> _occurrences = {};
  int _logIdCounter = 0;

  final Map<String, HttpEntry> _http = {};
  final Map<String, String> _idsByProfileId = {};
  String? _httpSessionIsolateId;
  final LinkedHashSet<String> _pendingBodies = LinkedHashSet();
  int _httpIdCounter = 0;
  int? _updatedSinceMicros;

  bool get isConnected => _service != null && _isolateId != null;
  String? get connectedUri => _connectedUri;
  String? get lastError => _lastError;

  /// Where the next connection attempt reads its URI from.
  String get uriSource => _manualUri != null ? 'connect tool' : uriFilePath;

  List<LogEntry> get logs => List.unmodifiable(_logs);
  List<HttpEntry> get httpRequests => List.unmodifiable(_http.values);
  HttpEntry? httpById(String id) => _http[id];
  int indexOfLog(String id) => _logs.indexWhere((l) => l.id == id);

  List<LogEntry> logsAround(int index, int radius) {
    final start = (index - radius).clamp(0, _logs.length);
    final end = (index + radius + 1).clamp(0, _logs.length);
    return _logs.sublist(start, end);
  }

  void clearBuffers() {
    _logs.clear();
    _http.clear();
    _idsByProfileId.clear();
    _pendingBodies.clear();
  }

  /// Tries to connect now and then every [reconnectInterval], so buffers fill
  /// up even before the first tool call.
  void startBackgroundReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer =
        Timer.periodic(reconnectInterval, (_) => unawaited(_tryConnect()));
    unawaited(_tryConnect());
  }

  Future<void> dispose() async {
    _reconnectTimer?.cancel();
    await _disconnect();
  }

  /// Connects to [uri] instead of the URI file. A null or empty [uri] goes
  /// back to the URI file.
  Future<void> connectTo(String? uri) async {
    final trimmed = uri?.trim();
    _manualUri = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    final inFlight = _connecting;
    if (inFlight != null) {
      try {
        await inFlight;
      } catch (_) {
        // Superseded by the connection below.
      }
    }
    await _disconnect();
    await ensureConnected();
  }

  Future<void> ensureConnected() async {
    final service = _service;
    if (service != null) {
      try {
        await service.getVersion().timeout(const Duration(seconds: 3));
      } catch (e) {
        _log('connection lost ($e)');
        await _disconnect();
      }
    }
    if (_service != null && _isolateId == null) await _adoptMainIsolate();
    if (isConnected) {
      _lastError = null;
      return;
    }

    final inFlight = _connecting;
    if (inFlight != null) return inFlight;
    final attempt = _connect();
    _connecting = attempt;
    try {
      await attempt;
      _lastError = null;
    } finally {
      _connecting = null;
    }
  }

  /// Fetches the bodies of [id] now if they haven't been fetched yet.
  Future<HttpEntry?> loadBodies(String id) async {
    if (_pendingBodies.contains(id) && isConnected) {
      await _fetchBodies(id, _isolateId!);
    }
    return _http[id];
  }

  Future<void> _tryConnect() async {
    try {
      await ensureConnected();
    } catch (e) {
      _lastError = '$e';
      _log('$e');
    }
  }

  Future<void> _connect() async {
    final wsUri = toWebSocketUri(await _resolveUri());
    final VmService service;
    try {
      service =
          await vmServiceConnectUri(wsUri).timeout(const Duration(seconds: 5));
    } catch (e) {
      throw VmConnectionException(
        'Could not connect to the VM service at $wsUri ($e). '
        'The app is probably not running.',
      );
    }
    _service = service;
    _connectedUri = wsUri;
    _occurrences.clear();

    try {
      _subscriptions.addAll([
        service.onStdoutEvent.listen((e) => _onStdEvent(e, 'stdout')),
        service.onStderrEvent.listen((e) => _onStdEvent(e, 'stderr')),
        service.onLoggingEvent.listen(_onLoggingEvent),
        service.onIsolateEvent.listen(_onIsolateEvent),
      ]);
      for (final stream in [
        EventStreams.kStdout,
        EventStreams.kStderr,
        EventStreams.kLogging,
        EventStreams.kIsolate,
      ]) {
        try {
          await service.streamListen(stream);
        } on RPCError {
          // Already subscribed.
        }
      }
    } catch (_) {
      await _disconnect();
      rethrow;
    }

    _startPolling();
    _log('connected to $wsUri');
    await _adoptMainIsolate();
  }

  Future<String> _resolveUri() async {
    final manual = _manualUri;
    if (manual != null) return manual;

    final file = File(uriFilePath);
    if (!await file.exists()) {
      throw VmConnectionException(
        'No VM service URI file at $uriFilePath. Start the app with '
        '`flutter run --vmservice-out-file=$uriFilePath`, or call the '
        '`connect` tool with the VM service URI that `flutter run` prints.',
      );
    }
    final contents = await file.readAsString();
    if (contents.trim().isEmpty) {
      throw VmConnectionException('$uriFilePath is empty.');
    }
    return parseUriFile(contents);
  }

  Future<void> _adoptMainIsolate() async {
    final service = _service;
    if (service == null) return;
    final vm = await service.getVM().timeout(_rpcTimeout);
    final isolates = vm.isolates ?? const <IsolateRef>[];
    if (isolates.isEmpty) {
      throw VmConnectionException(
        'Connected, but the app has no running isolate. Is it restarting?',
      );
    }
    final main =
        isolates.firstWhere(_isMainIsolate, orElse: () => isolates.first);
    await _useIsolate(main.id!);
  }

  bool _isMainIsolate(IsolateRef isolate) =>
      (isolate.name ?? '').toLowerCase().contains('main');

  Future<void> _useIsolate(String isolateId) async {
    _isolateId = isolateId;
    if (_httpSessionIsolateId != isolateId) {
      _httpSessionIsolateId = isolateId;
      _idsByProfileId.clear();
      _pendingBodies.clear();
      _updatedSinceMicros = null;
    }
    try {
      await _callExtension(_kEnableHttpLogging, isolateId, {'enabled': 'true'});
    } catch (e) {
      // dart:io registers its extensions slightly after the isolate starts;
      // the ServiceExtensionAdded event retries this.
      _log('HTTP profiling not available yet: $e');
    }
  }

  Future<Response> _callExtension(
    String method,
    String isolateId,
    Map<String, dynamic> args,
  ) {
    final service = _service;
    if (service == null) throw VmConnectionException('Not connected.');
    return service
        .callServiceExtension(method, isolateId: isolateId, args: args)
        .timeout(_rpcTimeout);
  }

  void _onIsolateEvent(Event event) {
    final isolate = event.isolate;
    final id = isolate?.id;
    if (isolate == null || id == null) return;
    if (event.kind == EventKind.kIsolateExit && id == _isolateId) {
      _isolateId = null;
    } else if (event.kind == EventKind.kServiceExtensionAdded &&
        event.extensionRPC == _kEnableHttpLogging &&
        _isMainIsolate(isolate)) {
      unawaited(_useIsolate(id));
    }
  }

  void _onStdEvent(Event event, String source) {
    final bytes = event.bytes;
    if (bytes == null) return;
    if (!_markSeen(
        '$source|${event.timestamp}|${bytes.length}|${bytes.hashCode}')) {
      return;
    }
    final String text;
    try {
      text = utf8.decode(base64Decode(bytes), allowMalformed: true);
    } on FormatException {
      return;
    }
    final timestamp = _eventTime(event);
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) continue;
      _addLog(LogEntry(
        id: '${++_logIdCounter}',
        timestamp: timestamp,
        source: source,
        level: source == 'stderr' ? 'error' : levelFromText(line),
        text: line,
      ));
    }
  }

  void _onLoggingEvent(Event event) {
    final record = event.logRecord;
    if (record == null) return;
    if (!_markSeen('log|${record.time}|${record.sequenceNumber}')) return;

    final logger = record.loggerName?.valueAsString ?? '';
    final message = record.message?.valueAsString ?? '';
    final text = _composeLogText(
      logger,
      message,
      _previewOf(record.error),
      _previewOf(record.stackTrace),
    );
    if (text.isEmpty) return;

    final level = record.level ?? 0;
    final entry = LogEntry(
      id: '${++_logIdCounter}',
      timestamp: record.time != null
          ? DateTime.fromMillisecondsSinceEpoch(record.time!)
          : _eventTime(event),
      source: 'log',
      level: level > 0 ? levelFromLogRecord(level) : levelFromText(text),
      text: text,
    );
    _addLog(entry);

    final isolateId = event.isolate?.id;
    if (isolateId != null && _needsFullText(record)) {
      unawaited(_resolveLogText(entry, isolateId, record, logger));
    }
  }

  bool _needsFullText(LogRecord record) =>
      record.message?.valueAsStringIsTruncated == true ||
      !_isNull(record.error) ||
      !_isNull(record.stackTrace);

  /// Replaces the preview text with the full message, error and stack trace.
  /// Fails quietly when the isolate is gone, keeping the preview.
  Future<void> _resolveLogText(
    LogEntry entry,
    String isolateId,
    LogRecord record,
    String logger,
  ) async {
    try {
      final message = await _stringOf(isolateId, record.message) ?? '';
      final error = await _stringOf(isolateId, record.error);
      final stackTrace = await _stringOf(isolateId, record.stackTrace);
      entry.text = _composeLogText(logger, message, error, stackTrace);
    } catch (_) {
      // Keep the preview text.
    }
  }

  String _composeLogText(
    String logger,
    String message,
    String? error,
    String? stackTrace,
  ) {
    return [
      logger.isEmpty ? message : '[$logger] $message',
      if (error != null && error.isNotEmpty) error,
      if (stackTrace != null && stackTrace.isNotEmpty) stackTrace,
    ].join('\n').trim();
  }

  bool _isNull(InstanceRef? ref) =>
      ref == null || ref.kind == InstanceKind.kNull;

  String? _previewOf(InstanceRef? ref) {
    if (_isNull(ref)) return null;
    return ref!.valueAsString ?? ref.classRef?.name;
  }

  Future<String?> _stringOf(String isolateId, InstanceRef? ref) async {
    final service = _service;
    if (_isNull(ref) || service == null) return null;
    if (ref!.valueAsString != null && ref.valueAsStringIsTruncated != true) {
      return ref.valueAsString;
    }
    final target = ref.kind == InstanceKind.kString
        ? ref
        : await service.invoke(
            isolateId, ref.id!, 'toString', const []).timeout(_rpcTimeout);
    if (target is! InstanceRef) return _previewOf(ref);
    if (target.valueAsStringIsTruncated != true) return target.valueAsString;
    final full =
        await service.getObject(isolateId, target.id!).timeout(_rpcTimeout);
    return full is Instance ? full.valueAsString : target.valueAsString;
  }

  DateTime _eventTime(Event event) => event.timestamp != null
      ? DateTime.fromMillisecondsSinceEpoch(event.timestamp!)
      : DateTime.now();

  /// DDS replays its event history to every new connection, so a reconnect to
  /// the same app would otherwise duplicate the whole console. Identical
  /// events in the same millisecond are told apart by how often they've been
  /// seen on this connection; a replay repeats the same sequence.
  bool _markSeen(String key) {
    if (_occurrences.length > maxLogs * 10) _occurrences.clear();
    final n = _occurrences.update(key, (n) => n + 1, ifAbsent: () => 0);
    if (!_seenEvents.add('$key#$n')) return false;
    if (_seenEvents.length > maxLogs * 10) {
      _seenEvents.remove(_seenEvents.first);
    }
    return true;
  }

  void _addLog(LogEntry entry) {
    _logs.add(entry);
    if (_logs.length > maxLogs) _logs.removeRange(0, _logs.length - maxLogs);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(httpPollInterval, (_) => unawaited(_poll()));
  }

  Future<void> _poll() async {
    if (_polling) return;
    _polling = true;
    try {
      await _pollHttp();
    } on TimeoutException {
      _log('the app is not responding (paused at a breakpoint?)');
    } catch (e) {
      // Usually the isolate died in a hot restart; ensureConnected re-resolves it.
      _log('HTTP poll failed: $e');
      _isolateId = null;
    } finally {
      _polling = false;
    }
  }

  Future<void> _pollHttp() async {
    final service = _service;
    final isolateId = _isolateId;
    if (service == null || isolateId == null) return;

    final since = _updatedSinceMicros;
    final response = await _callExtension(
      _kGetHttpProfile,
      isolateId,
      {if (since != null) 'updatedSince': '$since'},
    );
    if (isolateId != _isolateId) return;

    final json = response.json;
    if (json == null) return;
    final timestamp = json['timestamp'];
    if (timestamp is int) _updatedSinceMicros = timestamp;

    final requests = json['requests'];
    if (requests is List) {
      for (final request in requests.whereType<Map>()) {
        _ingest(Map<String, dynamic>.from(request));
      }
    }
    _evictOldHttp();

    final newestFirst =
        _pendingBodies.toList().reversed.where(_shouldPrefetch).take(25);
    for (final id in newestFirst) {
      await _fetchBodies(id, isolateId);
    }
  }

  void _ingest(Map<String, dynamic> profile) {
    final profileId = profile['id']?.toString();
    if (profileId == null) return;
    final id =
        _idsByProfileId.putIfAbsent(profileId, () => '${++_httpIdCounter}');
    final existing = _http[id];

    final request = _asMap(profile['request']) ?? const <String, dynamic>{};
    final response = _asMap(profile['response']);
    final startTime = _asInt(profile['startTime']);
    final requestEnd = _asInt(profile['endTime']);
    final responseEnd = _asInt(response?['endTime']);
    final error = (request['error'] ?? response?['error'])?.toString();

    // The top-level endTime is when the request finished sending, not when the
    // response arrived, so completion is judged from the response.
    final completed = responseEnd != null || error != null;
    final end = responseEnd ?? (error != null ? requestEnd : null);
    final durationMs = startTime != null && end != null
        ? ((end - startTime) / 1000).round()
        : null;

    final entry = HttpEntry(
      id: id,
      profileId: profileId,
      timestamp: startTime != null
          ? DateTime.fromMicrosecondsSinceEpoch(startTime)
          : existing?.timestamp ?? DateTime.now(),
      method: (profile['method'] ?? '?').toString(),
      url: (profile['uri'] ?? '').toString(),
      statusCode: _asInt(response?['statusCode']) ?? existing?.statusCode,
      durationMs: durationMs ?? existing?.durationMs,
      requestHeaders: _headers(request['headers']) ?? existing?.requestHeaders,
      responseHeaders:
          _headers(response?['headers']) ?? existing?.responseHeaders,
      requestBody: existing?.requestBody,
      responseBody: existing?.responseBody,
      requestBytes: _contentLength(request['contentLength']) ??
          existing?.requestBytes ??
          0,
      responseBytes: _contentLength(response?['contentLength']) ??
          existing?.responseBytes ??
          0,
      completed: completed || (existing?.completed ?? false),
      error: error ?? existing?.error,
    );
    _http[id] = entry;
    if (entry.completed && !(existing?.completed ?? false)) {
      _pendingBodies.add(id);
    }
  }

  bool _shouldPrefetch(String id) {
    final entry = _http[id];
    if (entry == null) return false;
    if (entry.requestBytes > _maxPrefetchBytes ||
        entry.responseBytes > _maxPrefetchBytes) {
      return false;
    }
    final type = entry.contentType ?? '';
    return !_binaryContentTypes.any(type.startsWith);
  }

  Future<void> _fetchBodies(String id, String isolateId) async {
    final entry = _http[id];
    _pendingBodies.remove(id);
    if (_service == null || entry == null) return;

    try {
      final response = await _callExtension(
        _kGetHttpProfileRequest,
        isolateId,
        {'id': entry.profileId},
      );
      final json = response.json;
      final current = _http[id];
      if (json == null || current == null) return;

      final requestBytes = _bodyBytes(json['requestBody']);
      final responseBytes = _bodyBytes(json['responseBody']);
      _http[id] = current.copyWith(
        requestBody: requestBytes == null ? null : _decodeBody(requestBytes),
        responseBody: responseBytes == null ? null : _decodeBody(responseBytes),
        requestBytes: current.requestBytes == 0 ? requestBytes?.length : null,
        responseBytes:
            current.responseBytes == 0 ? responseBytes?.length : null,
      );
    } on TimeoutException {
      _pendingBodies.add(id);
    } catch (e) {
      _log('could not fetch bodies of HTTP request $id: $e');
    }
  }

  void _evictOldHttp() {
    while (_http.length > maxHttp) {
      final oldest = _http.keys.first;
      final entry = _http.remove(oldest)!;
      _pendingBodies.remove(oldest);
      if (_idsByProfileId[entry.profileId] == oldest) {
        _idsByProfileId.remove(entry.profileId);
      }
    }
  }

  Map<String, dynamic>? _headers(Object? raw) {
    final headers = _asMap(raw);
    if (headers == null) return null;
    return redactHeaders ? redactSensitiveHeaders(headers) : headers;
  }

  List<int>? _bodyBytes(Object? body) {
    if (body is List) return body.cast<int>();
    if (body is String) {
      try {
        return base64Decode(body);
      } on FormatException {
        return utf8.encode(body);
      }
    }
    return null;
  }

  String _decodeBody(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return '<${bytes.length} bytes of binary data>';
    }
  }

  Future<void> _disconnect() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final service = _service;
    _service = null;
    _isolateId = null;
    _connectedUri = null;
    try {
      await service?.dispose();
    } catch (_) {
      // Already closed.
    }
  }

  /// Writes to stderr (stdout carries the MCP protocol), skipping repeats so
  /// the reconnect loop doesn't flood the log while the app is down.
  void _log(String message) {
    if (message == _lastLogged) return;
    _lastLogged = message;
    stderr.writeln('flutter-peek: $message');
  }
}

Map<String, dynamic>? _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

int? _asInt(Object? value) => value is num ? value.toInt() : null;

int? _contentLength(Object? value) {
  final length = _asInt(value);
  return length != null && length > 0 ? length : null;
}
