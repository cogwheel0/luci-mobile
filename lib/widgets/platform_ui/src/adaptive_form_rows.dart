import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'adaptive_anchored_menu.dart';
import 'adaptive_selection_controls.dart';
import 'platform_ui_capabilities.dart';

/// A row of an [AdaptiveFormSection] that has something to say under the
/// section on iOS: a field's hint, or its error.
abstract interface class AdaptiveFormNotes {
  /// The row's label, which names its note when the group shows several.
  String get formNoteLabel;

  /// The error, if the row has one, else its hint.
  String? get formNote;

  /// Whether [formNote] is an error.
  bool get formNoteIsError;
}

/// A label as an iOS row shows it: a Material field label can end in a
/// colon ("Network Name (SSID):"); an iOS row's label never does.
String _rowLabelText(String label) =>
    label.replaceFirst(RegExp(r'\s*[:：]\s*$'), '');

/// A form made of [AdaptiveFormSection]s.
///
/// iOS stacks the groups with the space iOS Settings puts between them.
/// Android, which shows the sections as one run of fields, puts
/// [materialGap] between them, as between the fields within one.
class AdaptiveForm extends StatelessWidget {
  const AdaptiveForm({
    super.key,
    required this.sections,
    this.materialGap = 16,
  });

  final List<Widget> sections;
  final double materialGap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final (i, section) in sections.indexed) ...[
        if (i > 0 && !PlatformUiCapabilities.isIOS)
          SizedBox(height: materialGap),
        section,
      ],
    ],
  );
}

/// A group of form rows.
///
/// On iOS it is an inset group, as iOS Settings lays a form out: the rows
/// on one rounded surface, separated by hairlines, with [header] above it
/// and, under it, the rows' errors and hints and then [footer]. On Android
/// it is the Material form luci-mobile's forms were: the rows in a column,
/// [materialGap] apart, and no header or footer (the fields carry their own
/// hints and errors there). An [AdaptiveFormPair] is one line of two fields
/// on Android and two rows on iOS.
class AdaptiveFormSection extends StatelessWidget {
  const AdaptiveFormSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.error,
    this.materialGap = 16,
  });

  final List<Widget> children;

  /// A title above the group, on iOS.
  final String? header;

  /// A note under the group, after its rows' own, on iOS.
  final String? footer;

  /// What went wrong with the form as a whole, rather than with one row,
  /// such as a failed connection: in red under the group, before
  /// [footer], and announced when it appears. iOS only, like [footer].
  final String? error;

  /// The space between rows on Android.
  final double materialGap;

  @override
  Widget build(BuildContext context) {
    if (!PlatformUiCapabilities.isIOS) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, child) in children.indexed) ...[
            if (i > 0) SizedBox(height: materialGap),
            child,
          ],
        ],
      );
    }

    final rows = [
      for (final child in children)
        if (child is AdaptiveFormPair) ...[
          child.first,
          child.second,
        ] else
          child,
    ];
    final notes = [
      for (final row in rows)
        if (row is AdaptiveFormNotes &&
            (row as AdaptiveFormNotes).formNote != null)
          row as AdaptiveFormNotes,
    ];
    final separator = CupertinoColors.separator.resolveFrom(context);
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final noteStyle = _footnoteStyle(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Text(
                header!.toUpperCase(),
                style: noteStyle.copyWith(color: secondary),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: CupertinoColors.secondarySystemGroupedBackground
                  .resolveFrom(context),
              borderRadius: BorderRadius.circular(adaptiveFormCornerRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, row) in rows.indexed) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 16),
                      child: Container(height: 0.5, color: separator),
                    ),
                  row,
                ],
              ],
            ),
          ),
          // Each row reads its own note to VoiceOver, so these are for
          // the eye. Several in one group say which row each is about.
          for (final note in notes)
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  notes.length > 1
                      ? '${_rowLabelText(note.formNoteLabel)}: ${note.formNote}'
                      : note.formNote!,
                  style: noteStyle.copyWith(
                    color: note.formNoteIsError
                        ? CupertinoColors.systemRed.resolveFrom(context)
                        : secondary,
                  ),
                ),
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  style: noteStyle.copyWith(
                    color: CupertinoColors.systemRed.resolveFrom(context),
                  ),
                ),
              ),
            ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(footer!, style: noteStyle.copyWith(color: secondary)),
            ),
        ],
      ),
    );
  }
}

