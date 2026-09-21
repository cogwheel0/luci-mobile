import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/utils/logger.dart';
import 'package:luci_mobile/state/router_session.dart';

/// Sends a wake-on-LAN packet from the router.
///
/// From the router, not the phone: a magic packet has to reach the target's
/// broadcast domain, and the phone is often on a different one — or asleep.
///
/// Goes through `/usr/bin/etherwake`, which is the path `luci-app-wol`'s ACL
/// grants `exec` on. Measured on OpenWrt 24.10: `file.exec` is granted
/// per exact command path, so an arbitrary binary is refused with status 6
/// even for root.
class WolService {
  const WolService(this._api);

  final IApiService _api;

  static const etherwake = '/usr/bin/etherwake';

  /// A MAC the tool will accept: lower case, colon separated.
  static String? normaliseMac(String raw) {
    final cleaned = raw.trim().toLowerCase().replaceAll('-', ':');
    final ok = RegExp(r'^([0-9a-f]{2}:){5}[0-9a-f]{2}$').hasMatch(cleaned);
    return ok ? cleaned : null;
  }

  /// Arguments for waking [mac] over [device].
  ///
  /// `-D` makes etherwake print what it sent, which is the only feedback
  /// there is: nothing acknowledges a magic packet.
  static List<String> argsFor(String mac, {String? device}) => [
    '-D',
    if (device != null && device.isNotEmpty) ...['-i', device],
    mac,
  ];

  /// The interface `luci-app-wol` sends on: `etherwake.setup.interface`.
  ///
  /// Without `-i`, etherwake uses its compiled-in default, `eth0` — which on
  /// a DSA or swconfig router is the switch conduit, not the LAN bridge, so
  /// the frame never reaches a port. Null when the config cannot be read.
  Future<String?> configuredInterface(RouterSession session) async {
    try {
      final values = uciValuesOf(
        await _api.uciGetAll(
          session.ipAddress,
          session.sysauth,
          session.useHttps,
          config: 'etherwake',
        ),
      );
      for (final section in values.values) {
        if (section is! Map || section['.type'] != 'etherwake') continue;
        final iface = section['interface']?.toString().trim();
        if (iface != null && iface.isNotEmpty) return iface;
      }
    } catch (e, stack) {
      Logger.exception('etherwake config unavailable', e, stack);
    }
    return null;
  }

  /// Returns false when the router refused or the MAC is unusable.
  ///
  /// [device] defaults to what [configuredInterface] reports.
  Future<bool> wake(RouterSession session, String mac, {String? device}) async {
    final normalised = normaliseMac(mac);
    if (normalised == null) return false;
    device ??= await configuredInterface(session);

    // `call` throws RpcException for an RPC-level refusal — most often the
    // ACL not granting exec on this path — so catching it here is what makes
    // the documented `false` reachable instead of an exception escaping past
    // it.
    final dynamic result;
    try {
      result = await _api.call(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        object: 'file',
        method: 'exec',
        params: {
          'command': etherwake,
          'params': argsFor(normalised, device: device),
        },
      );
    } on RpcException catch (e, stack) {
      Logger.exception('etherwake was refused', e, stack);
      return false;
    }
    if (result is! List || result.isEmpty || result.first != 0) return false;
    final data = result.length > 1 ? result[1] : null;
    return data is! Map || data['code'] == 0;
  }
}
