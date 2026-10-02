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

  /// Media type of the response, without parameters (`application/json`).
  String? get contentType {
    final value = _contentType(responseHeaders);
    return value.isEmpty ? null : value.split(';').first.trim();
  }

  Map<String, dynamic> toPreview() => {
        'id': id,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'method': method,
        'url': url,
        'status': statusCode,
        'durationMs': durationMs,
        if (contentType != null) 'contentType': contentType,
        'requestBytes': requestBytes,
        'responseBytes': responseBytes,
        'completed': completed,
        if (error != null) 'error': error,
      };

  /// Full details. Each body is cut to [maxBodyChars] characters starting at
  /// [bodyOffset]; a complete JSON body is returned as JSON, not as a string.
  Map<String, dynamic> toDetail(
      {int maxBodyChars = 20000, int bodyOffset = 0}) {
    return {
      'id': id,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'method': method,
      'url': url,
      'status': statusCode,
      'durationMs': durationMs,
      if (error != null) 'error': error,
      'requestHeaders': requestHeaders,
      ..._bodyFields(
          'request', requestBody, requestHeaders, maxBodyChars, bodyOffset),
      'requestBytes': requestBytes,
      'responseHeaders': responseHeaders,
      ..._bodyFields(
          'response', responseBody, responseHeaders, maxBodyChars, bodyOffset),
      'responseBytes': responseBytes,
      'completed': completed,
    };
  }
}

Map<String, dynamic> _bodyFields(
  String prefix,
  String? body,
  Map<String, dynamic> headers,
  int maxChars,
  int offset,
) {
  if (body == null) return {'${prefix}Body': null};
  final start = offset.clamp(0, body.length);
  final end = (start + maxChars).clamp(start, body.length);
  final whole = start == 0 && end == body.length;
  return {
    '${prefix}Body':
        whole ? _jsonOrText(body, headers) : body.substring(start, end),
    if (!whole)
      '${prefix}BodyRange': {
        'offset': start,
        'returnedChars': end - start,
        'totalChars': body.length,
      },
  };
}

/// Decoded JSON when the body is JSON, so it isn't escaped twice in the tool
/// response; the raw text otherwise.
Object _jsonOrText(String body, Map<String, dynamic> headers) {
  if (body.isEmpty || !_contentType(headers).contains('json')) return body;
  try {
    return jsonDecode(body) ?? body;
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