/// The corner radius of an iOS form group: iOS 26's larger one, or the
/// earlier 10.
double get adaptiveFormCornerRadius =>
    PlatformUiCapabilities.iOSMajorVersion >= 26 ? 26 : 10;

/// The height of an iOS form row.
double get _rowHeight => PlatformUiCapabilities.iOSMajorVersion >= 26 ? 52 : 44;

/// Two fields side by side on Android, and two rows of the group on iOS.
/// Only meaningful as a child of [AdaptiveFormSection].
class AdaptiveFormPair extends StatelessWidget {
  const AdaptiveFormPair({
    super.key,
    required this.first,
    required this.second,
    this.gap = 16,
  });

  final Widget first;
  final Widget second;

  /// The space between the two on Android.
  final double gap;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: first),
      SizedBox(width: gap),
      Expanded(child: second),
    ],
  );
}

/// A row's label, in red while the row has an error, and dimmed while it is
/// disabled.
class _RowLabel extends StatelessWidget {
  const _RowLabel(this.text, {required this.error, required this.enabled});

  final String text;
  final bool error;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Text(
    _rowLabelText(text),
    style: _bodyStyle(context).copyWith(
      color:
          (error
                  ? CupertinoColors.systemRed
                  : enabled
                  ? CupertinoColors.label
                  : CupertinoColors.tertiaryLabel)
              .resolveFrom(context),
    ),
  );
}

/// iOS's body text, 17 point with its own tracking: the Material text
/// style these rows would otherwise inherit spaces letters further apart.
TextStyle _bodyStyle(BuildContext context) =>
    CupertinoTheme.of(context).textTheme.textStyle;

/// iOS's footnote text, for a group's header and notes.
TextStyle _footnoteStyle(BuildContext context) =>
    _bodyStyle(context)
        .copyWith(fontSize: 13, letterSpacing: -0.08, height: 1.3);

/// A text field as a form row.
///
/// On Android, the Material text field luci-mobile's forms used: [label] as
/// its floating label, [placeholder] as its hint, and [helper] and [error]
/// under it. On iOS, a row of an [AdaptiveFormSection]: [label] on the
/// left and the text on the right, as iOS Settings edits a value; tapping
/// anywhere on the row edits it. The section shows [error], or else
/// [helper], under the group, and the label turns red while there is an
/// error.
class AdaptiveFormTextField extends StatefulWidget
    implements AdaptiveFormNotes {
  const AdaptiveFormTextField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.placeholder,
    this.helper,
    this.helperMaxLines,
    this.error,
    this.suffix,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.autofocus = false,
    this.enabled = true,
    this.maxLength,
    this.inputFormatters,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.materialDecoration = const InputDecoration(),
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  /// The Material field's look on Android, such as an outlined border. Its
  /// label, hint, helper, error and suffix come from the fields here.
  final InputDecoration materialDecoration;

  /// Shown while the field is empty.
  final String? placeholder;

  /// A hint about what the field takes.
  final String? helper;

  /// Lines [helper] may take on Android.
  final int? helperMaxLines;

  /// What is wrong with the value, or null.
  final String? error;

  /// A control at the end of the field, such as a show-password button.
  final Widget? suffix;

  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final bool autofocus;
  final bool enabled;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  String get formNoteLabel => label;

  @override
  String? get formNote => error ?? helper;

  @override
  bool get formNoteIsError => error != null;

  @override
  State<AdaptiveFormTextField> createState() => _AdaptiveFormTextFieldState();
}

class _AdaptiveFormTextFieldState extends State<AdaptiveFormTextField> {
  FocusNode? _ownFocusNode;

  FocusNode get _focusNode =>
      widget.focusNode ?? (_ownFocusNode ??= FocusNode());

  @override
  void dispose() {
    _ownFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformUiCapabilities.isIOS) {
      return TextField(
        controller: widget.controller,
        focusNode: widget.focusNode,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        textCapitalization: widget.textCapitalization,
        obscureText: widget.obscureText,
        autocorrect: widget.autocorrect,
        enableSuggestions: widget.enableSuggestions,
        autofocus: widget.autofocus,
        enabled: widget.enabled,
        maxLength: widget.maxLength,
        inputFormatters: widget.inputFormatters,
        autofillHints: widget.autofillHints,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        decoration: widget.materialDecoration.copyWith(
          labelText: widget.label,
          hintText: widget.placeholder,
          helperText: widget.helper,
          helperMaxLines: widget.helperMaxLines,
          errorText: widget.error,
          suffixIcon: widget.suffix,
        ),
      );
    }

