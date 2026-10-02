/// Header names whose values are replaced before they are stored, so
/// credentials never reach the agent's context.
const sensitiveHeaders = {
  'authorization',
  'proxy-authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
  'x-auth-token',
};

const redactedValue = '<redacted>';

Map<String, dynamic> redactSensitiveHeaders(Map<String, dynamic> headers) {
  return {
    for (final entry in headers.entries)
      entry.key: sensitiveHeaders.contains(entry.key.toLowerCase())
          ? redactedValue
          : entry.value,
  };
}
