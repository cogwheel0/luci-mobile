import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/wireless_config.dart';

/// The `WIFI:` payload phone cameras understand (the ZXing format, read by
/// Android 10+ and iOS 11+ camera apps).
String wifiQrPayload({
  required String ssid,
  String? encryption,
  String? key,
  bool hidden = false,
}) {
  String esc(String v) => v.replaceAllMapped(
    RegExp(r'([\\;,":])'),
    (m) => '\\${m.group(1)}',
  );
  final enc = (encryption ?? 'none').toLowerCase();
  final type = switch (enc) {
    'none' || 'owe' || '' => 'nopass',
    final e when e.startsWith('wep') => 'WEP',
    // Pure WPA3: phones that see WPA would try PSK and fail.
    final e when e.startsWith('sae') && !e.startsWith('sae-mixed') => 'SAE',
    _ => 'WPA',
  };
  final buf = StringBuffer('WIFI:T:$type;S:${esc(ssid)};');
  if (type != 'nopass' && key != null && key.isNotEmpty) {
    buf.write('P:${esc(key)};');
  }
  if (hidden) buf.write('H:true;');
  buf.write(';');
  return buf.toString();
}

/// Shows a QR code guests can scan to join [network] (GitHub issue #37).
Future<void> showWifiQrSheet(BuildContext context, WirelessNetwork network) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _WifiQrSheet(network: network),
  );
}

class _WifiQrSheet extends StatelessWidget {
  const _WifiQrSheet({required this.network});

  final WirelessNetwork network;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final ssid = network.ssid ?? '';
    final key = network.isOpen ? null : network.key;
    final payload = wifiQrPayload(
      ssid: ssid,
      encryption: network.encryption,
      key: key,
      hidden: network.hidden,
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l10n.shareWifi, style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            // Always dark-on-white: scanners struggle with inverted codes,
            // and the dark/AMOLED themes would otherwise invert it.
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: payload,
                size: 240,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.wifiQrHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.wifi),
              title: Text(ssid),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                onPressed: () => _copy(context, ssid, ssid),
              ),
            ),
            if (key != null && key.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.key),
                title: SelectableText(
                  key,
                  style: const TextStyle(fontFamily: 'monospace'),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () => _copy(context, key, l10n.password),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _copy(BuildContext context, String value, String label) async {
    final messenger = ScaffoldMessenger.of(context);
    final text = context.l10n.copiedToClipboard(label);
    await Clipboard.setData(ClipboardData(text: value));
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }
}
