## Unreleased

- Finds the app without `--vmservice-out-file`. With Flutter 3.44 or later,
  `flutter run` starts a Dart Tooling Daemon, and the server asks it for the
  app that was started in the agent's project folder. With several apps of
  the project, the agent picks one with `connect` instead of the server
  guessing. The URI file still comes first when its app is running.
- `is_app_connected` and `connect` return the app's name, with its device.
- New `--[no-]discover` option.

## 1.0.0

- First public release.
- Tools for console logs (`list_console_logs`, `get_console_log`,
  `search_console_logs`) and HTTP traffic (`list_http_requests`,
  `get_http_request`, `get_http_requests_with_bodies`, `search_http_requests`,
  `http_summary`), plus `get_context_around`, `is_app_connected`, `connect`
  and `clear_buffers`.
- Finds the app through `flutter run --vmservice-out-file`, or through a URI
  given to the `connect` tool. Reconnects after hot and full restarts.
- Keeps buffered data after the app disconnects.
- Redacts credential headers by default.
- Keeps tool responses below MCP output limits. Long bodies can be read in
  parts, and binary bodies are fetched only on demand.
