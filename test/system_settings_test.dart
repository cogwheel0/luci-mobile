import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/models/router_capabilities.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/state/system_settings_notifier.dart';

SystemSettings settings({
  String section = 'cfg01e48a',
  String hostname = 'OpenWrt',
  String zoneName = 'UTC',
  String description = '',
  String notes = '',
}) => SystemSettings(
  section: section,
  hostname: hostname,
  zoneName: zoneName,
  description: description,
  notes: notes,
  timezones: const {
    'UTC': 'UTC',
    'Europe/Berlin': 'CET-1CEST,M3.5.0,M10.5.0/3',
  },
);

List<UciOperation> plan(
  SystemSettings current, {
  String? hostname,
  String? zoneName,
  String? description,
  String? notes,
}) => planSystemSettings(
  current: current,
  hostname: hostname ?? current.hostname,
  zoneName: zoneName ?? current.zoneName,
  description: description ?? current.description,
  notes: notes ?? current.notes,
);

void main() {
  group('planning system settings', () {
    // Applying a no-op would still run the whole rollback protocol and make
    // the user sit through it for nothing.
    test('an unchanged form plans nothing', () {
      expect(plan(settings()), isEmpty);
    });

    test('a renamed router sets only the hostname', () {
      final ops = plan(settings(), hostname: 'attic-ap');
      final op = ops.single as UciSet;
      expect(op.config, 'system');
      expect(op.section, 'cfg01e48a');
      expect(op.values, {'hostname': 'attic-ap'});
    });

    test('surrounding whitespace is trimmed rather than written', () {
      final ops = plan(settings(), hostname: '  attic-ap  ');
      expect((ops.single as UciSet).values['hostname'], 'attic-ap');
    });

    // `zonename` is what the UI reads back; `timezone` is the POSIX string
    // the C library keeps time by. Writing one without the other leaves the
    // router displaying a zone it is not actually in.
    test('a timezone change writes both zonename and timezone', () {
      final ops = plan(settings(), zoneName: 'Europe/Berlin');
      expect((ops.single as UciSet).values, {
        'zonename': 'Europe/Berlin',
        'timezone': 'CET-1CEST,M3.5.0,M10.5.0/3',
      });
    });

    test('an unlisted zone falls back to UTC rather than writing nothing', () {
      final ops = plan(settings(), zoneName: 'Mars/Olympus');
      expect((ops.single as UciSet).values['timezone'], 'UTC');
    });

    test('description and notes are written independently', () {
      final ops = plan(settings(), description: 'Attic', notes: 'Rack 2');
      expect(ops, hasLength(2));
      expect((ops.first as UciSet).values, {'description': 'Attic'});
      expect((ops.last as UciSet).values, {'notes': 'Rack 2'});
    });

    // A router whose `system` section could not be located must not have
    // writes aimed at a guessed name like `@system[0]`.
    test('no discovered section means no writes', () {
      expect(plan(settings(section: ''), hostname: 'x'), isEmpty);
    });
  });

  group('hostname validation', () {
    test('accepts what OpenWrt accepts', () {
      expect(isValidHostname('OpenWrt'), isTrue);
      expect(isValidHostname('attic-ap'), isTrue);
      expect(isValidHostname('r2'), isTrue);
    });

    // An invalid hostname can stop dnsmasq while leaving the router
    // reachable, so the router's own rollback timer would never fire.
    test('rejects what would break dnsmasq', () {
      expect(isValidHostname('attic ap'), isFalse);
      expect(isValidHostname('attic_ap'), isFalse);
      expect(isValidHostname('-attic'), isFalse);
      expect(isValidHostname('attic-'), isFalse);
      expect(isValidHostname(''), isFalse);
    });
  });

  group('the systemSettings capability', () {
    RouterCapabilities probed(Map<String, Set<String>>? acl) =>
        RouterCapabilities(ubusAcl: acl, probedAt: DateTime(2026));

    test('needs uci write access', () {
      expect(
        probed({
          'uci': {'get'},
        }).of(RouterFeature.systemSettings).reason,
        UnavailableReason.noPermission,
      );
      expect(
        probed({
          'uci': {'set'},
        }).of(RouterFeature.systemSettings).available,
        isTrue,
      );
    });

    // A router that will not report its ACL should not have every write
    // hidden; the call itself surfaces the error if it really is denied.
    test('an unreported ACL does not hide the screen', () {
      expect(probed(null).of(RouterFeature.systemSettings).available, isTrue);
    });

    test('an unprobed router reports notProbed, not unsupported', () {
      expect(
        RouterCapabilities.unknown.of(RouterFeature.systemSettings).reason,
        UnavailableReason.notProbed,
      );
    });
  });
}
