import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/utils/uci_values.dart';
import 'package:luci_mobile/models/addon_spec.dart';
import 'package:luci_mobile/models/uci_change.dart';
import 'package:luci_mobile/services/addon_planner.dart';
import 'package:luci_mobile/services/uci_changeset_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/uci_mutation.dart';

/// The sections of one add-on's config.
///
/// Keyed by the spec itself. Every spec is a `static const` in
/// `AddonCatalog`, so Dart canonicalises them and identity is a stable
/// cache key without needing value equality on the whole field list.
final addonProvider = FutureProvider.family<List<AddonSection>, AddonSpec>((
  ref,
  spec,
) async {
  final session = ref.watch(sessionProvider);
  final api = ref.watch(apiServiceProvider);
  if (session == null || api == null) return const [];

  return AddonPlanner.sections(
    spec,
    await uciConfigValues(api, session, spec.config),
  );
}, retry: (_, _) => null);

final addonMutationsProvider = Provider<AddonMutations>(AddonMutations.new);

class AddonMutations {
  AddonMutations(this.ref);

  final Ref ref;

  Future<ApplyOutcome?> apply(
    AddonSpec spec,
    List<UciOperation> ops, {
    BuildContext? context,
    void Function(ApplyPhase phase, Duration remaining)? onPhase,
  }) async {
    final outcome = await applyUciOperations(
      ref,
      ops,
      describe: 'add-on change',
      context: context,
      onPhase: onPhase,
    );
    if (ref.mounted) ref.invalidate(addonProvider(spec));
    return outcome;
  }
}
