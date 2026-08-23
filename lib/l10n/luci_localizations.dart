import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_localizations.dart';

const List<LocalizationsDelegate<dynamic>> luciLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ];

extension LuciLocalizationsContext on BuildContext {
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? lookupAppLocalizations(const Locale('en'));
}

Locale? resolveLuciLocale(
  List<Locale>? locales,
  Iterable<Locale> supportedLocales,
) {
  if (locales == null || locales.isEmpty) return null;
  final supported = supportedLocales.toList();

  for (final device in locales) {
    final language = device.languageCode.toLowerCase();
    final prefersTraditional =
        language == 'zh' &&
        (device.scriptCode?.toLowerCase() == 'hant' ||
            const {
              'TW',
              'HK',
              'MO',
            }.contains(device.countryCode?.toUpperCase()));

    if (prefersTraditional) {
      for (final locale in supported) {
        if (locale.languageCode == 'zh' && locale.scriptCode == 'Hant') {
          return locale;
        }
      }
    }

    for (final locale in supported) {
      if (locale.languageCode.toLowerCase() == language &&
          locale.scriptCode?.toLowerCase() ==
              device.scriptCode?.toLowerCase()) {
        return locale;
      }
    }

    for (final locale in supported) {
      if (locale.languageCode.toLowerCase() == language &&
          locale.scriptCode == null) {
        return locale;
      }
    }
  }

  return null;
}
