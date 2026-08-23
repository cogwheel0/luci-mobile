import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/l10n/app_localizations.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';

void main() {
  test('supports the same locales as Conduit', () async {
    expect(
      AppLocalizations.supportedLocales
          .map((locale) => locale.toLanguageTag())
          .toSet(),
      <String>{
        'en',
        'de',
        'fr',
        'it',
        'zh',
        'zh-Hant',
        'ru',
        'nl',
        'es',
        'ko',
        'ja',
        'cs',
        'sk',
        'pl',
      },
    );

    final german = await AppLocalizations.delegate.load(const Locale('de'));
    expect(german.clients, 'Clients');
    expect(german.settings, 'Einstellungen');
    expect(
      resolveLuciLocale(const <Locale>[
        Locale('zh', 'TW'),
      ], AppLocalizations.supportedLocales),
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
  });
}
