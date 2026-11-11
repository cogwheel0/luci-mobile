import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/widgets/autofill_form.dart';

void main() {
  // #36: password managers saw three unrelated fields; grouped, they see
  // one sign-in to fill and save.
  testWidgets('the fields form one autofill group around the form', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AutofillForm(
            formKey: formKey,
            child: Column(
              children: [
                TextFormField(autofillHints: const [AutofillHints.url]),
                TextFormField(autofillHints: const [AutofillHints.username]),
                TextFormField(
                  autofillHints: const [AutofillHints.password],
                  validator: (v) => (v ?? '').isEmpty ? 'required' : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final group = tester.widget<AutofillGroup>(find.byType(AutofillGroup));
    // Leaving - a cancelled dialog, a failed attempt - saves nothing.
    expect(group.onDisposeAction, AutofillContextAction.cancel);
    expect(
      find.descendant(
        of: find.byType(AutofillGroup),
        matching: find.byType(Form),
      ),
      findsOneWidget,
    );
    // The key still reaches the Form: screens validate through it.
    expect(formKey.currentState, isNotNull);
    expect(formKey.currentState!.validate(), isFalse);
  });

  // Fields stay editable while signing in; values typed meanwhile were
  // never checked and must not be saved over a working entry.
  testWidgets('only the values signed in with are saved', (tester) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.textInput,
        null,
      ),
    );

    AutofillForm.saveCredentials(unchanged: true);
    AutofillForm.saveCredentials(unchanged: false);
    await tester.pump();

    expect(
      calls
          .where((c) => c.method == 'TextInput.finishAutofillContext')
          .map((c) => c.arguments),
      [true, false],
    );
  });
}
