## 0.1.0

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
