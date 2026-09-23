import 'package:flutter/foundation.dart';

/// Which add-on a screen is for. Also the key the capability gate and the
/// hub tile are looked up by.
enum Addon { sqm, adblock, upnp, ddns, nlbwmon }

/// How one UCI option is presented.
///
/// These are hand-written per add-on, not derived from the config: a
/// generic UCI editor was explicitly ruled out, and a curated field list is
/// what makes "Download speed (kbit/s)" readable instead of `download`.
sealed class AddonField {
  const AddonField(this.option, {required this.labelKey, this.helpKey});

  /// The UCI option name.
  final String option;

  /// Keys into the generated localizations, resolved at render time so the
  /// spec itself stays free of BuildContext.
  final String labelKey;
  final String? helpKey;
}

final class AddonSwitch extends AddonField {
  const AddonSwitch(super.option, {required super.labelKey, super.helpKey});
}

final class AddonNumber extends AddonField {
  const AddonNumber(
    super.option, {
    required super.labelKey,
    super.helpKey,
    this.min = 0,
    this.max = 10000000,
    this.suffix,
  });

  final int min;
  final int max;

  /// A literal unit like `kbit/s` — not translated, because the units are
  /// not.
  final String? suffix;
}

final class AddonText extends AddonField {
  const AddonText(
    super.option, {
    required super.labelKey,
    super.helpKey,
    this.obscure = false,
  });

  final bool obscure;
}

final class AddonChoice extends AddonField {
  const AddonChoice(
    super.option, {
    required super.labelKey,
    super.helpKey,
    required this.values,
  });

  /// Raw UCI values, shown verbatim: `cake` and `fq_codel` are the names
  /// users will find in every guide, so translating them would hurt.
  final List<String> values;
}

/// A multi-value option (`list foo 'a'`), rendered as a checklist.
final class AddonMultiChoice extends AddonField {
  const AddonMultiChoice(
    super.option, {
    required super.labelKey,
    super.helpKey,
    required this.values,
  });

  final List<String> values;
}

/// One add-on's editable surface.
@immutable
class AddonSpec {
  const AddonSpec({
    required this.addon,
    required this.config,
    required this.sectionType,
    required this.titleKey,
    required this.subtitleKey,
    required this.fields,
    this.singleSection = true,
    this.nameOption,
  });

  final Addon addon;

  /// The UCI config file, e.g. `sqm`.
  final String config;

  /// The section type to edit, e.g. `queue`.
  final String sectionType;

  final String titleKey;
  final String subtitleKey;

  final List<AddonField> fields;

  /// False when the config holds several editable sections (SQM has one per
  /// interface, DDNS one per service) and the screen must list them first.
  final bool singleSection;

  /// The option to label a section by, when there are several.
  final String? nameOption;
}
