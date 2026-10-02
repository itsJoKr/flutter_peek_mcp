import '../filters.dart';
import '../mcp_server.dart';
import '../models.dart';
import '../noise_filter.dart';
import '../vm_client.dart';
import 'app_tools.dart';

const _filterProperties = {
  'urlContains': {
    'type': 'string',
    'description': 'Case-insensitive substring of the URL',
  },
  'method': {'type': 'string', 'description': 'GET, POST, PUT, DELETE, …'},
  'status': {
    'type': 'string',
    'description':
        'Exact ("404"), family ("4xx", "5xx") or comparison (">=400", "<500")',
  },
  'minDurationMs': {'type': 'integer'},
  'sinceMs': {
    'type': 'integer',
    'description': 'Unix ms; only requests started at or after this time',
  },
  'untilMs': {'type': 'integer'},
};

const _orderProperty = {
  'type': 'string',
  'enum': ['newest', 'oldest'],
  'default': 'newest',
};

const _includeNoiseProperty = {
  'type': 'boolean',
  'default': false,
  'description':
      'Include background traffic (analytics, crash reporting, health checks)',
};

ToolDef listHttpRequestsTool(VmClient vm, NoiseFilter noise) => ToolDef(
      name: 'list_http_requests',
      description:
          'List captured HTTP requests with metadata only (no headers or '
          'bodies): method, URL, status, duration, sizes. Use it to scan '
          'recent network activity, then open one with get_http_request.',
      inputSchema: {
        'type': 'object',
        'properties': {
          ..._filterProperties,
          'limit': {'type': 'integer', 'default': 50, 'maximum': 200},
          'offset': {'type': 'integer', 'default': 0},
          'order': _orderProperty,
          'includeNoise': _includeNoiseProperty,
        },
      },
      handler: (args) async {
        final warning = await connectOrWarn(vm);
        final filtered = filterHttp(vm.httpRequests, args, noise);
        sortByTime(filtered, _timeOf, args['order'] as String?);
        final offset = asInt(args['offset']) ?? 0;
        final limit = (asInt(args['limit']) ?? 50).clamp(1, 200);
        final page = filtered.skip(offset).take(limit).toList();
        return {
          if (warning != null) 'warning': warning,
          'total': filtered.length,
          'returned': page.length,
          'offset': offset,
          'items': [for (final e in page) e.toPreview()],
        };
      },
    );

ToolDef getHttpRequestTool(VmClient vm) => ToolDef(
      name: 'get_http_request',
      description:
          'Get one HTTP request by id with full request and response headers '
          'and bodies. Bodies are capped at about 50 KB each, and JSON is '
          'pretty-printed.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
        },
        'required': ['id'],
      },
      handler: (args) async {
        final warning = await connectOrWarn(vm);
        final id = args['id'] as String?;
        if (id == null) throw ToolException('id is required');
        final entry = await vm.loadBodies(id);
        if (entry == null) {
          throw ToolException('No HTTP request with id "$id" in buffer');
        }
        return {
          if (warning != null) 'warning': warning,
          ...entry.toDetail(),
        };
      },
    );

ToolDef getHttpRequestsWithBodiesTool(VmClient vm, NoiseFilter noise) =>
    ToolDef(
      name: 'get_http_requests_with_bodies',
      description:
          'Get full details, with bodies, of up to 10 HTTP requests that match '
          'a filter. At least one filter is required, so the whole buffer is '
          'never dumped.',
      inputSchema: {
        'type': 'object',
        'properties': {
          ..._filterProperties,
          'limit': {'type': 'integer', 'default': 10, 'maximum': 10},
          'order': _orderProperty,
          'includeNoise': _includeNoiseProperty,
        },
      },
      handler: (args) async {
        final hasFilter = _filterProperties.keys.any((key) {
          final value = args[key];
          return value != null && '$value'.isNotEmpty;
        });
        if (!hasFilter) {
          throw ToolException(
            'Pass at least one of ${_filterProperties.keys.join(', ')}. '
            'Use list_http_requests to scan without bodies.',
          );
        }
        final warning = await connectOrWarn(vm);
        final filtered = filterHttp(vm.httpRequests, args, noise);
        sortByTime(filtered, _timeOf, args['order'] as String?);
        final limit = (asInt(args['limit']) ?? 10).clamp(1, 10);
        final items = <Map<String, dynamic>>[];
        for (final entry in filtered.take(limit)) {
          items.add((await vm.loadBodies(entry.id) ?? entry).toDetail());
        }
        return {
          if (warning != null) 'warning': warning,
          'total': filtered.length,
          'returned': items.length,
          'items': items,
        };
      },
    );

