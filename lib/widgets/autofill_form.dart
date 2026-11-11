import 'package:flutter/material.dart';
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

  /// Offers to save what was typed into the form being shown, now that the
  /// router accepted it. Call before navigating away from it.
  static void saveCredentials() => TextInput.finishAutofillContext();

  @override
  Widget build(BuildContext context) => AutofillGroup(
    onDisposeAction: AutofillContextAction.cancel,
    child: Form(key: formKey, child: child),
  );
}
