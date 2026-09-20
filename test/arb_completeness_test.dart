import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards translation completeness.
///
/// `flutter analyze --fatal-infos` cannot catch a missing translation: gen_l10n
/// silently falls back to the template locale, so a key added to `app_en.arb`
/// and forgotten everywhere else ships as English with a green build.
/// `localization_test.dart` pins which locales exist; this pins that they all
/// say the same things.
void main() {
  const arbDir = 'lib/l10n';
  const templateFile = 'app_en.arb';

  Set<String> messageKeys(File file) {
    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return decoded.keys.where((key) => !key.startsWith('@')).toSet();
  }

  late Set<String> templateKeys;
  late List<File> translations;

  setUpAll(() {
    final dir = Directory(arbDir);
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'Run tests from the package root; $arbDir was not found.',
    );

    templateKeys = messageKeys(File('$arbDir/$templateFile'));

    translations =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.arb'))
            .where((f) => !f.path.endsWith(templateFile))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
  });

  test('the template defines at least one message', () {
    expect(templateKeys, isNotEmpty);
  });

  test('every locale is present as an .arb file', () {
    expect(translations, isNotEmpty);
  });

  test('every locale defines exactly the template key set', () {
    final problems = <String>[];

    for (final file in translations) {
      final keys = messageKeys(file);
      final name = file.uri.pathSegments.last;

      final missing = templateKeys.difference(keys).toList()..sort();
      final extra = keys.difference(templateKeys).toList()..sort();

      if (missing.isNotEmpty) {
        problems.add(
          '$name is missing ${missing.length}: ${missing.join(', ')}',
        );
      }
      if (extra.isNotEmpty) {
        problems.add(
          '$name has ${extra.length} not in the template: '
          '${extra.join(', ')}',
        );
      }
    }

    expect(
      problems,
      isEmpty,
      reason:
          'Add every new string to all .arb files in $arbDir.\n'
          '${problems.join('\n')}',
    );
  });

  test('no locale leaves a message blank', () {
    final blanks = <String>[];

    for (final file in [File('$arbDir/$templateFile'), ...translations]) {
      final decoded =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final name = file.uri.pathSegments.last;
      for (final entry in decoded.entries) {
        if (entry.key.startsWith('@')) continue;
        final value = entry.value;
        if (value is String && value.trim().isEmpty) {
          blanks.add('$name: ${entry.key}');
        }
      }
    }

    expect(
      blanks,
      isEmpty,
      reason: 'Blank translations:\n${blanks.join('\n')}',
    );
  });
}
