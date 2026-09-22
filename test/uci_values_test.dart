import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/services/uci_changeset_service.dart';

void main() {
  // Three shapes reach the app: rpcd's, the reviewer-mode fixtures', and
  // the bare one some builds return. One helper reads all of them.
  test('reads every uci.get shape', () {
    const sections = {
      'lan': {'.type': 'interface'},
    };
    expect(
      uciValuesOf([
        0,
        {'values': sections},
      ]),
      sections,
    );
    expect(
      uciValuesOf([
        0,
        {'network': sections},
      ], config: 'network'),
      sections,
    );
    expect(uciValuesOf([0, sections]), sections);
    expect(uciSectionsOf({'wireless': sections}, config: 'wireless'), sections);
  });

  test('anything that is not a config reads as empty', () {
    expect(uciValuesOf(null), isEmpty);
    expect(uciValuesOf([6]), isEmpty);
    expect(uciValuesOf([0, 'nope']), isEmpty);
    expect(uciSectionsOf(null), isEmpty);
  });
}
