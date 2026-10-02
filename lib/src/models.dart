import 'dart:convert';

/// One line of app output: `print`/stdout, stderr, or a `dart:developer` log.
class LogEntry {
  final String id;
  final DateTime timestamp;

  /// `stdout`, `stderr` or `log` (from `dart:developer` `log()`).
  final String source;

  /// `info`, `warn` or `error`.
  final String level;

  /// Mutable so a truncated `log()` message can be replaced once the full
  /// string is fetched from the VM.
  String text;

  LogEntry({
    required this.id,
    required this.timestamp,
    required this.source,
    required this.level,
    required this.text,
  });

  Map<String, dynamic> toPreview({int textCap = 200}) {
    final truncated = text.length > textCap;
    return {
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'source': source,
      'level': level,
      'text': truncated ? '${text.substring(0, textCap)}…' : text,
      if (truncated) 'truncated': true,
    };
  }

  Map<String, dynamic> toFull() => {
        'id': id,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'source': source,
        'level': level,
        'text': text,
      };
}

/// Guesses a level from the text of a plain stdout line.
String levelFromText(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('exception') || lower.contains('error')) return 'error';
  if (lower.contains('warn')) return 'warn';
  return 'info';
}

/// Maps a `dart:developer` / `package:logging` numeric level to ours.
/// 900 is WARNING and 1000 is SEVERE in `package:logging`.
String levelFromLogRecord(int level) {
  if (level >= 1000) return 'error';
  if (level >= 900) return 'warn';
  return 'info';
}

/// One HTTP request captured by the `dart:io` HTTP profiler.
class HttpEntry {
  /// Stable id exposed to tools. Unique across app restarts.
  final String id;

  /// Id assigned by the app's HTTP profiler. Only valid for the isolate that
  /// made the request.
  final String profileId;

  final DateTime timestamp;
  final String method;
  final String url;
  final int? statusCode;
  final int? durationMs;
  final Map<String, dynamic> requestHeaders;
  final Map<String, dynamic> responseHeaders;
  final String? requestBody;
  final String? responseBody;
  final int requestBytes;
  final int responseBytes;

  /// True once the response has fully arrived, or the request failed.
  final bool completed;
  final String? error;

  HttpEntry({
    required this.id,
    required this.profileId,
    required this.timestamp,
    required this.method,
    required this.url,
    this.statusCode,
    this.durationMs,
    Map<String, dynamic>? requestHeaders,
    Map<String, dynamic>? responseHeaders,
    this.requestBody,
    this.responseBody,
    this.requestBytes = 0,
    this.responseBytes = 0,
    this.completed = false,
    this.error,
  })  : requestHeaders = requestHeaders ?? const {},
        responseHeaders = responseHeaders ?? const {};

  HttpEntry copyWith({
    String? requestBody,
    String? responseBody,
    int? requestBytes,
    int? responseBytes,
  }) {
    return HttpEntry(
      id: id,
      profileId: profileId,
      timestamp: timestamp,
      method: method,
      url: url,
      statusCode: statusCode,
      durationMs: durationMs,
      requestHeaders: requestHeaders,
      responseHeaders: responseHeaders,
      requestBody: requestBody ?? this.requestBody,
      responseBody: responseBody ?? this.responseBody,
      requestBytes: requestBytes ?? this.requestBytes,
      responseBytes: responseBytes ?? this.responseBytes,
      completed: completed,
      error: error,
    );
  }

  Map<String, dynamic> toPreview() => {
        'id': id,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'method': method,
        'url': url,
        'status': statusCode,
        'durationMs': durationMs,
        'requestBytes': requestBytes,
        'responseBytes': responseBytes,
        'completed': completed,
        if (error != null) 'error': error,
      };

  Map<String, dynamic> toDetail({int bodyCap = 50000}) {
    final req = _capBody(requestBody, bodyCap);
    final resp = _capBody(responseBody, bodyCap);
    return {
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'method': method,
      'url': url,
      'status': statusCode,
      'durationMs': durationMs,
      'requestHeaders': requestHeaders,
      'requestBody': _pretty(req.text, requestHeaders),
      if (req.truncated) 'requestBodyTruncated': true,
      'requestBytes': requestBytes,
      'responseHeaders': responseHeaders,
      'responseBody': _pretty(resp.text, responseHeaders),
      if (resp.truncated) 'responseBodyTruncated': true,
      'responseBytes': responseBytes,
      'completed': completed,
      if (error != null) 'error': error,
    };
  }
}

({String? text, bool truncated}) _capBody(String? body, int cap) {
  if (body == null) return (text: null, truncated: false);
  if (body.length <= cap) return (text: body, truncated: false);
  return (text: '${body.substring(0, cap)}…[TRUNCATED]', truncated: true);
}

String? _pretty(String? body, Map<String, dynamic> headers) {
  if (body == null || body.isEmpty) return body;
  if (!_contentType(headers).contains('json')) return body;
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(body));
  } on FormatException {
    return body;
  }
}

String _contentType(Map<String, dynamic> headers) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'content-type') {
      final v = entry.value;
      if (v is List) return v.join(';').toLowerCase();
      return v.toString().toLowerCase();
    }
  }
  return '';
}
