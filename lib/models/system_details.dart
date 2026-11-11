/// A row of the dashboard's System details sheet: what LuCI's Status >
/// Overview shows beyond model and version (#14).
enum SystemDetail {
  hostname,
  model,
  architecture,
  target,
  firmware,
  kernel;

  /// The rows for a `system board` reply, in LuCI's order, leaving out
  /// whatever the router did not report.
  static List<(SystemDetail, String)> of(Map<String, dynamic>? boardInfo) {
    final release = boardInfo?['release'];
    String? text(Object? v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    return [
      for (final (field, value) in [
        (hostname, text(boardInfo?['hostname'])),
        (model, text(boardInfo?['model'])),
        // `system` is the CPU, e.g. "MediaTek MT7621 ver:1 eco:3": what
        // LuCI labels Architecture.
        (architecture, text(boardInfo?['system'])),
        (target, release is Map ? text(release['target']) : null),
        // The full release line, e.g. "OpenWrt 24.10.0 r28427-6df0e3d02a".
        (firmware, release is Map ? text(release['description']) : null),
        (kernel, text(boardInfo?['kernel'])),
      ])
        if (value != null) (field, value),
    ];
  }
}
