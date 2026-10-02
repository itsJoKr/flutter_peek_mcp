import '../filters.dart';
import '../mcp_server.dart';
import '../models.dart';
import '../vm_client.dart';
import 'app_tools.dart';

ToolDef listConsoleLogsTool(VmClient vm) => ToolDef(
      name: 'list_console_logs',
      description: 'List buffered console output: print/stdout, stderr and '
          'dart:developer log() records. Long lines are truncated to 200 '
          'characters; open one with get_console_log for the full text and '
          'the lines around it.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'contains': {
            'type': 'string',
            'description': 'Case-insensitive substring',
          },
          'matchesRegex': {
            'type': 'string',
            'description': 'Case-insensitive regular expression',
          },
          'level': {
            'type': 'string',
            'enum': ['info', 'warn', 'error'],
          },
          'source': {
            'type': 'string',
            'enum': ['stdout', 'stderr', 'log'],
          },
          'sinceMs': {'type': 'integer'},
          'untilMs': {'type': 'integer'},
          'limit': {'type': 'integer', 'default': 100, 'maximum': 500},
          'offset': {'type': 'integer', 'default': 0},
          'order': {
            'type': 'string',
            'enum': ['newest', 'oldest'],
            'default': 'newest',
          },
        },
      },
      handler: (args) async {
        final warning = await connectOrWarn(vm);
        final filtered = filterLogs(vm.logs, args);
        sortByTime(filtered, _timeOf, args['order'] as String?);
        final offset = asInt(args['offset']) ?? 0;
        final limit = (asInt(args['limit']) ?? 100).clamp(1, 500);
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

ToolDef getConsoleLogTool(VmClient vm) => ToolDef(
      name: 'get_console_log',
      description:
          'Get the full text of one console entry by id, plus the entries '
          'before and after it. Useful for stack traces.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'contextLines': {'type': 'integer', 'default': 5, 'maximum': 50},
        },
        'required': ['id'],
      },
      handler: (args) async {
        final warning = await connectOrWarn(vm);
        final id = args['id'] as String?;
        if (id == null) throw ToolException('id is required');
        final index = vm.indexOfLog(id);
        if (index < 0) {
          throw ToolException('No console log with id "$id" in buffer');
        }
        final radius = (asInt(args['contextLines']) ?? 5).clamp(0, 50);
        return {
          if (warning != null) 'warning': warning,
          'entry': vm.logs[index].toFull(),
          'context': [for (final e in vm.logsAround(index, radius)) e.toFull()],
        };
      },
    );

ToolDef searchConsoleLogsTool(VmClient vm) => ToolDef(
      name: 'search_console_logs',
      description:
          'grep-style search of buffered console output (case-insensitive), '
          'newest first. Each match comes with a few surrounding entries.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string'},
          'regex': {
            'type': 'boolean',
            'default': false,
            'description': 'Treat query as a regular expression',
          },
          'contextLines': {'type': 'integer', 'default': 2, 'maximum': 20},
          'limit': {'type': 'integer', 'default': 30, 'maximum': 100},
        },
        'required': ['query'],
      },
      handler: (args) async {
        final query = args['query'] as String?;
        if (query == null || query.isEmpty) {
          throw ToolException('query is required');
        }
        final warning = await connectOrWarn(vm);
        final useRegex = args['regex'] as bool? ?? false;
        final pattern = RegExp(
          useRegex ? query : RegExp.escape(query),
          caseSensitive: false,
        );
        final radius = (asInt(args['contextLines']) ?? 2).clamp(0, 20);
        final limit = (asInt(args['limit']) ?? 30).clamp(1, 100);

        final logs = vm.logs;
        final hits = <Map<String, dynamic>>[];
        for (var i = logs.length - 1; i >= 0 && hits.length < limit; i--) {
          if (!pattern.hasMatch(logs[i].text)) continue;
          hits.add({
            'match': logs[i].toFull(),
            'context': [for (final e in vm.logsAround(i, radius)) e.toFull()],
          });
        }
        return {
          if (warning != null) 'warning': warning,
          'returned': hits.length,
          'items': hits,
        };
      },
    );

DateTime _timeOf(LogEntry entry) => entry.timestamp;
