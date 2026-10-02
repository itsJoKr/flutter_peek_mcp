import 'models.dart';
import 'noise_filter.dart';

/// Filters HTTP entries by the arguments shared by the HTTP tools.
List<HttpEntry> filterHttp(
  Iterable<HttpEntry> all,
  Map<String, dynamic> args,
  NoiseFilter noise,
) {
  final urlContains = (args['urlContains'] as String?)?.toLowerCase();
  final method = (args['method'] as String?)?.toUpperCase();
  final status = args['status'] as String?;
  final minDuration = asInt(args['minDurationMs']);
  final since = asInt(args['sinceMs']);
  final until = asInt(args['untilMs']);
  final includeNoise = args['includeNoise'] as bool? ?? false;

  return all.where((e) {
    if (!includeNoise && noise.isNoise(e.url)) return false;
    if (urlContains != null && !e.url.toLowerCase().contains(urlContains)) {
      return false;
    }
    if (method != null && e.method.toUpperCase() != method) return false;
    if (status != null && !matchesStatus(e.statusCode, status)) return false;
    if (minDuration != null && (e.durationMs ?? 0) < minDuration) return false;
    return _inRange(e.timestamp, since, until);
  }).toList();
}

/// Filters console entries by the arguments of `list_console_logs`.
List<LogEntry> filterLogs(Iterable<LogEntry> all, Map<String, dynamic> args) {
  final contains = (args['contains'] as String?)?.toLowerCase();
  final pattern = args['matchesRegex'] as String?;
  final regex = pattern != null ? RegExp(pattern, caseSensitive: false) : null;
  final level = args['level'] as String?;
  final source = args['source'] as String?;
  final since = asInt(args['sinceMs']);
  final until = asInt(args['untilMs']);

  return all.where((e) {
    if (contains != null && !e.text.toLowerCase().contains(contains)) {
      return false;
    }
    if (regex != null && !regex.hasMatch(e.text)) return false;
    if (level != null && e.level != level) return false;
    if (source != null && e.source != source) return false;
    return _inRange(e.timestamp, since, until);
  }).toList();
}

bool _inRange(DateTime timestamp, int? sinceMs, int? untilMs) {
  final ms = timestamp.millisecondsSinceEpoch;
  if (sinceMs != null && ms < sinceMs) return false;
  if (untilMs != null && ms > untilMs) return false;
  return true;
}

/// Matches a status code against an exact code (`404`), a family (`4xx`) or a
/// comparison (`>=400`). Requests without a response never match.
bool matchesStatus(int? code, String filter) {
  final f = filter.toLowerCase().trim();
  if (f.isEmpty) return true;
  if (code == null) return false;

  final exact = int.tryParse(f);
  if (exact != null) return code == exact;

  if (RegExp(r'^[1-5]xx$').hasMatch(f)) return code ~/ 100 == int.parse(f[0]);

  final comparison = RegExp(r'^(>=|<=|>|<|=)\s*(\d+)$').firstMatch(f);
  if (comparison == null) return false;
  final value = int.parse(comparison.group(2)!);
  return switch (comparison.group(1)) {
    '>=' => code >= value,
    '<=' => code <= value,
    '>' => code > value,
    '<' => code < value,
    _ => code == value,
  };
}

typedef HttpMatch = ({String where, String snippet});

/// Finds [query] (case-insensitive) in the URL, headers or bodies of [entry],
/// limited to [field] (`all`, `url`, `headers` or `body`).
HttpMatch? findHttpMatch(HttpEntry entry, String query, String field) {
  final candidates = <(String, String?)>[
    if (field == 'all' || field == 'url') ('url', entry.url),
    if (field == 'all' || field == 'headers')
      ('headers', '${entry.requestHeaders}\n${entry.responseHeaders}'),
    if (field == 'all' || field == 'body') ...[
      ('requestBody', entry.requestBody),
      ('responseBody', entry.responseBody),
    ],
  ];
  for (final (where, text) in candidates) {
    final snippet = snippetAround(text, query);
    if (snippet != null) return (where: where, snippet: snippet);
  }
  return null;
}

/// Up to [radius] characters on each side of the first match of [query].
String? snippetAround(String? text, String query, {int radius = 60}) {
  if (text == null) return null;
  final index = text.toLowerCase().indexOf(query.toLowerCase());
  if (index < 0) return null;
  final start = (index - radius).clamp(0, text.length);
  final end = (index + query.length + radius).clamp(0, text.length);
  return '${start > 0 ? '…' : ''}'
      '${text.substring(start, end)}'
      '${end < text.length ? '…' : ''}';
}

int? asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// Sorts in place by timestamp; `newest` (the default) or `oldest` first.
void sortByTime<T>(List<T> items, DateTime Function(T) timeOf, String? order) {
  final oldestFirst = order == 'oldest';
  items.sort((a, b) => oldestFirst
      ? timeOf(a).compareTo(timeOf(b))
      : timeOf(b).compareTo(timeOf(a)));
}
