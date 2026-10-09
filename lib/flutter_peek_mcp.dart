/// MCP server that exposes a running Flutter app's console logs and HTTP
/// traffic to AI coding agents through the Dart VM service.
library;

export 'src/dtd_discovery.dart' show DtdDiscovery;
export 'src/mcp_server.dart' show McpServer, ToolDef;
export 'src/noise_filter.dart' show NoiseFilter;
export 'src/tools/tools.dart' show buildTools;
export 'src/version.dart' show packageVersion;
export 'src/vm_client.dart' show VmClient, VmConnectionException;
