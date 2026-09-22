import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
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
  WolService(this._api);

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
  ///
  /// Read once per router and kept: the config does not change between
  /// wakes, and a router without `luci-app-wol` has no config to read at
  /// all, which is not worth a failed round trip on every tap.
  ///
  /// Only an answer is kept. A read that failed - a timeout, a session that
  /// had just expired - is forgotten, so the next wake asks again rather
  /// than sending on the wrong interface for the rest of the session.
  Future<String?> configuredInterface(RouterSession session) async {
    final cached = _interfaceByRouter[session.routerId];
    if (cached != null) return cached.value;
    try {
      final values = await uciConfigValues(_api, session, 'etherwake');
      final found = uciSections(values, 'etherwake')
          .map((e) => uciText(e.value['interface']))
          .firstWhere((iface) => iface != null, orElse: () => null);
      _interfaceByRouter[session.routerId] = (value: found);
      return found;
    } on RpcException catch (e) {
      // No config at all is an answer - luci-app-wol is not installed - and
      // is kept; only a failure to ask is forgotten.
      if (e.isNotFound) {
        _interfaceByRouter[session.routerId] = (value: null);
      } else {
        Logger.info('Could not read the etherwake config: $e');
      }
      return null;
    } catch (e) {
      Logger.info('Could not read the etherwake config: $e');
      return null;
    }
  }

  final Map<String, ({String? value})> _interfaceByRouter = {};

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
    // `-D` was passed so etherwake would say what it sent; a reply with no
    // exit status at all means nothing ran that we can vouch for, and this
    // return value is the only signal the user gets - nothing acknowledges
    // a magic packet.
    if (data is! Map) return false;
    return data['code'] == 0;
  }
}
