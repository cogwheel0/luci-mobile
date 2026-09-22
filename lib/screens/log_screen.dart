import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/screens/diagnostics_screen.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/diagnostics_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

enum _LogSource { system, kernel }

/// The router's system and kernel logs.
class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  _LogSource _source = _LogSource.system;
  final _filter = TextEditingController();
  bool _loading = false;
  String? _error;
  List<LogEntry> _entries = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final session = ref.read(sessionProvider);
    final service = ref.read(diagnosticsServiceProvider);
    if (session == null || service == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = _source == _LogSource.system
          ? await service.systemLog(session)
          : await service.kernelLog(session);
      if (!mounted) return;
      setState(() => _entries = LogEntry.parseAll(result.output));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = const [];
        // Saying "no log entries" when the read failed would suggest the
        // router had nothing to report, which is the opposite of the truth.
        _error = userFacingApiError(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<LogEntry> get _visible {
    final needle = _filter.text.trim().toLowerCase();
    if (needle.isEmpty) return _entries;
    return [
      for (final e in _entries)
        if (e.raw.toLowerCase().contains(needle)) e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visible = _visible;

    return Scaffold(
      appBar: LuciAppBar(
        title: l10n.systemLog,
        showBack: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: l10n.copy,
            onPressed: _entries.isEmpty
                ? null
                : () => copyToClipboard(
                    context,
                    _entries.map((e) => e.raw).join('\n'),
                    label: l10n.systemLog,
                  ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.retry,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(LuciSpacing.md),
            child: SegmentedButton<_LogSource>(
              segments: [
                ButtonSegment(
                  value: _LogSource.system,
                  label: Text(l10n.systemLog),
                ),
                ButtonSegment(
                  value: _LogSource.kernel,
                  label: Text(l10n.kernelLog),
                ),
              ],
              selected: {_source},
              onSelectionChanged: _loading
                  ? null
                  : (s) {
                      setState(() => _source = s.first);
                      _load();
                    },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: LuciSpacing.md),
            child: TextField(
              controller: _filter,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: l10n.filterLog,
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _filter.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(_filter.clear),
                      ),
              ),
            ),
          ),
          const SizedBox(height: LuciSpacing.sm),
          Expanded(child: _body(context, visible)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, List<LogEntry> visible) {
    final l10n = context.l10n;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _Centered(
        icon: Icons.error_outline,
        title: l10n.logUnavailable,
        detail: _error!,
        action: l10n.retry,
        onAction: _load,
      );
    }
    if (_entries.isEmpty) {
      return _Centered(icon: Icons.article_outlined, title: l10n.logEmpty);
    }
    if (visible.isEmpty) {
      return _Centered(icon: Icons.search_off, title: l10n.noMatchingLogLines);
    }

    return ListView.builder(
      // Newest last is how logs read; start the user at the bottom.
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: LuciSpacing.md),
      itemCount: visible.length,
      itemBuilder: (context, i) =>
          _LogRow(entry: visible[visible.length - 1 - i]),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = entry.isProblem
        ? scheme.error
        : entry.isWarning
        ? scheme.tertiary
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A thin severity rail rather than a coloured row: errors need to
          // be findable while scrolling without the log turning into stripes.
          Container(
            width: 3,
            height: 18,
            margin: const EdgeInsets.only(top: 2, right: LuciSpacing.sm),
            decoration: BoxDecoration(
              color: accent ?? Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.timestamp != null)
                  Text(
                    '${entry.timestamp}  ${entry.facility}.${entry.level}',
                    style: TextStyle(
                      fontSize: 11,
                      color: accent ?? scheme.onSurfaceVariant,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                SelectableText(
                  entry.message ?? entry.raw,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({
    required this.icon,
    required this.title,
    this.detail,
    this.action,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(LuciSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: LuciSpacing.md),
          Text(title, style: LuciTextStyles.cardTitle(context)),
          if (detail != null) ...[
            const SizedBox(height: LuciSpacing.sm),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: LuciTextStyles.cardSubtitle(context),
            ),
          ],
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    ),
  );
}
