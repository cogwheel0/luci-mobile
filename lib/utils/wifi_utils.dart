/// Format GL.iNet/UCI band string to human-readable label.
String formatWifiBand(String band) {
  switch (band.toLowerCase()) {
    case '2g':
    case '2.4g':
      return '2.4 GHz';
    case '5g':
      return '5 GHz';
    case '6g':
      return '6 GHz';
    default:
      return '';
  }
}

/// Returns a usable Wi-Fi channel, ignoring common placeholder values.
String? normalizeWifiChannel(Object? value) {
  final channel = value?.toString().trim() ?? '';
  if (channel.isEmpty ||
      const {
        '0',
        'auto',
        'n/a',
        'na',
        'unknown',
        '--',
      }.contains(channel.toLowerCase())) {
    return null;
  }
  return channel;
}

/// Chooses an actual radio channel before its configured fallback.
String resolveWifiChannel({Object? actual, Object? configured}) =>
    normalizeWifiChannel(actual) ?? normalizeWifiChannel(configured) ?? 'N/A';

/// Extracts a scalar string from a UCI value that may be list-valued.
String uciString(Object? value, [String fallback = '']) {
  if (value is List) return value.isEmpty ? fallback : value.first.toString();
  return value?.toString() ?? fallback;
}
