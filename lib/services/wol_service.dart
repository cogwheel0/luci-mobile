import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/utils/logger.dart';
import 'package:luci_mobile/state/router_session.dart';

/// Which `luci-app-wol` a router runs, and what it can send with.
///
/// The package changed its whole interface between releases:
///
/// * **legacy** (OpenWrt 24.10 and older): config `etherwake`, and the ACL
///   grants `file.exec` on `/usr/bin/etherwake` directly.
/// * **modern** (OpenWrt 25.x / master): config `luci-wol`, a `luci.wol`
///   ubus object with `stat` and `exec`, and no `file.exec` grant at all -
///   so the legacy call is refused even when etherwake is installed.
class WolBackend {
  const WolBackend.legacy() : modern = false, etherwake = true, wakeonlan = false;

  const WolBackend.modern({required this.etherwake, required this.wakeonlan})
    : modern = true;

  final bool modern;
  final bool etherwake;
  final bool wakeonlan;
}

/// Sends a wake-on-LAN packet from the router.
///
/// From the router, not the phone: a magic packet has to reach the target's
/// broadcast domain, and the phone is often on a different one — or asleep.
class WolService {
  WolService(this._api);

  final IApiService _api;

  static const etherwake = '/usr/bin/etherwake';
  static const wakeonlan = '/usr/bin/wakeonlan';

  /// A MAC the tool will accept: lower case, colon separated.
  static String? normaliseMac(String raw) {
    final cleaned = raw.trim().toLowerCase().replaceAll('-', ':');
    final ok = RegExp(r'^([0-9a-f]{2}:){5}[0-9a-f]{2}$').hasMatch(cleaned);
    return ok ? cleaned : null;
  }

  /// Arguments for waking [mac] over [device] with etherwake.
  ///
  /// `-D` makes etherwake print what it sent, which is the only feedback
  /// there is: nothing acknowledges a magic packet.
  static List<String> argsFor(
    String mac, {
    String? device,
    bool broadcast = false,
  }) => [
    '-D',
    if (device != null && device.isNotEmpty) ...['-i', device],
    if (broadcast) '-b',
    mac,
  ];

  final Map<String, WolBackend> _backendByRouter = {};

  /// Which `luci-app-wol` this router has.
  ///
  /// `luci.wol stat` answering means the modern package. A refusal or a
  /// missing object means the legacy one (or none, which the legacy call
  /// then reports as a failed wake). Only an RPC answer is cached; a
  /// timeout is asked again next time.
  Future<WolBackend> backend(RouterSession session) async {
    final cached = _backendByRouter[session.routerId];
    if (cached != null) return cached;
    try {
      final result = await _api.call(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        object: 'luci.wol',
        method: 'stat',
      );
      final data = result is List && result.length > 1 ? result[1] : null;
      if (result is List && result.isNotEmpty && result.first == 0 && data is Map) {
        return _backendByRouter[session.routerId] = WolBackend.modern(
          etherwake: data['etherwake'] == true,
          wakeonlan: data['wakeonlan'] == true,
        );
      }
      return _backendByRouter[session.routerId] = const WolBackend.legacy();
    } on RpcException {
      return _backendByRouter[session.routerId] = const WolBackend.legacy();
    } catch (e) {
      Logger.info('Could not ask luci.wol what it supports: $e');
      return const WolBackend.legacy();
    }
  }

  /// The interface legacy `luci-app-wol` sends on: `etherwake.setup.interface`.
  ///
  /// Without `-i`, etherwake uses its compiled-in default, `eth0` — which on
  /// a DSA or swconfig router is the switch conduit, not the LAN bridge, so
  /// the frame never reaches a port. Null when the config cannot be read.
  ///
  /// Only an answer is kept. A read that failed - a timeout, a session that
  /// had just expired - is forgotten, so the next wake asks again rather
  /// than sending on the wrong interface for the rest of the session.
  Future<String?> configuredInterface(RouterSession session) => _cachedRead(
    _interfaceByRouter,
    session,
    'etherwake',
    (values) => uciSections(values, 'etherwake')
        .map((e) => uciText(e.value['interface']))
        .firstWhere((iface) => iface != null, orElse: () => null),
  );

