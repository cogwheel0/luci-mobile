import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/models/wireless_config.dart';
import 'package:luci_mobile/services/wireless_planner.dart';

final _config = <String, dynamic>{
  'radio0': {
    '.type': 'wifi-device',
    '.name': 'radio0',
    'band': '2g',
    'channel': '6',
    'htmode': 'HT20',
    'country': 'DE',
    'disabled': '0',
  },
  'radio1': {
    '.type': 'wifi-device',
    '.name': 'radio1',
    'hwmode': '11a', // pre-`band` config
    'channel': 'auto',
    'htmode': 'VHT80',
    'disabled': '1',
  },
  'default_radio0': {
    '.type': 'wifi-iface',
    '.name': 'default_radio0',
    'device': 'radio0',
    'mode': 'ap',
    'ssid': 'Home',
    'encryption': 'psk2+ccmp',
    'key': 'supersecret',
    'network': ['lan'],
  },
  'guest': {
    '.type': 'wifi-iface',
    '.name': 'guest',
    'device': 'radio0',
    'mode': 'ap',
    'ssid': 'Guests',
    'encryption': 'none',
    'network': 'guest',
    'isolate': '1',
    'hidden': '1',
  },
  'backhaul': {
    '.type': 'wifi-iface',
    '.name': 'backhaul',
    'device': 'radio1',
    'mode': 'sta',
    'ssid': 'Upstream',
    'encryption': 'sae',
    'key': 'meshpass1',
  },
};

