import 'package:flutter_peek_mcp/src/filters.dart';
import 'package:flutter_peek_mcp/src/models.dart';
import 'package:flutter_peek_mcp/src/noise_filter.dart';
import 'package:test/test.dart';

HttpEntry _entry(
  String id, {
  String url = 'https://api.example.com/orders',
  String method = 'GET',
  int? status = 200,
  int durationMs = 10,
  int timestampMs = 1000,
  String? responseBody,
}) =>
    HttpEntry(
      id: id,
      profileId: id,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      method: method,
      url: url,
      statusCode: status,
      durationMs: durationMs,
      responseBody: responseBody,
      completed: true,
    );

void main() {
  group('matchesStatus', () {
    test('exact code', () {
      expect(matchesStatus(404, '404'), isTrue);
      expect(matchesStatus(500, '404'), isFalse);
    });

    test('family', () {
      expect(matchesStatus(404, '4xx'), isTrue);
      expect(matchesStatus(499, '4XX'), isTrue);
      expect(matchesStatus(500, '4xx'), isFalse);
    });

    test('comparison', () {
      expect(matchesStatus(400, '>=400'), isTrue);
      expect(matchesStatus(399, '>=400'), isFalse);
      expect(matchesStatus(499, '< 500'), isTrue);
      expect(matchesStatus(201, '=201'), isTrue);
    });

    test('requests without a response never match', () {
      expect(matchesStatus(null, '5xx'), isFalse);
    });

    test('unknown syntax matches nothing', () {
      expect(matchesStatus(200, 'ok'), isFalse);
    });
  });

  group('filterHttp', () {
    final noise = NoiseFilter(['sentry.io']);
    final entries = [
      _entry('1', status: 200, timestampMs: 1000),
      _entry('2', status: 500, method: 'POST', timestampMs: 2000),
      _entry('3', url: 'https://o1.ingest.sentry.io/api', timestampMs: 3000),
      _entry('4', durationMs: 900, timestampMs: 4000),
    ];

    List<String> ids(Map<String, dynamic> args) =>
        filterHttp(entries, args, noise).map((e) => e.id).toList();

    test('hides noise unless asked', () {
      expect(ids({}), ['1', '2', '4']);
      expect(ids({'includeNoise': true}), ['1', '2', '3', '4']);
    });

    test('combines filters', () {
      expect(ids({'method': 'post'}), ['2']);
      expect(ids({'status': '5xx'}), ['2']);
      expect(ids({'minDurationMs': 500}), ['4']);
      expect(ids({'sinceMs': 2000, 'untilMs': 3500}), ['2']);
      expect(ids({'urlContains': 'ORDERS'}), ['1', '2', '4']);
    });
  });

  group('findHttpMatch', () {
    final entry = _entry('1', responseBody: '{"orderId": "ORD-42"}');

    test('finds text in bodies case-insensitively', () {
      final match = findHttpMatch(entry, 'ord-42', 'all');
      expect(match?.where, 'responseBody');
      expect(match?.snippet, contains('ORD-42'));
    });

    test('respects the field', () {
      expect(findHttpMatch(entry, 'ORD-42', 'url'), isNull);
      expect(findHttpMatch(entry, 'orders', 'url')?.where, 'url');
    });
  });

  test('snippetAround adds ellipses only when text is cut', () {
    expect(snippetAround('abc', 'b'), 'abc');
    expect(
      snippetAround('${'x' * 100}needle${'y' * 100}', 'needle', radius: 3),
      '…xxxneedleyyy…',
    );
  });

  test('filterLogs filters by level, source and regex', () {
    final logs = [
      LogEntry(
        id: '1',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1),
        source: 'stdout',
        level: 'info',
        text: 'Loaded 3 orders',
      ),
      LogEntry(
        id: '2',
        timestamp: DateTime.fromMillisecondsSinceEpoch(2),
        source: 'log',
        level: 'error',
        text: 'Failed to save order',
      ),
    ];
    List<String> ids(Map<String, dynamic> args) =>
        filterLogs(logs, args).map((e) => e.id).toList();

    expect(ids({'level': 'error'}), ['2']);
    expect(ids({'source': 'stdout'}), ['1']);
    expect(ids({'matchesRegex': r'loaded \d+'}), ['1']);
    expect(ids({'contains': 'ORDER'}), ['1', '2']);
  });
}
