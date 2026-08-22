import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/models/wifi_scan_result.dart';

void main() {
  test('classifies the 4.9 GHz Wi-Fi band', () {
    final result = WifiScanResult.fromJson({
      'frequency': 4940,
      'encryption': <String, dynamic>{},
    });

    expect(result.band, '4.9 GHz');
  });
}
