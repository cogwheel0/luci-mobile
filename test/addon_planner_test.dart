import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/l10n/addon_strings.dart';
import 'package:luci_mobile/l10n/app_localizations.dart';
import 'package:luci_mobile/models/addon_spec.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/addon_catalog.dart';
import 'package:luci_mobile/services/addon_planner.dart';

/// The shape `uci.get` returns, as measured on OpenWrt 24.10.
const _sqm = {
  'eth1': {
    '.anonymous': false,
    '.type': 'queue',
    '.name': 'eth1',
    'enabled': '0',
    'interface': 'eth1',
    'download': '85000',
    'upload': '10000',
    'qdisc': 'cake',
  },
  'somethingelse': {'.type': 'other', '.name': 'somethingelse'},
};

const _adblock = {
  'global': {
    '.type': 'adblock',
    '.name': 'global',
    'adb_enabled': '1',
    'adb_feed': ['adguard', 'certpl'],
  },
};

void main() {
  // The add-on form reads UCI through the same helpers as every other
  // screen. Its own copies disagreed: a flag rpcd returned as a one-element
  // list read as off here and on everywhere else, and a list joined with
  // commas round-tripped commas back into the config.
  test('an option is read as it is read everywhere else', () {
    const section = AddonSection(
      name: 'cfg01',
      label: 'cfg01',
      values: {
        'enabled': ['1'],
        'servers': ['a', 'b'],
        'one': 'x',
      },
    );
    expect(section.flag('enabled'), isTrue);
    expect(section.list('servers'), ['a', 'b']);
    expect(section.list('one'), ['x']);
    expect(section.text('servers'), 'a b');
    expect(section.flag('missing', orElse: true), isTrue);
  });

  group('reading add-on configs', () {
    test('only sections of the spec type are returned', () {
      final sections = AddonPlanner.sections(AddonCatalog.sqm, _sqm);
      expect(sections, hasLength(1));
      expect(sections.single.name, 'eth1');
    });

    test('a section is labelled by the spec option, not its UCI name', () {
      final sections = AddonPlanner.sections(AddonCatalog.sqm, _sqm);
      expect(sections.single.label, 'eth1');
    });

    test('list options survive as lists', () {
      final s = AddonPlanner.sections(AddonCatalog.adblock, _adblock).single;
      expect(s.list('adb_feed'), ['adguard', 'certpl']);
    });

    // UCI has no booleans, and the spellings in the wild are not uniform.
    test('every UCI spelling of true reads as on', () {
      for (final on in ['1', 'true', 'yes', 'on', 'enabled']) {
        final s = AddonPlanner.sections(AddonCatalog.sqm, {
          'q': {'.type': 'queue', '.name': 'q', 'enabled': on},
        }).single;
        expect(s.flag('enabled'), isTrue, reason: on);
      }
      for (final off in ['0', 'false', 'no', '']) {
        final s = AddonPlanner.sections(AddonCatalog.sqm, {
          'q': {'.type': 'queue', '.name': 'q', 'enabled': off},
        }).single;
        expect(s.flag('enabled'), isFalse, reason: off);
      }
    });

    test('a missing option falls back rather than throwing', () {
      final s = AddonPlanner.sections(AddonCatalog.sqm, {
        'q': {'.type': 'queue', '.name': 'q'},
      }).single;
      expect(s.text('download'), '');
      expect(s.flag('enabled'), isFalse);
      expect(s.list('nope'), isEmpty);
    });
  });

  group('planning add-on changes', () {
    AddonSection sqmSection() =>
        AddonPlanner.sections(AddonCatalog.sqm, _sqm).single;

    test('an untouched form plans nothing', () {
      expect(
        AddonPlanner.plan(
          spec: AddonCatalog.sqm,
          current: sqmSection(),
          edited: const {},
        ),
        isEmpty,
      );
    });

    // Re-selecting the value already on the router would still run the whole
    // rollback-protected apply and make the user wait through it.
    test('an edit back to the current value plans nothing', () {
      expect(
        AddonPlanner.plan(
          spec: AddonCatalog.sqm,
          current: sqmSection(),
          edited: const {'download': '85000', 'enabled': false},
        ),
        isEmpty,
      );
    });

    test('changed options are batched into one set', () {
      final ops = AddonPlanner.plan(
        spec: AddonCatalog.sqm,
        current: sqmSection(),
        edited: const {'enabled': true, 'download': '50000'},
      );
      final op = ops.single as UciSet;
      expect(op.config, 'sqm');
      expect(op.section, 'eth1');
      expect(op.values, {'enabled': '1', 'download': '50000'});
    });

    test('a switch writes UCI 1/0, not true/false', () {
      final ops = AddonPlanner.plan(
        spec: AddonCatalog.sqm,
        current: sqmSection(),
        edited: const {'enabled': true},
      );
      expect((ops.single as UciSet).values['enabled'], '1');
    });

    test('an option not in the spec is ignored', () {
      expect(
        AddonPlanner.plan(
          spec: AddonCatalog.sqm,
          current: sqmSection(),
          edited: const {'linklayer': 'ethernet'},
        ),
        isEmpty,
      );
    });

    test('a changed list is replaced wholesale', () {
      final ops = AddonPlanner.plan(
        spec: AddonCatalog.adblock,
        current: AddonPlanner.sections(AddonCatalog.adblock, _adblock).single,
        edited: const {
          'adb_feed': ['adguard', 'oisd_small'],
        },
      );
      final op = ops.single as UciSetList;
      expect(op.option, 'adb_feed');
      expect(op.values, ['adguard', 'oisd_small']);
    });

    test('an unchanged list plans nothing', () {
      expect(
        AddonPlanner.plan(
          spec: AddonCatalog.adblock,
          current: AddonPlanner.sections(AddonCatalog.adblock, _adblock).single,
          edited: const {
            'adb_feed': ['adguard', 'certpl'],
          },
        ),
        isEmpty,
      );
    });

    // Assigning an empty list leaves the old entries in place, so clearing
    // every box has to delete the option instead.
    test('clearing every entry deletes the option', () {
      final ops = AddonPlanner.plan(
        spec: AddonCatalog.adblock,
        current: AddonPlanner.sections(AddonCatalog.adblock, _adblock).single,
        edited: const {'adb_feed': <String>[]},
      );
      final op = ops.single as UciRemove;
      expect(op.option, 'adb_feed');
      expect(op.section, 'global');
    });
  });

  group('number validation', () {
    const field = AddonNumber('download', labelKey: 'x', min: 0, max: 1000);

    test('accepts the range and blank', () {
      expect(AddonPlanner.validNumber(field, '500'), isTrue);
      expect(AddonPlanner.validNumber(field, ''), isTrue);
      expect(AddonPlanner.validNumber(field, '  0 '), isTrue);
    });

    test('rejects nonsense and out-of-range', () {
      expect(AddonPlanner.validNumber(field, '1001'), isFalse);
      expect(AddonPlanner.validNumber(field, '-1'), isFalse);
      expect(AddonPlanner.validNumber(field, 'fast'), isFalse);
    });
  });

  // A spec key with no case in the resolver would render as the raw key -
  // a visible "addonQdiscHelp" in the UI rather than a compile error.
  group('every spec key resolves to a translation', () {
    test('catalog keys are all mapped', () async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final keys = <String>{};
      for (final spec in AddonCatalog.all) {
        keys.addAll([spec.titleKey, spec.subtitleKey]);
        for (final f in spec.fields) {
          keys.add(f.labelKey);
          if (f.helpKey != null) keys.add(f.helpKey!);
        }
      }
      for (final key in keys) {
        expect(l10n.string(key), isNot(key), reason: key);
      }
    });
  });
}
