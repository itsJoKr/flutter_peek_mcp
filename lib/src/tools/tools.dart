import '../mcp_server.dart';
import '../noise_filter.dart';
import '../vm_client.dart';
import 'app_tools.dart';
import 'console_tools.dart';
import 'http_tools.dart';

/// All flutter-peek tools, reading from [vm] and hiding URLs that match
/// [noise] by default.
List<ToolDef> buildTools(VmClient vm, NoiseFilter noise) => [
      isAppConnectedTool(vm),
      connectTool(vm),
      listHttpRequestsTool(vm, noise),
      getHttpRequestTool(vm),
      getHttpRequestsWithBodiesTool(vm, noise),
      searchHttpRequestsTool(vm, noise),
      httpSummaryTool(vm, noise),
      listConsoleLogsTool(vm),
      getConsoleLogTool(vm),
      searchConsoleLogsTool(vm),
      contextAroundTool(vm, noise),
      clearBuffersTool(vm),
    ];