ToolDef searchHttpRequestsTool(VmClient vm, NoiseFilter noise) => ToolDef(
      name: 'search_http_requests',
      description:
          'Search HTTP URLs, headers and bodies for text (case-insensitive). '
          'Returns previews with a snippet around the match. Use it to find a '
          'request by its content, such as an order id in a payload, when you '
          'do not know the URL. Open a match with get_http_request.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Text to search for'},
          'field': {
            'type': 'string',
            'enum': ['all', 'url', 'body', 'headers'],
            'default': 'all',
          },
          'limit': {'type': 'integer', 'default': 20, 'maximum': 50},
          'includeNoise': _includeNoiseProperty,
        },
        'required': ['query'],
      },
      handler: (args) async {
        final query = args['query'] as String?;
        if (query == null || query.isEmpty) {
          throw ToolException('query is required');
        }
        final warning = await connectOrWarn(vm);
        final field = args['field'] as String? ?? 'all';
        final limit = (asInt(args['limit']) ?? 20).clamp(1, 50);
        final includeNoise = args['includeNoise'] as bool? ?? false;

        final results = <Map<String, dynamic>>[];
        for (final entry in vm.httpRequests.reversed) {
          if (!includeNoise && noise.isNoise(entry.url)) continue;
          final match = findHttpMatch(entry, query, field);
          if (match == null) continue;
          results.add({
            ...entry.toPreview(),
            'matchWhere': match.where,
            'matchSnippet': match.snippet,
          });
          if (results.length >= limit) break;
        }
        return {
          if (warning != null) 'warning': warning,
          'returned': results.length,
          'items': results,
        };
      },
    );

ToolDef httpSummaryTool(VmClient vm, NoiseFilter noise) => ToolDef(
      name: 'http_summary',
      description:
          'Aggregate stats over captured HTTP requests: counts by status '
          'family and method, error rate, slowest and most frequent URLs. A '
          'cheap first check for "is anything wrong with the network?".',
      inputSchema: {
        'type': 'object',
        'properties': {
          'sinceMs': {'type': 'integer'},
          'includeNoise': _includeNoiseProperty,
        },
      },
      handler: (args) async {
        final warning = await connectOrWarn(vm);
        final entries = filterHttp(vm.httpRequests, args, noise);

        final byStatusFamily = <String, int>{};
        final byMethod = <String, int>{};
        final durationsByUrl = <String, List<int>>{};
        final countByUrl = <String, int>{};
        var errorCount = 0;

        for (final e in entries) {
          byMethod.update(e.method, (n) => n + 1, ifAbsent: () => 1);
          countByUrl.update(e.url, (n) => n + 1, ifAbsent: () => 1);
          if (e.durationMs != null) {
            durationsByUrl.putIfAbsent(e.url, () => []).add(e.durationMs!);
          }
          final code = e.statusCode;
          final family = code == null
              ? (e.error != null ? 'failed' : 'pending')
              : '${code ~/ 100}xx';
          byStatusFamily.update(family, (n) => n + 1, ifAbsent: () => 1);
          if (e.error != null || (code != null && code >= 400)) errorCount++;
        }

        final averageByUrl = {
          for (final MapEntry(key: url, value: durations)
              in durationsByUrl.entries)
            url: (durations.reduce((a, b) => a + b) / durations.length).round(),
        };

        return {
          if (warning != null) 'warning': warning,
          'total': entries.length,
          'byStatusFamily': byStatusFamily,
          'byMethod': byMethod,
          'errorCount': errorCount,
          'errorRate': entries.isEmpty ? 0.0 : errorCount / entries.length,
          'topSlowUrls': _top(averageByUrl, 'avgDurationMs'),
          'topFrequentUrls': _top(countByUrl, 'count'),
        };
      },
    );

DateTime _timeOf(HttpEntry entry) => entry.timestamp;

List<Map<String, dynamic>> _top(Map<String, num> stats, String key) {
  final sorted = stats.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final entry in sorted.take(5)) {'url': entry.key, key: entry.value},
  ];
}
