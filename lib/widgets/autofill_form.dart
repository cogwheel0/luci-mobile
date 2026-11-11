import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// A [Form] whose fields the OS and password managers treat as one
/// sign-in: the router's address, username and password are offered and
/// saved together, instead of field by field (#36).
///
/// Nothing is saved when the form goes away - a cancelled dialog, a failed
/// attempt. Call [saveCredentials] once a sign-in has worked.
class AutofillForm extends StatelessWidget {
  const AutofillForm({required this.formKey, required this.child, super.key});

  /// The [Form]'s key, for `validate()`; [key] is this widget's own.
  final GlobalKey<FormState> formKey;
  final Widget child;

  /// Ends the sign-in, offering to save what the form holds - now that the
  /// router accepted it - only if [unchanged]: the fields stay editable
  /// while signing in, and values typed meanwhile were never checked, so
  /// saving them could store a wrong password over a working one. Call
  /// before navigating away from the form.
  static void saveCredentials({required bool unchanged}) =>
      TextInput.finishAutofillContext(shouldSave: unchanged);

  @override
  Widget build(BuildContext context) => AutofillGroup(
    onDisposeAction: AutofillContextAction.cancel,
    child: Form(key: formKey, child: child),
  );
}
