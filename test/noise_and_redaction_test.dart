import 'package:flutter_peek_mcp/src/noise_filter.dart';
import 'package:flutter_peek_mcp/src/redaction.dart';
import 'package:test/test.dart';

void main() {
  test('NoiseFilter.parse reads substrings, regexes and comments', () {
    final patterns = NoiseFilter.parse('''
# comment
/metrics

regex:^https://cdn\\.
''');
    final filter = NoiseFilter(patterns);
    expect(filter.isNoise('https://api.example.com/metrics'), isTrue);
    expect(filter.isNoise('https://cdn.example.com/a.png'), isTrue);
    expect(filter.isNoise('https://api.example.com/cdn.'), isFalse);
    expect(filter.isNoise('https://api.example.com/orders'), isFalse);
  });

  test('default noise hides crash reporting but not app endpoints', () {
    final filter = NoiseFilter.defaults();
    expect(
        filter.isNoise('https://o1.ingest.sentry.io/api/1/envelope/'), isTrue);
    expect(filter.isNoise('https://api.example.com/analytics/report'), isFalse);
  });

  test('redactSensitiveHeaders hides credentials regardless of case', () {
    final redacted = redactSensitiveHeaders({
      'Authorization': ['Bearer secret'],
      'cookie': ['a=b'],
      'content-type': ['application/json'],
    });
    expect(redacted['Authorization'], redactedValue);
    expect(redacted['cookie'], redactedValue);
    expect(redacted['content-type'], ['application/json']);
  });
}
