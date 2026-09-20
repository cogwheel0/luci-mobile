import 'package:flutter/foundation.dart';

/// A radio (`wifi-device`) out of `/etc/config/wireless`.
@immutable
class WirelessRadio {
  const WirelessRadio({
    required this.section,
    this.band,
    this.channel,
    this.htmode,
    this.country,
    this.txpower,
    this.disabled = false,
    this.networks = const [],
  });

  /// UCI section id, e.g. `radio0`.
  final String section;

  /// `2g`, `5g`, `6g` — absent on older configs that only carry `hwmode`.
  final String? band;

  /// `auto`, or a channel number as text.
  final String? channel;

  /// `HT20`, `VHT80`, `HE160`, …
  final String? htmode;
  final String? country;
  final String? txpower;
  final bool disabled;

  /// The SSIDs hosted on this radio.
  final List<WirelessNetwork> networks;

  /// A human label: the band if known, else the section name.
  String get label => switch (band) {
    '2g' => '2.4 GHz',
    '5g' => '5 GHz',
    '6g' => '6 GHz',
    _ => section,
  };

  WirelessRadio withNetworks(List<WirelessNetwork> networks) => WirelessRadio(
    section: section,
    band: band,
    channel: channel,
    htmode: htmode,
    country: country,
    txpower: txpower,
    disabled: disabled,
    networks: networks,
  );
}

/// An SSID (`wifi-iface`) out of `/etc/config/wireless`.
@immutable
class WirelessNetwork {
  const WirelessNetwork({
    required this.section,
    required this.device,
    this.ssid,
    this.mode = 'ap',
    this.encryption,
    this.key,
    this.network = const [],
    this.hidden = false,
    this.isolate = false,
    this.disabled = false,
  });

  final String section;

  /// The radio section this SSID lives on.
  final String device;

  final String? ssid;

  /// `ap`, `sta`, `mesh`, `adhoc`.
  final String mode;

  /// UCI encryption token: `none`, `psk2`, `sae`, `sae-mixed`, `owe`, …
  final String? encryption;
  final String? key;

  /// Networks (firewall/bridge membership) this SSID is attached to.
  final List<String> network;

  final bool hidden;

  /// Client isolation — stations cannot talk to each other.
  final bool isolate;

  final bool disabled;

  bool get isAccessPoint => mode == 'ap';
  bool get isOpen => encryption == null || encryption == 'none';

  /// True when this looks like a guest network: an AP that isolates its
  /// clients and is not attached to the LAN.
  bool get looksLikeGuest =>
      isAccessPoint && isolate && !network.contains('lan');

  WirelessNetwork copyWith({
    String? ssid,
    String? encryption,
    String? key,
    bool clearKey = false,
    List<String>? network,
    bool? hidden,
    bool? isolate,
    bool? disabled,
  }) => WirelessNetwork(
    section: section,
    device: device,
    ssid: ssid ?? this.ssid,
    mode: mode,
    encryption: encryption ?? this.encryption,
    key: clearKey ? null : (key ?? this.key),
    network: network ?? this.network,
    hidden: hidden ?? this.hidden,
    isolate: isolate ?? this.isolate,
    disabled: disabled ?? this.disabled,
  );
}

/// What a given encryption choice requires of the user.
enum WirelessSecurity {
  none('none'),
  wpa2('psk2'),
  wpa2wpa3('sae-mixed'),
  wpa3('sae'),
  owe('owe');

  const WirelessSecurity(this.uciValue);

  final String uciValue;

  bool get needsPassphrase =>
      this == WirelessSecurity.wpa2 ||
      this == WirelessSecurity.wpa2wpa3 ||
      this == WirelessSecurity.wpa3;

  /// Maps a UCI token onto a choice the UI offers.
  ///
  /// UCI encryption values carry cipher suffixes (`psk2+ccmp`), and
  /// enterprise modes (`wpa2`, `wpa3`) are deliberately *not* mapped: editing
  /// an EAP network here would silently drop its RADIUS settings.
  static WirelessSecurity? fromUci(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final base = raw.split('+').first.trim().toLowerCase();
    return switch (base) {
      'none' => WirelessSecurity.none,
      'psk2' || 'psk-mixed' || 'psk' => WirelessSecurity.wpa2,
      'sae-mixed' => WirelessSecurity.wpa2wpa3,
      'sae' => WirelessSecurity.wpa3,
      'owe' => WirelessSecurity.owe,
      _ => null,
    };
  }

  /// True when the raw UCI value is something this editor must not touch.
  static bool isEnterprise(String? raw) {
    if (raw == null) return false;
    final base = raw.split('+').first.trim().toLowerCase();
    return base.startsWith('wpa') || base.contains('eap');
  }
}