void main() {
  _encryptionPreservation();

  group('parsing', () {
    test('groups SSIDs under the radio that hosts them', () {
      final radios = WirelessPlanner.parse(_config);
      expect(radios, hasLength(2));

      final r0 = radios.firstWhere((r) => r.section == 'radio0');
      expect(r0.band, '2g');
      expect(r0.label, '2.4 GHz');
      expect(r0.channel, '6');
      expect(r0.disabled, isFalse);
      expect(r0.networks.map((n) => n.ssid), ['Home', 'Guests']);

      final r1 = radios.firstWhere((r) => r.section == 'radio1');
      expect(r1.disabled, isTrue);
      expect(r1.networks.single.mode, 'sta');
    });

    // Older configs predate the `band` option; falling back to `hwmode` keeps
    // the channel and width pickers correct on them.
    test('falls back to hwmode when band is absent', () {
      final r1 = WirelessPlanner.parse(
        _config,
      ).firstWhere((r) => r.section == 'radio1');
      expect(r1.band, '5g');
      expect(r1.label, '5 GHz');
    });

    test('reads network membership as a list either way it is stored', () {
      final radios = WirelessPlanner.parse(_config);
      final home = radios[0].networks.firstWhere((n) => n.ssid == 'Home');
      final guest = radios[0].networks.firstWhere((n) => n.ssid == 'Guests');
      expect(home.network, ['lan']); // stored as a list
      expect(guest.network, ['guest']); // stored as a string
    });

    test('recognises a guest network by isolation and membership', () {
      final radios = WirelessPlanner.parse(_config);
      final home = radios[0].networks.firstWhere((n) => n.ssid == 'Home');
      final guest = radios[0].networks.firstWhere((n) => n.ssid == 'Guests');
      expect(guest.looksLikeGuest, isTrue);
      expect(guest.hidden, isTrue);
      expect(home.looksLikeGuest, isFalse);
    });

    // UCI spells booleans several ways; a hand-written `disabled 'yes'` is
    // a disabled network, not an enabled one.
    test('booleans in every UCI spelling are read', () {
      final radios = WirelessPlanner.parse({
        'radio0': {'.type': 'wifi-device', 'disabled': 'yes'},
        'net0': {
          '.type': 'wifi-iface',
          'device': 'radio0',
          'mode': 'ap',
          'ssid': 'x',
          'hidden': 'on',
          'isolate': 'off',
        },
      });
      expect(radios.single.disabled, isTrue);
      expect(radios.single.networks.single.hidden, isTrue);
      expect(radios.single.networks.single.isolate, isFalse);
    });
  });

  group('security mapping', () {
    test('strips the cipher suffix UCI carries', () {
      expect(WirelessSecurity.fromUci('psk2+ccmp'), WirelessSecurity.wpa2);
      expect(WirelessSecurity.fromUci('sae'), WirelessSecurity.wpa3);
      expect(WirelessSecurity.fromUci('sae-mixed'), WirelessSecurity.wpa2wpa3);
      expect(WirelessSecurity.fromUci('none'), WirelessSecurity.none);
      expect(WirelessSecurity.fromUci('owe'), WirelessSecurity.owe);
    });

    // Editing an EAP network here would silently drop its RADIUS settings,
    // so enterprise must not map onto an offered choice.
    test('enterprise modes are not offered as a choice', () {
      expect(WirelessSecurity.fromUci('wpa2+ccmp'), isNull);
      expect(WirelessSecurity.isEnterprise('wpa2+ccmp'), isTrue);
      expect(WirelessSecurity.isEnterprise('wpa3'), isTrue);
      expect(WirelessSecurity.isEnterprise('psk2+ccmp'), isFalse);
    });

    test('only PSK/SAE modes ask for a passphrase', () {
      expect(WirelessSecurity.wpa2.needsPassphrase, isTrue);
      expect(WirelessSecurity.wpa3.needsPassphrase, isTrue);
      expect(WirelessSecurity.none.needsPassphrase, isFalse);
      // OWE encrypts without a shared secret.
      expect(WirelessSecurity.owe.needsPassphrase, isFalse);
    });
  });

  group('validation', () {
    // hostapd refuses anything outside 8-63 and the radio then fails to come
    // up, which looks to the user like the app broke their Wi-Fi.
    test('passphrase length is bounded the way hostapd bounds it', () {
      expect(WirelessPlanner.isValidPassphrase('short'), isFalse);
      expect(WirelessPlanner.isValidPassphrase('12345678'), isTrue);
      expect(WirelessPlanner.isValidPassphrase('x' * 63), isTrue);
      expect(WirelessPlanner.isValidPassphrase('x' * 64), isFalse);
    });

    test('SSID is bounded in bytes, not characters', () {
      expect(WirelessPlanner.isValidSsid(''), isFalse);
      expect(WirelessPlanner.isValidSsid('a' * 32), isTrue);
      expect(WirelessPlanner.isValidSsid('a' * 33), isFalse);
      // Eight 4-byte emoji are 32 bytes: right at the limit.
      expect(WirelessPlanner.isValidSsid('😀' * 8), isTrue);
      expect(WirelessPlanner.isValidSsid('😀' * 9), isFalse);
    });
  });

  group('planning', () {
    WirelessNetwork home() => WirelessPlanner.parse(
      _config,
    )[0].networks.firstWhere((n) => n.ssid == 'Home');

    test('toggling an SSID touches only its disabled flag', () {
      final ops = WirelessPlanner.planSetEnabled(
        network: home(),
        enabled: false,
      );
      final set = ops.single as UciSet;
      expect(set.config, 'wireless');
      expect(set.section, 'default_radio0');
      expect(set.values, {'disabled': '1'});
    });

    test('an edit writes ssid, encryption and passphrase together', () {
      final ops = WirelessPlanner.planUpdateNetwork(
        existing: home(),
        ssid: 'NewName',
        security: WirelessSecurity.wpa3,
        passphrase: 'newpassphrase',
        hidden: true,
      );
      final set = ops.first as UciSet;
      expect(set.values['ssid'], 'NewName');
      expect(set.values['encryption'], 'sae');
      expect(set.values['key'], 'newpassphrase');
      expect(set.values['hidden'], '1');
    });

    // A stale passphrase left in the config is readable by anyone who can see
    // the config and misleading to anyone reading it.
    test('switching to open removes the old key', () {
      final ops = WirelessPlanner.planUpdateNetwork(
        existing: home(),
        ssid: 'Home',
        security: WirelessSecurity.none,
      );
      expect(ops, hasLength(2));
      expect((ops[0] as UciSet).values['encryption'], 'none');
      expect((ops[0] as UciSet).values.containsKey('key'), isFalse);
      final remove = ops[1] as UciRemove;
      expect(remove.section, 'default_radio0');
      expect(remove.option, 'key');
    });

    test('switching to open on a network with no key needs no removal', () {
      final guest = WirelessPlanner.parse(
        _config,
      )[0].networks.firstWhere((n) => n.ssid == 'Guests');
      final ops = WirelessPlanner.planUpdateNetwork(
        existing: guest,
        ssid: 'Guests',
        security: WirelessSecurity.none,
      );
      expect(ops, hasLength(1));
    });

    test('a new SSID is added to the chosen radio in AP mode', () {
      final radio = WirelessPlanner.parse(
        _config,
      ).firstWhere((r) => r.section == 'radio0');
      final ops = WirelessPlanner.planCreateNetwork(
        radio: radio,
        ssid: 'Visitors',
        security: WirelessSecurity.wpa2,
        passphrase: 'guestpass1',
        network: const ['guest'],
        isolate: true,
      );
      final add = ops.single as UciAdd;
      expect(add.config, 'wireless');
      expect(add.type, 'wifi-iface');
      expect(add.values['device'], 'radio0');
      expect(add.values['mode'], 'ap');
      expect(add.values['ssid'], 'Visitors');
      expect(add.values['key'], 'guestpass1');
      expect(add.values['network'], 'guest');
      expect(add.values['isolate'], '1');
    });

    test('an open new SSID carries no key at all', () {
      final radio = WirelessPlanner.parse(_config).first;
      final add =
          WirelessPlanner.planCreateNetwork(
                radio: radio,
                ssid: 'Open',
                security: WirelessSecurity.none,
                passphrase: 'ignored',
              ).single
              as UciAdd;
      expect(add.values.containsKey('key'), isFalse);
    });

    test('a radio edit writes only the fields that changed', () {
      final radio = WirelessPlanner.parse(_config).first;
      final ops = WirelessPlanner.planUpdateRadio(
        radio: radio,
        channel: const OptionEdit.set('11'),
      );
      final set = ops.single as UciSet;
      expect(set.values, {'channel': '11'});
      expect(WirelessPlanner.planUpdateRadio(radio: radio), isEmpty);
    });

    // A router storing `us` must not be rewritten to `US` on a save where
    // nothing was touched: that reconfigures the radio and drops every
    // client on it.
    test('a country code differing only in case is no change', () {
      const radio = WirelessRadio(section: 'radio0', country: 'us');
      OptionEdit edit(String? was, String? now) => now == was
          ? const OptionEdit.keep()
          : now == null
          ? const OptionEdit.clear()
          : OptionEdit.set(now);
      expect(
        WirelessPlanner.planUpdateRadio(
          radio: radio,
          country: edit(radio.country?.toUpperCase(), 'US'),
        ),
        isEmpty,
      );
    });

    // Emptying a field is a choice too: the option goes, and the driver or
    // the regulatory default takes over. Not the same as leaving it alone.
    test('a radio option can be cleared, not just changed', () {
      final radio = WirelessPlanner.parse(_config).first;
      final ops = WirelessPlanner.planUpdateRadio(
        radio: radio,
        htmode: const OptionEdit.clear(),
        country: const OptionEdit.clear(),
      );
      expect(
        ops.whereType<UciRemove>().map((r) => r.option),
        containsAll(['htmode', 'country']),
      );
      expect(ops.whereType<UciSet>(), isEmpty);
      // Clearing what is not set is nothing to do.
      final bare = WirelessRadio(section: 'radio9');
      expect(
        WirelessPlanner.planUpdateRadio(
          radio: bare,
          htmode: const OptionEdit.clear(),
        ),
        isEmpty,
      );
    });

    test('deleting an SSID removes its section', () {
      final ops = WirelessPlanner.planDeleteNetwork(home());
      expect((ops.single as UciRemove).section, 'default_radio0');
      expect((ops.single as UciRemove).option, isNull);
    });
  });

  group('band-specific options', () {
    // Offering 2.4 GHz channels on a 5 GHz radio produces a config the radio
    // silently refuses to come up on.
    test('channels and widths match the band', () {
      expect(WirelessPlanner.channelsFor('2g'), contains('11'));
      expect(WirelessPlanner.channelsFor('2g'), isNot(contains('36')));
      expect(WirelessPlanner.channelsFor('5g'), contains('36'));
      expect(WirelessPlanner.channelsFor('5g'), isNot(contains('11')));
      expect(WirelessPlanner.htmodesFor('2g'), isNot(contains('VHT80')));
      expect(WirelessPlanner.htmodesFor('5g'), contains('VHT80'));
      // A Wi-Fi 6 radio's real width must be offerable, or the sheet would
      // show HT20 for a radio running HE80.
      expect(WirelessPlanner.htmodesFor('5g'), contains('HE80'));
      expect(WirelessPlanner.htmodesFor('2g'), contains('HE40'));
    });

    test('auto is always the first channel offered', () {
      for (final band in ['2g', '5g', '6g', null]) {
        expect(
          WirelessPlanner.channelsFor(band).first,
          'auto',
          reason: '$band',
        );
      }
    });
  });
}

