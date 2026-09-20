/// The bottom-navigation destinations.
///
/// Deliberately an enum rather than an `int`. Tab positions moved when the
/// shell went from four destinations to five, and every hardcoded index
/// (`requestTab(2)` for Interfaces, `index != 3` for the reboot lockout)
/// silently pointed somewhere else. Naming them makes that a compile error.
enum LuciTab {
  dashboard,
  network,
  clients,
  insights,
  settings;

  /// Whether this destination stays usable while the router is rebooting.
  ///
  /// Everything else reads live router state, so it has nothing to show —
  /// but Settings is where the reboot was started and where the user waits.
  bool get allowedDuringReboot => this == LuciTab.settings;

  /// Enums already expose `.index`; this is the inverse.
  static LuciTab fromIndex(int index) =>
      index >= 0 && index < LuciTab.values.length
      ? LuciTab.values[index]
      : LuciTab.dashboard;
}
