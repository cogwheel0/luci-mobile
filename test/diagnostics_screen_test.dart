import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:luci_mobile/screens/diagnostics_screen.dart';
import 'package:luci_mobile/services/diagnostics_service.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/state/app_state_provider.dart';
import 'package:luci_mobile/state/router_session.dart';
import 'package:luci_mobile/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';

const _session = RouterSession(
  routerId: 'r1',
  ipAddress: '192.168.1.1',
  sysauth: 'sysauth',
  useHttps: false,
  token: 1,
);

/// Answers every run with a ping's output, or fails when [fails].
class _Diagnostics extends DiagnosticsService {
  _Diagnostics({this.fails = false}) : super(MockApiService());

  final bool fails;

  @override
  Future<DiagnosticResult> run(
    RouterSession session,
    DiagnosticTool tool,
    String target,
  ) async {
    if (fails) throw Exception('unreachable');
    return const DiagnosticResult(output: '64 bytes from 1.1.1.1', exitCode: 0);
  }
}

/// Shows Diagnostics and runs a ping.
Future<void> _runPing(WidgetTester tester, {bool fails = false}) async {
  tester.view
    ..physicalSize = const Size(1800, 3600)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWithValue(_session),
        diagnosticsServiceProvider.overrideWithValue(
          _Diagnostics(fails: fails),
        ),
      ],
      child: const MaterialApp(home: DiagnosticsScreen()),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(
    PlatformUiCapabilities.isIOS
        ? find.byWidgetPredicate(
            (w) => w is AdaptiveButton && w.semanticLabel == 'Run',
          )
        : find.byTooltip('Run'),
  );
  await tester.pumpAndSettle();
}

/// The output, selectable.
Finder _output(String text) =>
    find.byWidgetPredicate((w) => w is SelectableText && w.data == text);

void main() {
  tearDown(PlatformUiCapabilities.resetDebugOverrides);

  testWidgets('Android: the output on a raised card', (tester) async {
    PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.android;
    await _runPing(tester);

    expect(
      find.ancestor(
        of: _output('64 bytes from 1.1.1.1'),
        matching: find.byType(Card),
      ),
      findsOneWidget,
    );
  });

  group('before iOS 26', () {
    setUp(() {
      PlatformUiCapabilities.debugPlatformOverride = TargetPlatform.iOS;
      PlatformUiCapabilities.debugIOSMajorVersionOverride = 25;
    });

    testWidgets('the output on a flat tile of the grouped list', (
      tester,
    ) async {
      await _runPing(tester);

      final output = _output('64 bytes from 1.1.1.1');
      expect(output, findsOneWidget);
      expect(find.byType(Card), findsNothing);
      final tile = tester.widget<DecoratedBox>(
        find.ancestor(of: output, matching: find.byType(DecoratedBox)).first,
      );
      final context = tester.element(output);
      expect(
        (tile.decoration as BoxDecoration).color,
        CupertinoColors.secondarySystemGroupedBackground.resolveFrom(context),
      );
    });

    testWidgets('a failure in red on a flat tile', (tester) async {
      await _runPing(tester, fails: true);

      expect(find.byType(Card), findsNothing);
      final error = find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.style?.color ==
                CupertinoColors.systemRed.resolveFrom(
                  tester.element(find.byType(DiagnosticsScreen)),
                ),
      );
      expect(error, findsOneWidget);
    });
  });
}
