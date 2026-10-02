import 'dart:io';

/// Hides background traffic (analytics, crash reporting, health checks) from
/// HTTP tools unless a tool call passes `includeNoise: true`.
class NoiseFilter {
  /// Substring patterns that are always active.
  static const defaultPatterns = [
    '/heartbeat',
    '/health',
    '/ping',
    'sentry.io',
    'google-analytics.com',
    'googletagmanager.com',
    'firebaselogging',
    'firebase-settings.crashlytics.com',
    'firebaseinstallations.googleapis.com',
    'app-measurement.com',
  ];

  final List<Pattern> _patterns;

  NoiseFilter(Iterable<Pattern> patterns) : _patterns = List.of(patterns);

  NoiseFilter.defaults() : this(defaultPatterns);

  /// Parses a pattern file: one pattern per line, `#` starts a comment, and a
  /// `regex:` prefix makes the rest of the line a regular expression.
  static List<Pattern> parse(String contents) {
    final patterns = <Pattern>[];
    for (final raw in contents.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('regex:')) {
        patterns.add(RegExp(line.substring('regex:'.length).trim()));
      } else {
        patterns.add(line);
      }
    }
    return patterns;
  }

  /// Built-in patterns plus the patterns in [path], when given.
  static Future<NoiseFilter> load(String? path) async {
    if (path == null) return NoiseFilter.defaults();
    final file = File(path);
    if (!await file.exists()) {
      throw ArgumentError.value(path, 'noise', 'file does not exist');
    }
    return NoiseFilter([
      ...defaultPatterns,
      ...parse(await file.readAsString()),
    ]);
  }

  bool isNoise(String url) =>
      _patterns.any((p) => p.allMatches(url).isNotEmpty);
}
