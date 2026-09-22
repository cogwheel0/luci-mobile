import 'package:flutter/widgets.dart';

import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/state/router_session.dart';
import 'package:luci_mobile/utils/logger.dart';

/// Reads what one router supports, so features can hide or explain themselves
/// instead of failing at the point of use.
///
/// The happy path is two RPCs: `uci.configs` for which packages are
/// configured, and `session.list` for the whole ubus ACL at once. When a
/// restricted login cannot read the session list, it falls back to a handful
/// of `session.access` checks.
///
/// Every probe is best-effort. A failure yields [RouterCapabilities.probeFailed],
/// which the UI must render as "couldn't check" — never as "not supported".
class CapabilityService {
  CapabilityService(this._api, {DateTime Function() clock = DateTime.now})
    : _clock = clock;

  final IApiService _api;
  final DateTime Function() _clock;

  /// Configs worth checking one at a time when `uci.configs` is denied.
  ///
  /// Measured on stock OpenWrt 24.10: a normal root LuCI session is granted
  /// uci get/set/add/delete/changes/apply/confirm but *not* `configs`. Gating
  /// the whole probe on it would report every package-backed feature as
  /// "couldn't check" on a default install.
  static const List<String> _knownConfigs = [
    'dhcp',
    'firewall',
    'network',
    'wireless',
    'system',
    'dropbear',
    'uhttpd',
    'sqm',
    'ddns',
    'adblock',
    'nlbwmon',
    'upnpd',
    'openvpn',
    // `luci-app-wol` ships this; without it in the list the wake control
    // stays gated off on a router that can in fact wake devices, because
    // `uci.configs` is denied on a stock box and this list is the only
    // other way the probe learns what is installed.
    'etherwake',
  ];

  /// The objects and functions worth checking one at a time when the router
  /// will not hand over its whole ACL.
  static const Map<String, List<String>> _fallbackProbes = {
    'uci': ['set', 'apply', 'confirm', 'rollback'],
    'system': ['reboot'],
    'iwinfo': ['assoclist', 'scan'],
    'luci-rpc': ['getHostHints'],
    'luci': ['getRealtimeStats'],
    'rc': ['init'],
  };

  Future<RouterCapabilities> probe(
    RouterSession session, {
    BuildContext? context,
  }) async {
    final results = await Future.wait([
      _safe(
        'uci.configs',
        () => _api.uciConfigs(
          session.ipAddress,
          session.sysauth,
          session.useHttps,
          context: context,
        ),
      ),
      _safe(
        'luci.getFeatures',
        () => _api.luciGetFeatures(
          session.ipAddress,
          session.sysauth,
          session.useHttps,
        ),
      ),
      _safe(
        'session.list',
        () => _api.fetchSessionAcl(
          session.ipAddress,
          session.sysauth,
          session.useHttps,
        ),
      ),
    ]);

    var configs = results[0] as List<String>?;
    final features = results[1] as Map<String, dynamic>?;
    var acl = results[2] as Map<String, Set<String>>?;

    // `uci.configs` is not granted to a stock LuCI session, so falling back to
    // reading each interesting config is the normal path, not the exception.
    // An empty list is not an answer either: the RPC layer returns one for an
    // unrecognised payload shape, and a router with zero configs does not
    // exist. Treating it as authoritative tells the user to install packages
    // they already have.
    if (configs == null || configs.isEmpty) {
      configs = await _probeConfigsIndividually(session);
    }

    // Both routes failing means we genuinely learned nothing: reporting every
    // package-gated feature as missing would be worse than admitting that.
    if (configs == null) {
      Logger.warning('Capability probe failed for ${session.ipAddress}');
      return RouterCapabilities(probeFailed: true, probedAt: _clock());
    }

    // An empty map is not an answer either, for the same reason an empty
    // config list is not: the RPC layer produces one for a payload shape it
    // did not recognise, and taken as authoritative it denies every write -
    // including the rollback that keeps a user from locking themselves out.
    var unprobed = const <String>{};
    if (acl == null || acl.isEmpty) {
      final fallback = await _probeAclIndividually(session);
      acl = fallback?.acl;
      unprobed = fallback?.unprobed ?? const {};
    }

    return RouterCapabilities(
      uciConfigs: configs.toSet(),
      features: features ?? const <String, dynamic>{},
      ubusAcl: acl,
      unprobedFunctions: unprobed,
      probedAt: _clock(),
    );
  }

  /// Determines which configs exist by reading them one at a time.
  ///
  /// Returns null only when *every* read failed, which means the router is
  /// unreachable rather than sparsely configured.
  Future<List<String>?> _probeConfigsIndividually(RouterSession session) async {
    final answers = await Future.wait([
      for (final config in _knownConfigs)
        _safe('uci.get $config', () async {
          await _api.uciGetAll(
            session.ipAddress,
            session.sysauth,
            session.useHttps,
            config: config,
          );
          return true;
        }),
    ]);

    final present = <String>[];
    var answered = false;
    for (var i = 0; i < _knownConfigs.length; i++) {
      if (answers[i] == null) continue;
      answered = true;
      present.add(_knownConfigs[i]);
    }
    return answered ? present : null;
  }

  /// Builds an ACL map from individual `session.access` checks.
  ///
  /// Returns null when nothing could be determined, which
  /// [RouterCapabilities.allows] treats as "assume permitted" rather than
  /// hiding every write behind a guess. A probe that answered for some
  /// functions and not others reports the rest as [unprobed]: an unanswered
  /// probe is not a denial, and mistaking one for the other on
  /// `uci.rollback` would drop rollback protection over a timeout.
  Future<({Map<String, Set<String>> acl, Set<String> unprobed})?>
  _probeAclIndividually(RouterSession session) async {
    final pairs = <(String, String)>[
      for (final entry in _fallbackProbes.entries)
        for (final fn in entry.value) (entry.key, fn),
    ];

    final answers = await Future.wait([
      for (final (object, fn) in pairs)
        _safe(
          'session.access $object.$fn',
          () => _api.checkUbusAccess(
            session.ipAddress,
            session.sysauth,
            session.useHttps,
            object: object,
            function: fn,
          ),
        ),
    ]);

    final acl = <String, Set<String>>{};
    final unprobed = <String>{};
    var answered = false;
    for (var i = 0; i < pairs.length; i++) {
      final (object, fn) = pairs[i];
      final allowed = answers[i];
      if (allowed == null) {
        unprobed.add('$object.$fn');
        continue;
      }
      answered = true;
      if (allowed == true) {
        acl.putIfAbsent(object, () => <String>{}).add(fn);
      }
    }
    return answered ? (acl: acl, unprobed: unprobed) : null;
  }

  /// Runs [body], logging and swallowing any failure.
  Future<T?> _safe<T>(String what, Future<T?> Function() body) async {
    try {
      return await body();
    } catch (e, stack) {
      Logger.exception('Capability probe: $what failed', e, stack);
      return null;
    }
  }
}
