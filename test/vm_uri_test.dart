import 'package:flutter_peek_mcp/src/vm_uri.dart';
import 'package:test/test.dart';

void main() {
  group('parseUriFile', () {
    test('plain text, as written by flutter run', () {
      expect(parseUriFile('http://127.0.0.1:1234/abc=/\n'),
          'http://127.0.0.1:1234/abc=/');
    });

    test('JSON, as written by dart --write-service-info', () {
      expect(parseUriFile('{"uri":"http://127.0.0.1:1234/abc=/"}'),
          'http://127.0.0.1:1234/abc=/');
    });
  });

  group('toWebSocketUri', () {
    test('converts the http URI printed by flutter run', () {
      expect(toWebSocketUri('http://127.0.0.1:1234/abc=/'),
          'ws://127.0.0.1:1234/abc=/ws');
    });

    test('keeps a complete ws URI', () {
      expect(toWebSocketUri('ws://127.0.0.1:1234/abc=/ws'),
          'ws://127.0.0.1:1234/abc=/ws');
    });

    test('extracts the URI from a DevTools URL', () {
      expect(
        toWebSocketUri(
            'http://127.0.0.1:9100/?uri=http://127.0.0.1:1234/abc=/'),
        'ws://127.0.0.1:1234/abc=/ws',
      );
    });

    test('adds a scheme when missing', () {
      expect(
          toWebSocketUri('127.0.0.1:1234/abc='), 'ws://127.0.0.1:1234/abc=/ws');
    });
  });
}
