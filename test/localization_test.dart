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

    for (final locale in AppLocalizations.supportedLocales) {
      final localizations = await AppLocalizations.delegate.load(locale);
      expect(localizations.reviewerModeConfirmation, contains('REVIEWER'));
      expect(localizations.typeReviewer, contains('REVIEWER'));
      expect(localizations.networkExample, contains('lan'));
      expect(localizations.networkExample, contains('wwan'));
    }

    const traditionalChinese = Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
    );
    for (final locale in const <Locale>[
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      Locale('zh', 'TW'),
      Locale('zh', 'HK'),
      Locale('zh', 'MO'),
    ]) {
      expect(
        resolveLuciLocale(<Locale>[locale], AppLocalizations.supportedLocales),
        traditionalChinese,
      );
    }

    expect(
      resolveLuciLocale(const <Locale>[
        Locale('en', 'TW'),
      ], AppLocalizations.supportedLocales),
      const Locale('en'),
    );
    expect(
      resolveLuciLocale(const <Locale>[
        Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
          countryCode: 'TW',
        ),
      ], AppLocalizations.supportedLocales),
      const Locale('zh'),
    );
  });
}