    final enabled = widget.enabled;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Tapping anywhere on the row edits it. VoiceOver reaches the field
      // itself, so this is no action of its own there.
      excludeFromSemantics: true,
      onTap: enabled ? _focusNode.requestFocus : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: _rowHeight),
        child: Padding(
          padding: EdgeInsetsDirectional.only(
            start: 16,
            end: widget.suffix == null ? 16 : 4,
          ),
          child: Row(
            children: [
              Expanded(
                // One element to VoiceOver: the field, named by the label,
                // as a Material field's label names it. A suffix, such as a
                // show-password button, stays an element of its own.
                child: MergeSemantics(
                  // The row's error is read with its name, as a Material
                  // field's is; its hint after.
                  child: Semantics(
                    label: widget.error,
                    hint: widget.error == null ? widget.helper : null,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Row(
                        children: [
                          ConstrainedBox(
                            // A long label wraps rather than squeezing the
                            // value out.
                            constraints: BoxConstraints(
                              maxWidth: constraints.maxWidth * 0.5,
                            ),
                            child: _RowLabel(
                              widget.label,
                              error: widget.error != null,
                              enabled: enabled,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: CupertinoTextField(
                              controller: widget.controller,
                              focusNode: _focusNode,
                              placeholder: widget.placeholder,
                              keyboardType: widget.keyboardType,
                              textInputAction: widget.textInputAction,
                              textCapitalization: widget.textCapitalization,
                              obscureText: widget.obscureText,
                              autocorrect: widget.autocorrect,
                              enableSuggestions: widget.enableSuggestions,
                              autofocus: widget.autofocus,
                              enabled: enabled,
                              maxLength: widget.maxLength,
                              inputFormatters: widget.inputFormatters,
                              autofillHints: widget.autofillHints,
                              onChanged: widget.onChanged,
                              onSubmitted: widget.onSubmitted,
                              textAlign: TextAlign.end,
                              decoration: null,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              style: _bodyStyle(context).copyWith(
                                color:
                                    (enabled
                                            ? CupertinoColors.label
                                            : CupertinoColors.secondaryLabel)
                                        .resolveFrom(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.suffix != null) widget.suffix!,
            ],
          ),
        ),
      ),
    );
  }
}

/// One of an [AdaptiveFormPicker]'s choices.
@immutable
class AdaptiveFormChoice<T> {
  const AdaptiveFormChoice(this.value, this.label);

  final T value;
  final String label;
}

/// A choice among a few values, as a form row.
///
/// On Android, the Material dropdown luci-mobile's forms used, [label] as
/// its floating label. On iOS, a row of an [AdaptiveFormSection]: [label]
/// on the left and the current choice on the right with the up-and-down
/// chevron of a pop-up button. Tapping it opens the system pull-down menu,
/// the current choice checked, on iOS 26, and an action sheet before.
///
/// [value] need not be among [choices]: the row then shows [hint], as the
/// dropdown does. It is the dropdown's initial value on Android, where the
/// dropdown keeps the choice itself afterwards.
class AdaptiveFormPicker<T> extends StatefulWidget
    implements AdaptiveFormNotes {
  const AdaptiveFormPicker({
    super.key,
    required this.label,
    required this.value,
    required this.choices,
    required this.onChanged,
    this.hint,
    this.helper,
    this.error,
  });

  final String label;
  final T? value;
  final List<AdaptiveFormChoice<T>> choices;

  /// Called with the choice made; null disables the row.
  final ValueChanged<T?>? onChanged;

  /// Shown when [value] is not one of [choices].
  final String? hint;

  final String? helper;
  final String? error;

  @override
  String get formNoteLabel => label;

  @override
  String? get formNote => error ?? helper;

  @override
  bool get formNoteIsError => error != null;

  AdaptiveFormChoice<T>? get _current {
    for (final choice in choices) {
      if (choice.value == value) return choice;
    }
    return null;
  }

  @override
  State<AdaptiveFormPicker<T>> createState() => _AdaptiveFormPickerState<T>();
}

class _AdaptiveFormPickerState<T> extends State<AdaptiveFormPicker<T>> {
  /// The choice and its chevron, which the menu grows out of, as a pop-up
  /// button's does.
  final _anchor = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final AdaptiveFormPicker(
      :label,
      :value,
      :choices,
      :onChanged,
      :hint,
      :helper,
      :error,
      :_current,
    ) = widget;
    if (!PlatformUiCapabilities.isIOS) {
      return DropdownButtonFormField<T>(
        initialValue: _current == null ? null : value,
        hint: hint == null ? null : Text(hint),
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          errorText: error,
        ),
        items: [
          for (final choice in choices)
            DropdownMenuItem<T>(value: choice.value, child: Text(choice.label)),
        ],
        onChanged: onChanged,
      );
    }

    final enabled = onChanged != null;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final open = enabled ? () => _choose(context) : null;
    return Semantics(
      // An element of its own, which VoiceOver can open: without container
      // the group's notes under it read as part of this row.
      container: true,
      button: true,
      enabled: enabled,
      // Its error read with its name, its hint after: the group's notes
      // are for the eye.
      label: error == null ? label : '$label\n$error',
      value: _current?.label ?? hint,
      hint: error == null ? helper : null,
      onTap: open,
      excludeSemantics: true,
      child: _TappableRow(
        onTap: open,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _rowHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                children: [
                  ConstrainedBox(
                    // A long label, or large text, wraps rather than pushing
                    // the choice out of the row.
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.5,
                    ),
                    child: _RowLabel(
                      label,
                      error: error != null,
                      enabled: enabled,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Row(
                        key: _anchor,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              _current?.label ?? hint ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: _bodyStyle(context).copyWith(
                                color: enabled
                                    ? secondary
                                    : CupertinoColors.tertiaryLabel.resolveFrom(
                                        context,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            CupertinoIcons.chevron_up_chevron_down,
                            size: 15,
                            color: secondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _choose(BuildContext context) async {
    final AdaptiveFormPicker(:label, :value, :choices) = widget;
    FocusScope.of(context).unfocus();
    final anchor = _anchor.currentContext ?? context;
    if (AdaptiveAnchoredMenu.canShow(anchor)) {
      final id = await AdaptiveAnchoredMenu.show(
        anchorContext: anchor,
        items: [
          for (final (i, choice) in choices.indexed)
            AdaptiveAnchoredMenuItem(
              id: '$i',
              label: choice.label,
              checked: choice.value == value,
            ),
        ],
      );
      // The form may have closed while the menu was open.
      if (id == null || !mounted) return;
      widget.onChanged?.call(choices[int.parse(id)].value);
      return;
    }
    final chosen = await showCupertinoModalPopup<AdaptiveFormChoice<T>>(
      context: context,
      builder: (sheet) => CupertinoActionSheet(
        title: Text(label),
        actions: [
          for (final choice in choices)
            CupertinoActionSheetAction(
              isDefaultAction: choice.value == value,
              onPressed: () => Navigator.of(sheet).pop(choice),
              child: Text(choice.label),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheet).pop(),
          child: Text(MaterialLocalizations.of(sheet).cancelButtonLabel),
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    widget.onChanged?.call(chosen.value);
  }
}

/// A button as a form row, centred: on iOS, a destructive action such as
/// removing what the form edits, in red, as iOS Settings' "Forget This
/// Network". iOS only; Android forms put such actions with their buttons.
class AdaptiveFormButtonRow extends StatelessWidget {
  const AdaptiveFormButtonRow({
    super.key,
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = !enabled
        ? CupertinoColors.tertiaryLabel.resolveFrom(context)
        : destructive
        ? CupertinoColors.systemRed.resolveFrom(context)
        : CupertinoTheme.of(context).primaryColor;
    return Semantics(
      container: true,
      button: true,
      enabled: enabled,
      child: _TappableRow(
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _rowHeight),
          child: Center(
            child: Text(
              label,
              style: _bodyStyle(context).copyWith(color: color),
            ),
          ),
        ),
      ),
    );
  }
}

/// A row that acts when tapped, which a hardware keyboard can also reach,
/// with Tab, and act on, with Space or Return, showing where focus is.
class _TappableRow extends StatefulWidget {
  const _TappableRow({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_TappableRow> createState() => _TappableRowState();
}

class _TappableRowState extends State<_TappableRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    return FocusableActionDetector(
      enabled: onTap != null,
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onTap?.call();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (show) => setState(() => _focused = show),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _focused
                ? CupertinoColors.systemFill.resolveFrom(context)
                : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// An on/off setting as a form row.
///
/// On Android, the switch tile luci-mobile's forms used, [description]
/// under its title. On iOS, a row of an [AdaptiveFormSection]: [label] on
/// the left and the switch on the right, the native one on iOS 26, with
/// [description] under the group, as iOS Settings explains a switch. Give a
/// switch with a description a section of its own, so its explanation sits
/// under it.
class AdaptiveFormSwitch extends StatelessWidget implements AdaptiveFormNotes {
  const AdaptiveFormSwitch({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.description,
    this.materialContentPadding = EdgeInsets.zero,
    this.materialCheckbox = false,
  });

  final String label;
  final bool value;

  /// Called with the new value; null disables the switch.
  final ValueChanged<bool>? onChanged;

  /// What the setting does.
  final String? description;

  /// The tile's padding on Android.
  final EdgeInsetsGeometry materialContentPadding;

  /// Whether Android shows a checkbox tile rather than a switch tile, for
  /// an option that goes with the rest of the form rather than a setting
  /// of its own. iOS forms use a switch for either.
  final bool materialCheckbox;

  @override
  String get formNoteLabel => label;

  @override
  String? get formNote => description;

  @override
  bool get formNoteIsError => false;

  @override
  Widget build(BuildContext context) {
    if (!PlatformUiCapabilities.isIOS && materialCheckbox) {
      return AdaptiveCheckboxListTile(
        contentPadding: materialContentPadding,
        title: Text(label),
        subtitle: description == null ? null : Text(description!),
        value: value,
        onChanged: onChanged,
      );
    }
    if (!PlatformUiCapabilities.isIOS) {
      return AdaptiveSwitchListTile(
        contentPadding: materialContentPadding,
        title: Text(label),
        subtitle: description == null ? null : Text(description!),
        value: value,
        onChanged: onChanged,
      );
    }
    final change = onChanged;
    // One switch to assistive technology, as a Settings row is; only the
    // switch itself responds to touch.
    return MergeSemantics(
      child: Semantics(
        toggled: value,
        enabled: change != null,
        hint: description,
        onTap: change == null ? null : () => change(!value),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _rowHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: _RowLabel(
                    label,
                    error: false,
                    enabled: change != null,
                  ),
                ),
                const SizedBox(width: 12),
                ExcludeSemantics(
                  child: AdaptiveSwitch(value: value, onChanged: change),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The button at the end of a password field that shows or hides what is
/// typed: an eye on iOS, at a 44 point target, and the Material visibility
/// icon on Android. It shows what tapping it will do, as both platforms do.
class AdaptiveObscureToggle extends StatelessWidget {
  const AdaptiveObscureToggle({
    super.key,
    required this.obscured,
    required this.onPressed,
    this.semanticLabel,
    this.materialOutlined = false,
  });

  /// Whether the field hides its text now.
  final bool obscured;

  /// Whether Android shows the outlined visibility icons.
  final bool materialOutlined;

  final VoidCallback? onPressed;

  /// What the button does, such as "Show password", for assistive
  /// technology (and a tooltip on Android).
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (!PlatformUiCapabilities.isIOS) {
      return IconButton(
        icon: Icon(switch ((obscured, materialOutlined)) {
          (true, false) => Icons.visibility,
          (false, false) => Icons.visibility_off,
          (true, true) => Icons.visibility_outlined,
          (false, true) => Icons.visibility_off_outlined,
        }),
        tooltip: semanticLabel,
        onPressed: onPressed,
      );
    }
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size.square(44),
      onPressed: onPressed,
      child: Icon(
        obscured ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
        size: 20,
        color: CupertinoColors.secondaryLabel.resolveFrom(context),
        semanticLabel: semanticLabel,
      ),
    );
  }
}

/// A read-only detail as a form row: [label] on the left and [value] on
/// the right in the secondary colour, as iOS Settings shows a fact it does
/// not let you change. On Android, the same two texts in a row; Android
/// forms lay their details out themselves.
class AdaptiveFormValueRow extends StatelessWidget {
  const AdaptiveFormValueRow({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (!PlatformUiCapabilities.isIOS) {
      return MergeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              ConstrainedBox(
                // A long label wraps rather than overflowing the row.
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * 0.5,
                ),
                child: Text(label),
              ),
              const SizedBox(width: 16),
              Expanded(child: Text(value, textAlign: TextAlign.end)),
            ],
          ),
        ),
      );
    }
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: _rowHeight),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * 0.5,
                  ),
                  child: _RowLabel(label, error: false, enabled: true),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    style: _bodyStyle(context).copyWith(
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
