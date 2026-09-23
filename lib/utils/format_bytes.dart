import 'dart:math' as math;

/// Human-readable byte count: `1.5 MB`, `0 B`.
///
/// One copy for the traffic, client and interface screens, which had each
/// grown their own and were rounding differently.
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  final i = (math.log(bytes) / math.log(1024)).floor().clamp(
    0,
    suffixes.length - 1,
  );
  return '${(bytes / math.pow(1024, i)).toStringAsFixed(decimals)} '
      '${suffixes[i]}';
}