  /// The LAN device, for when no WoL config names one: `network.lan.device`,
  /// or `br-lan` for a pre-21.02 bridge declared with `type bridge`.
  Future<String?> lanDevice(RouterSession session) => _cachedRead(
    _lanByRouter,
    session,
    'network',
    (values) {
      final lan = values['lan'];
      if (lan is! Map) return null;
      final device = uciText(lan['device']);
      if (device != null) return device;
      return uciText(lan['type']) == 'bridge' ? 'br-lan' : null;
    },
  );

  final Map<String, ({String? value})> _interfaceByRouter = {};
  final Map<String, ({String? value})> _lanByRouter = {};

  Future<String?> _cachedRead(
    Map<String, ({String? value})> cache,
    RouterSession session,
    String config,
    String? Function(Map<String, dynamic> values) pick,
  ) async {
    final cached = cache[session.routerId];
    if (cached != null) return cached.value;
    try {
      final found = pick(await uciConfigValues(_api, session, config));
      cache[session.routerId] = (value: found);
      return found;
    } on RpcException catch (e) {
      // No config at all is an answer and is kept; only a failure to ask
      // is forgotten.
      if (e.isNotFound) {
        cache[session.routerId] = (value: null);
      } else {
        Logger.info('Could not read the $config config: $e');
      }
      return null;
    } catch (e) {
      Logger.info('Could not read the $config config: $e');
      return null;
    }
  }

  /// Returns false when the router refused or the MAC is unusable.
  ///
  /// [device] defaults to what the router's WoL config says, then the LAN
  /// device.
  Future<bool> wake(RouterSession session, String mac, {String? device}) async {
    final normalised = normaliseMac(mac);
    if (normalised == null) return false;

    final found = await backend(session);
    if (found.modern) return _wakeModern(session, normalised, found, device);

    device ??= await configuredInterface(session) ?? await lanDevice(session);
    return _execLegacy(session, argsFor(normalised, device: device));
  }

  Future<bool> _wakeModern(
    RouterSession session,
    String mac,
    WolBackend found,
    String? device,
  ) async {
    if (!found.etherwake && !found.wakeonlan) {
      Logger.warning('luci-app-wol has neither etherwake nor wakeonlan');
      return false;
    }

    // `luci-wol` holds the preferred binary and per-target options keyed by
    // MAC; honour them the way the LuCI page does.
    Map<String, dynamic> values = const {};
    try {
      values = await uciConfigValues(_api, session, 'luci-wol');
    } catch (e) {
      Logger.info('Could not read the luci-wol config: $e');
    }
    final defaults = values['defaults'];
    final preferred = defaults is Map ? uciText(defaults['executable']) : null;
    var bin = preferred ?? (found.etherwake ? etherwake : wakeonlan);
    if (bin == etherwake && !found.etherwake) bin = wakeonlan;
    if (bin == wakeonlan && !found.wakeonlan) bin = etherwake;

    final target = uciSections(values, 'target')
        .map((e) => e.value)
        .where((t) => normaliseMac(uciText(t['mac']) ?? '') == mac)
        .firstOrNull;

    final List<String> args;
    if (bin == etherwake) {
      device ??=
          uciText(target?['iface']) ??
          await configuredInterface(session) ??
          await lanDevice(session);
      args = argsFor(
        mac,
        device: device,
        broadcast: uciText(target?['broadcast']) == '1',
      );
    } else {
      // wakeonlan takes no interface; it broadcasts over UDP.
      args = [mac];
    }

    final dynamic result;
    try {
      result = await _api.call(
        session.ipAddress,
        session.sysauth,
        session.useHttps,
        object: 'luci.wol',
        method: 'exec',
        params: {'name': bin, 'args': args},
      );
    } on RpcException catch (e, stack) {
      Logger.exception('luci.wol exec was refused', e, stack);
      return false;
    }
    if (result is! List || result.isEmpty || result.first != 0) return false;
    final data = result.length > 1 ? result[1] : null;
    if (data is! Map) return false;
    if (data['stderr'] == 'disallowed') return false;
    return data['code'] == 0;
  }

  /// Legacy `luci-app-wol`: `file.exec` on etherwake's exact path, which is
  /// all its ACL grants. Measured on OpenWrt 24.10: an arbitrary binary is
  /// refused with status 6 even for root.
  Future<bool> _execLegacy(RouterSession session, List<String> args) async {
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
        params: {'command': etherwake, 'params': args},
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
