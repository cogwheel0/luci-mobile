import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/client_config_planner.dart';
import 'package:luci_mobile/models/wireless_config.dart';

/// Reads and edits `/etc/config/wireless`.
///
/// Pure functions of an already-fetched config, so the rules — which options
/// a security change must clear, what makes a passphrase valid, how a guest
/// network differs from a normal one — are testable without a radio.
class WirelessPlanner {
  const WirelessPlanner._();

  /// WPA-PSK passphrases are 8-63 characters; hostapd refuses anything else
  /// and the radio then fails to come up.
  static const int minPassphrase = 8;
  static const int maxPassphrase = 63;

  /// SSIDs are at most 32 bytes.
  static const int maxSsidBytes = 32;

  static String? _str(dynamic v) {
    if (v == null) return null;
    if (v is List) return v.isEmpty ? null : v.first.toString();
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static bool _bool(dynamic v, {bool orElse = false}) =>
      ClientConfigPlanner.uciBool(v, orElse: orElse);

  static List<String> _list(dynamic v) => ClientConfigPlanner.uciList(v);

  /// Builds the radio list, each with its SSIDs attached.
  static List<WirelessRadio> parse(Map<String, dynamic> values) {
    final radios = <String, WirelessRadio>{};
    final networks = <WirelessNetwork>[];

    for (final entry in values.entries) {
      final s = entry.value;
      if (s is! Map) continue;
      switch (s['.type']) {
        case 'wifi-device':
          radios[entry.key] = WirelessRadio(
            section: entry.key,
            band: _str(s['band']) ?? _hwmodeToBand(_str(s['hwmode'])),
            channel: _str(s['channel']),
            htmode: _str(s['htmode']),
            country: _str(s['country']),
            txpower: _str(s['txpower']),
            disabled: _bool(s['disabled']),
          );
        case 'wifi-iface':
          final device = _str(s['device']);
          if (device == null) continue;
          networks.add(
            WirelessNetwork(
              section: entry.key,
              device: device,
              ssid: _str(s['ssid']),
              mode: _str(s['mode']) ?? 'ap',
              encryption: _str(s['encryption']),
              key: _str(s['key']),
              network: _list(s['network']),
              hidden: _bool(s['hidden']),
              isolate: _bool(s['isolate']),
              disabled: _bool(s['disabled']),
            ),
          );
      }
    }

    return [
      for (final radio in radios.values)
        radio.withNetworks(
          networks.where((n) => n.device == radio.section).toList(),
        ),
    ];
  }

  /// Pre-`band` configs used `hwmode` (`11g`, `11a`).
  static String? _hwmodeToBand(String? hwmode) => switch (hwmode) {
    '11g' || '11b' || '11ng' => '2g',
    '11a' || '11na' || '11ac' => '5g',
    _ => null,
  };

  // ------------------------------------------------------------ validation

  static bool isValidSsid(String ssid) {
    final bytes = ssid.runes.fold<int>(
      0,
      (sum, r) =>
          sum + (r < 0x80 ? 1 : (r < 0x800 ? 2 : (r < 0x10000 ? 3 : 4))),
    );
    return ssid.isNotEmpty && bytes <= maxSsidBytes;
  }

  static bool isValidPassphrase(String key) =>
      key.length >= minPassphrase && key.length <= maxPassphrase;

  // -------------------------------------------------------------- planning

  /// Enables or disables one SSID without touching anything else.
  static List<UciOperation> planSetEnabled({
    required WirelessNetwork network,
    required bool enabled,
  }) => [
    UciSet(
      'wireless',
      section: network.section,
      values: {'disabled': enabled ? '0' : '1'},
    ),
  ];

  /// Enables or disables a whole radio.
  static List<UciOperation> planSetRadioEnabled({
    required WirelessRadio radio,
    required bool enabled,
  }) => [
    UciSet(
      'wireless',
      section: radio.section,
      values: {'disabled': enabled ? '0' : '1'},
    ),
  ];

  /// Applies an edit to an existing SSID.
  ///
  /// Switching to an open network removes `key` rather than leaving a stale
  /// passphrase behind in the config file, where it would be readable by
  /// anyone who can view the config and misleading to anyone reading it.
  static List<UciOperation> planUpdateNetwork({
    required WirelessNetwork existing,
    required String ssid,
    required WirelessSecurity security,
    String? passphrase,
    bool? hidden,
    bool? isolate,
  }) {
    // `psk-mixed` and `psk` both read back as wpa2 for display, but their
    // uciValue is `psk2`. Writing that on an SSID rename would silently
    // narrow the network and drop every WPA/TKIP client off it, so the
    // option is only touched when the user actually picked something else.
    final securityChanged =
        WirelessSecurity.fromUci(existing.encryption) != security;

    final values = <String, String>{
      'ssid': ssid,
      if (securityChanged) 'encryption': security.uciValue,
      if (hidden != null) 'hidden': hidden ? '1' : '0',
      if (isolate != null) 'isolate': isolate ? '1' : '0',
    };
    if (security.needsPassphrase && passphrase != null) {
      values['key'] = passphrase;
    }

    final ops = <UciOperation>[
      UciSet('wireless', section: existing.section, values: values),
    ];
    if (!security.needsPassphrase && existing.key != null) {
      ops.add(UciRemove('wireless', section: existing.section, option: 'key'));
    }
    return ops;
  }

  /// Adds a new SSID to [radio].
  static List<UciOperation> planCreateNetwork({
    required WirelessRadio radio,
    required String ssid,
    required WirelessSecurity security,
    String? passphrase,
    List<String> network = const ['lan'],
    bool hidden = false,
    bool isolate = false,
  }) => [
    UciAdd(
      'wireless',
      type: 'wifi-iface',
      values: {
        'device': radio.section,
        'mode': 'ap',
        'ssid': ssid,
        'encryption': security.uciValue,
        if (security.needsPassphrase && passphrase != null) 'key': passphrase,
        'network': network.join(' '),
        if (hidden) 'hidden': '1',
        if (isolate) 'isolate': '1',
      },
    ),
  ];

  /// Removes an SSID.
  static List<UciOperation> planDeleteNetwork(WirelessNetwork network) => [
    UciRemove('wireless', section: network.section),
  ];

  /// Changes radio-level settings. Only the fields given are written.
  ///
  /// [clearHtmode] and [clearCountry] remove the option, handing the choice
  /// back to the driver (or the regulatory default). Distinct from leaving
  /// the argument null, which means "not touched".
  static List<UciOperation> planUpdateRadio({
    required WirelessRadio radio,
    String? channel,
    String? htmode,
    String? country,
    String? txpower,
    bool clearHtmode = false,
    bool clearCountry = false,
  }) {
    final values = <String, String>{
      'channel': ?channel,
      if (!clearHtmode) 'htmode': ?htmode,
      if (!clearCountry) 'country': ?country,
      'txpower': ?txpower,
    };
    return [
      if (values.isNotEmpty)
        UciSet('wireless', section: radio.section, values: values),
      if (clearHtmode && radio.htmode != null)
        UciRemove('wireless', section: radio.section, option: 'htmode'),
      if (clearCountry && radio.country != null)
        UciRemove('wireless', section: radio.section, option: 'country'),
    ];
  }

  /// The channels worth offering for a band.
  ///
  /// `auto` first, because letting the radio pick is right more often than a
  /// hand-chosen channel and is what most users want.
  static List<String> channelsFor(String? band) => switch (band) {
    '5g' => const [
      'auto',
      '36',
      '40',
      '44',
      '48',
      '52',
      '56',
      '60',
      '64',
      '100',
      '104',
      '108',
      '112',
      '116',
      '120',
      '124',
      '128',
      '132',
      '136',
      '140',
      '149',
      '153',
      '157',
      '161',
      '165',
    ],
    '6g' => const ['auto', '1', '5', '9', '13', '17', '21', '25', '29', '33'],
    _ => const [
      'auto',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
      '9',
      '10',
      '11',
      '12',
      '13',
    ],
  };

  /// Channel widths a band can actually use.
  static List<String> htmodesFor(String? band) => switch (band) {
    '5g' => const [
      'HT20',
      'HT40',
      'VHT20',
      'VHT40',
      'VHT80',
      'VHT160',
      'HE20',
      'HE40',
      'HE80',
      'HE160',
      'EHT20',
      'EHT40',
      'EHT80',
      'EHT160',
    ],
    '6g' => const [
      'HE20',
      'HE40',
      'HE80',
      'HE160',
      'EHT80',
      'EHT160',
      'EHT320',
    ],
    _ => const ['HT20', 'HT40', 'HE20', 'HE40', 'EHT20', 'EHT40'],
  };
}
