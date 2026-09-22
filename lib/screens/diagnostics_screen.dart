import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:luci_mobile/l10n/api_error_text.dart';
import 'package:luci_mobile/design/luci_design_system.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:luci_mobile/services/diagnostics_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/widgets/luci_app_bar.dart';

final diagnosticsServiceProvider = Provider<DiagnosticsService?>((ref) {
  final api = ref.watch(apiServiceProvider);
  return api == null ? null : DiagnosticsService(api);
});

/// Ping, traceroute and DNS lookup, run on the router.
///
/// Run *from the router*, which is the point: testing from the phone tells
/// you about the phone's connection, not the router's.
class DiagnosticsScreen extends ConsumerStatefulWidget {
  const DiagnosticsScreen({super.key});

  @override
  ConsumerState<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends ConsumerState<DiagnosticsScreen> {
  final _target = TextEditingController(text: 'openwrt.org');
  DiagnosticTool _tool = DiagnosticTool.ping;
  bool _running = false;
  String? _output;

  /// Kept as the error, not as a sentence; worded when it is shown.
  Object? _error;

  @override
  void dispose() {
    _target.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final session = ref.read(sessionProvider);
    final service = ref.read(diagnosticsServiceProvider);
    final target = _target.text.trim();
    if (session == null || service == null || target.isEmpty) return;

    setState(() {
      _running = true;
      _output = null;
      _error = null;
    });
    try {
      final result = await service.run(session, _tool, target);
      if (!mounted) return;
      setState(() {
        // A non-zero exit is a *result* here, not a failure: "100% packet
        // loss" is exactly what the user ran the tool to find out.
        _output = result.output.isEmpty ? (result.stderr ?? '') : result.output;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: LuciAppBar(title: l10n.diagnostics, showBack: true),
      body: ListView(
        padding: const EdgeInsets.all(LuciSpacing.md),
        children: [
          SegmentedButton<DiagnosticTool>(
            segments: [
              ButtonSegment(
                value: DiagnosticTool.ping,
                label: Text(l10n.toolPing),
                icon: const Icon(Icons.network_ping),
              ),
              ButtonSegment(
                value: DiagnosticTool.traceroute,
                label: Text(l10n.toolTraceroute),
                icon: const Icon(Icons.route),
              ),
              ButtonSegment(
                value: DiagnosticTool.nslookup,
                label: Text(l10n.toolNslookup),
                icon: const Icon(Icons.dns),
              ),
            ],
            selected: {_tool},
            onSelectionChanged: _running
                ? null
                : (s) => setState(() => _tool = s.first),
          ),
          const SizedBox(height: LuciSpacing.md),
          TextField(
            controller: _target,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              labelText: l10n.hostOrAddress,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: l10n.runDiagnostic,
                onPressed: _running ? null : _run,
              ),
            ),
          ),
          const SizedBox(height: LuciSpacing.md),

          if (_running)
            const Padding(
              padding: EdgeInsets.all(LuciSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            ),

          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(LuciSpacing.md),
                child: Text(apiErrorText(context, _error!)),
              ),
            ),

          if (_output != null) _OutputBlock(text: _output!),
        ],
      ),
    );
  }
}

/// Monospaced, selectable command output.
class _OutputBlock extends StatelessWidget {
  const _OutputBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(LuciSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: context.l10n.copy,
                onPressed: () => copyToClipboard(
                  context,
                  text,
                  label: context.l10n.diagnostics,
                ),
              ),
            ),
            SelectableText(
              text.isEmpty ? '—' : text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
