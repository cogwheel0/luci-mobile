import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/services/wol_service.dart';

void main() {
  group('normalising a MAC for etherwake', () {
    test('accepts the forms the app already holds', () {
      expect(WolService.normaliseMac('AA:BB:CC:11:22:33'), 'aa:bb:cc:11:22:33');
      expect(WolService.normaliseMac('aa-bb-cc-11-22-33'), 'aa:bb:cc:11:22:33');
      expect(
        WolService.normaliseMac('  AA:bb:CC:11:22:33 '),
        'aa:bb:cc:11:22:33',
      );
    });

    // A client with no lease carries the literal 'N/A', and handing that to
    // etherwake would be a shell argument nobody meant to send.
    test('rejects anything that is not a MAC', () {
      expect(WolService.normaliseMac('N/A'), isNull);
      expect(WolService.normaliseMac(''), isNull);
      expect(WolService.normaliseMac('aa:bb:cc:11:22'), isNull);
      expect(WolService.normaliseMac('aa:bb:cc:11:22:33:44'), isNull);
      expect(WolService.normaliseMac('zz:bb:cc:11:22:33'), isNull);
      expect(WolService.normaliseMac('192.168.1.1'), isNull);
    });
  });

  group('building the etherwake call', () {
    test('asks for output, because nothing else reports success', () {
      expect(WolService.argsFor('aa:bb:cc:11:22:33'), [
        '-D',
        'aa:bb:cc:11:22:33',
      ]);
    });

    test('an interface is passed through when known', () {
      expect(WolService.argsFor('aa:bb:cc:11:22:33', device: 'br-lan'), [
        '-D',
        '-i',
        'br-lan',
        'aa:bb:cc:11:22:33',
      ]);
    });

    test('an empty interface is left out rather than passed as blank', () {
      expect(WolService.argsFor('aa:bb:cc:11:22:33', device: ''), [
        '-D',
        'aa:bb:cc:11:22:33',
      ]);
    });
  });
}
