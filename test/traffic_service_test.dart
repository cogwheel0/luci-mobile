import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/services/traffic_service.dart';

/// The exact shape `nlbwmon-action download -f json` returns, measured on
/// OpenWrt 24.10.
const _table =
    '{"columns":["mac","ip","conns","rx_bytes","rx_pkts","tx_bytes",'
    '"tx_pkts"],"data":['
    '["a4:83:e7:2b:11:04","192.168.1.115",412,8402334721,6120044,412883912,'
    '2904113],'
    '["3c:22:fb:91:aa:17","192.168.1.132",188,2140998233,1704221,98221044,'
    '812004]]}';

void main() {
  group('parsing nlbwmon output', () {
    test('reads a row', () {
      final rows = TrafficService.parseTable(_table);
      expect(rows, hasLength(2));
      expect(rows.first.mac, 'A4:83:E7:2B:11:04');
      expect(rows.first.ip, '192.168.1.115');
      expect(rows.first.connections, 412);
      expect(rows.first.rxBytes, 8402334721);
      expect(rows.first.txBytes, 412883912);
      expect(rows.first.totalBytes, 8402334721 + 412883912);
    });

    test('the heaviest user comes first', () {
      final rows = TrafficService.parseTable(_table);
      expect(rows.first.ip, '192.168.1.115');
      expect(rows.last.ip, '192.168.1.132');
    });

    // Column order is not part of nlbwmon's contract, so every value is
    // looked up by name. A positional reader would silently swap rx and tx.
    test('values follow the column names, not their position', () {
      final rows = TrafficService.parseTable(
        '{"columns":["tx_bytes","rx_bytes","ip","mac","conns"],'
        '"data":[[500,900,"10.0.0.2","aa:bb:cc:dd:ee:ff",3]]}',
      );
      expect(rows.single.rxBytes, 900);
      expect(rows.single.txBytes, 500);
      expect(rows.single.ip, '10.0.0.2');
    });

    test('a router with no accounting yet yields no rows, not a crash', () {
      expect(
        TrafficService.parseTable(
          '{"columns":["mac","ip","conns","rx_bytes","rx_pkts","tx_bytes",'
          '"tx_pkts"],"data":[]}',
        ),
        isEmpty,
      );
    });

    test('junk output is dropped rather than crashing the screen', () {
      expect(TrafficService.parseTable(''), isEmpty);
      expect(TrafficService.parseTable('not json'), isEmpty);
      expect(TrafficService.parseTable('{"columns":"nope"}'), isEmpty);
      expect(TrafficService.parseTable('[]'), isEmpty);
    });

    test('a missing column reads as zero rather than throwing', () {
      final rows = TrafficService.parseTable(
        '{"columns":["mac","rx_bytes"],"data":[["aa:bb:cc:dd:ee:ff",10]]}',
      );
      expect(rows.single.txBytes, 0);
      expect(rows.single.ip, '');
    });
  });
}
