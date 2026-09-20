import 'dart:convert';

import 'package:luci_mobile/models/station_info.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/utils/logger.dart';

/// Per-router, on-device display names for clients.
///
/// This is the default "rename", and deliberately so. The router-side
/// alternative is the `dhcp` host `name` option, which is a DNS record rather
/// than the device's hostname: the device carries on announcing its old name,
/// so users read the rename as broken. It is also the one write that can stop
/// dnsmasq and take LAN DNS down without making the router unreachable — which
/// means `uci.apply`'s rollback timer would not catch it.
///
/// A local alias has neither problem, works for wired and static-IP devices
/// that have no host section at all, and matches what the UniFi app does.
/// Setting the DHCP hostname stays available as an explicit extra step.
class ClientAliasStore {
  ClientAliasStore(this._storage);

  final SecureStorageService _storage;

  static String storageKey(String routerId) => 'client_aliases:$routerId';

  /// MAC (normalized) -> alias. Empty when nothing is stored or storage fails.
  Future<Map<String, String>> load(String routerId) async {
    try {
      final raw = await _storage.readValue(storageKey(routerId));
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return {
        for (final entry in decoded.entries)
          StationInfo.normalizeMac(entry.key.toString()): entry.value
              .toString(),
      };
    } catch (e, stack) {
      Logger.exception('Failed to read client aliases', e, stack);
      return const {};
    }
  }

  Future<String?> aliasFor(String routerId, String mac) async {
    final all = await load(routerId);
    return all[StationInfo.normalizeMac(mac)];
  }

  /// Stores [alias] for [mac], or clears it when [alias] is null or blank.
  ///
  /// Returns false when storage rejected the write, so the UI can say so
  /// rather than showing a rename that did not stick.
  Future<bool> setAlias(String routerId, String mac, String? alias) async {
    final key = StationInfo.normalizeMac(mac);
    final current = Map<String, String>.from(await load(routerId));
    if (alias == null || alias.trim().isEmpty) {
      current.remove(key);
    } else {
      current[key] = alias.trim();
    }
    try {
      if (current.isEmpty) {
        await _storage.deleteValue(storageKey(routerId));
      } else {
        await _storage.writeValue(storageKey(routerId), jsonEncode(current));
      }
      return true;
    } catch (e, stack) {
      Logger.exception('Failed to save client alias', e, stack);
      return false;
    }
  }
}
