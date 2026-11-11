import 'package:material_ui/material_ui.dart';

import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/models/system_details.dart';

/// Makes [child] open the System details sheet on a tap, or the long press
/// #14 asked for. Inert when there is nothing to show.
class SystemDetailsTap extends StatelessWidget {
  const SystemDetailsTap({
    required this.details,
    required this.child,
    super.key,
  });

  final List<(SystemDetail, String)> details;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    void open() => showSystemDetailsSheet(context, details);
    return InkWell(
      onTap: details.isEmpty ? null : open,
      onLongPress: details.isEmpty ? null : open,
      child: child,
    );
  }
}

/// What LuCI's Status > Overview shows beyond model and version.
void showSystemDetailsSheet(
  BuildContext context,
  List<(SystemDetail, String)> details,
) {
  final l10n = context.l10n;
  String label(SystemDetail field) => switch (field) {
    SystemDetail.hostname => l10n.hostname,
    SystemDetail.model => l10n.model,
    SystemDetail.architecture => l10n.architecture,
    SystemDetail.target => l10n.targetPlatform,
    SystemDetail.firmware => l10n.versionLabel,
    SystemDetail.kernel => l10n.kernelVersion,
  };

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              l10n.systemDetails,
              style: Theme.of(sheetContext).textTheme.titleMedium,
            ),
          ),
          for (final (field, value) in details)
            ListTile(
              dense: true,
              title: Text(label(field)),
              // Selectable: these are what gets pasted into a bug report.
              subtitle: SelectableText(value),
            ),
        ],
      ),
    ),
  );
}