void _encryptionPreservation() {
  // `psk-mixed` and `psk` both read back as wpa2 for display, but wpa2's
  // uciValue is `psk2`. Writing that on an unrelated edit silently narrows
  // the network and drops every WPA/TKIP client off it.
  group('editing a network leaves its encryption alone', () {
    WirelessNetwork network(String encryption) => WirelessNetwork(
      section: 'cfg01',
      device: 'radio0',
      ssid: 'Home',
      mode: 'ap',
      encryption: encryption,
      key: 'supersecret',
    );

    Map<String, String> valuesOf(List<UciOperation> ops) =>
        (ops.whereType<UciSet>().first).values;

    test('an SSID rename on psk-mixed does not rewrite encryption', () {
      final ops = WirelessPlanner.planUpdateNetwork(
        existing: network('psk-mixed'),
        ssid: 'Home-2',
        security: WirelessSecurity.wpa2,
        passphrase: 'supersecret',
      );
      expect(valuesOf(ops)['ssid'], 'Home-2');
      expect(valuesOf(ops).containsKey('encryption'), isFalse);
    });

    test('the same holds for plain psk', () {
      final ops = WirelessPlanner.planUpdateNetwork(
        existing: network('psk'),
        ssid: 'Home-2',
        security: WirelessSecurity.wpa2,
        passphrase: 'supersecret',
      );
      expect(valuesOf(ops).containsKey('encryption'), isFalse);
    });

    // ...but a deliberate change still has to be written.
    test('choosing a different mode does write encryption', () {
      final ops = WirelessPlanner.planUpdateNetwork(
        existing: network('psk-mixed'),
        ssid: 'Home',
        security: WirelessSecurity.wpa3,
        passphrase: 'supersecret',
      );
      expect(valuesOf(ops)['encryption'], WirelessSecurity.wpa3.uciValue);
    });

    test('an already-psk2 network is untouched by a rename', () {
      final ops = WirelessPlanner.planUpdateNetwork(
        existing: network('psk2'),
        ssid: 'Home-2',
        security: WirelessSecurity.wpa2,
        passphrase: 'supersecret',
      );
      expect(valuesOf(ops).containsKey('encryption'), isFalse);
    });
  });
}
