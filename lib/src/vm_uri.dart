import 'dart:convert';

/// Extracts the VM service URI from the file written by
/// `flutter run --vmservice-out-file` (plain text) or
/// `dart run --write-service-info` (JSON with a `uri` key).
String parseUriFile(String contents) {
  final raw = contents.trim();
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map && decoded['uri'] is String) {
      return decoded['uri'] as String;
    }
    if (decoded is String) return decoded;
  } on FormatException {
    // Plain text, which is what Flutter writes.
  }
  return raw;
}

/// Turns any VM service address into the WebSocket URI that `vm_service`
/// connects to.
///
/// Accepts the `http://127.0.0.1:PORT/TOKEN=/` form printed by `flutter run`,
/// an already-complete `ws://…/ws` URI, or a DevTools URL that carries the
/// address in its `uri` query parameter.
String toWebSocketUri(String input) {
  var uri = input.trim();

  final parsed = Uri.tryParse(uri);
  final embedded = parsed?.queryParameters['uri'];
  if (embedded != null && embedded.isNotEmpty) uri = embedded;

  if (uri.startsWith('http://')) {
    uri = 'ws://${uri.substring('http://'.length)}';
  } else if (uri.startsWith('https://')) {
    uri = 'wss://${uri.substring('https://'.length)}';
  } else if (!uri.startsWith('ws://') && !uri.startsWith('wss://')) {
    uri = 'ws://$uri';
  }

  if (uri.endsWith('/')) uri = uri.substring(0, uri.length - 1);
  return uri.endsWith('/ws') ? uri : '$uri/ws';
}
