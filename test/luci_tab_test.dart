import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/navigation/luci_tab.dart';

/// The shell went from four destinations to five, which silently re-pointed
/// every hardcoded index. These pin the contract the enum replaced them with.
void main() {
  test('the destination order is the one the shell renders', () {
    expect(LuciTab.values, [
      LuciTab.dashboard,
      LuciTab.network,
      LuciTab.clients,
      LuciTab.insights,
      LuciTab.settings,
    ]);
  });

  test('index and fromIndex round-trip', () {
    for (final tab in LuciTab.values) {
      expect(LuciTab.fromIndex(tab.index), tab);
    }
  });

  // A NavigationBar can hand back any index; falling back to a real tab beats
  // a range error in the shell.
  test('an out-of-range index falls back rather than throwing', () {
    expect(LuciTab.fromIndex(-1), LuciTab.dashboard);
    expect(LuciTab.fromIndex(99), LuciTab.dashboard);
  });

  // Everything else reads live router state and has nothing to show mid-reboot;
  // Settings is where the reboot was started and where the user waits it out.
  test('only Settings stays reachable during a reboot', () {
    expect(LuciTab.settings.allowedDuringReboot, isTrue);
    for (final tab in LuciTab.values.where((t) => t != LuciTab.settings)) {
      expect(tab.allowedDuringReboot, isFalse, reason: tab.name);
    }
  });
}
