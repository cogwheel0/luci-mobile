import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'package:luci_mobile/l10n/app_localizations.dart';
import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/background_monitor.dart';
import 'package:luci_mobile/services/event_log.dart';
import 'package:luci_mobile/services/notification_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/utils/logger.dart';

/// Keys the foreground writes and the background isolate reads.
///
/// The isolate shares no memory with the app, so everything it needs —
/// which router, what was seen last time, and what the user allows — has to
/// travel through storage.
class BackgroundKeys {
  const BackgroundKeys._();

  static const enabled = 'bg:enabled';
  static const router = 'bg:router';
  static const kinds = 'bg:kinds';

  /// Set when a registration was refused, so the settings screen can say
  /// why the switch is off even when that happened at startup.
  static const schedulingFailed = 'bg:schedulingFailed';
  static String observation(String routerId) => 'bg:last:$routerId';
}

/// Re-registers the periodic poll if the user has it switched on.
///
/// Android drops scheduled work on a force-stop, an app update and (on some
/// builds) a reboot. Without this the switch would still read "on" while
/// nothing ever ran again — the worst kind of silent failure, because the
/// user has no way to tell.
Future<void> ensureScheduled({
  SecureStorageService? storage,
  Future<void> Function(Duration) delay = Future.delayed,
}) => _ensureScheduled(storage ?? SecureStorageService(), delay, _settled);

/// Exists from the moment the library loads, so a settings screen that
/// comes up before [ensureScheduled] has even been called still waits.
Completer<void> _settled = Completer<void>();

/// Completes once startup knows whether the stored switch stands - never
/// with an error. The settings screen reads that switch, and reading it
/// while [ensureScheduled] is still deciding could show "on" over a poll
/// that is about to be turned off. In the normal case this is one storage
/// read and one registration; only a registration that hiccups holds it
/// for the retry.
Future<void> get backgroundStartup => _settled.future;

/// True once [backgroundStartup] has completed.
bool get backgroundStartupSettled => _settled.isCompleted;

/// For a launch on which [ensureScheduled] cannot run - WorkManager itself
/// failed to initialise. Reconciles the stored switch, so it does not read
/// "on" over a poll that was never registered, and unblocks anything
/// waiting on [backgroundStartup].
Future<void> backgroundPollUnavailable({SecureStorageService? storage}) async {
  final store = storage ?? SecureStorageService();
  try {
    if (await store.readValue(BackgroundKeys.enabled) == 'true') {
      await disableBackgroundPoll(store, failed: true, keepRouter: true);
    }
  } catch (e, stack) {
    Logger.exception('Could not switch the poll off in storage', e, stack);
  } finally {
    settleBackgroundStartup();
  }
}

/// Unblocks anything waiting on [backgroundStartup].
void settleBackgroundStartup() {
  if (!_settled.isCompleted) _settled.complete();
}

/// Test hook: a fresh, pending startup.
@visibleForTesting
void resetBackgroundStartup() => _settled = Completer<void>();

Future<void> _ensureScheduled(
  SecureStorageService store,
  Future<void> Function(Duration) delay,
  Completer<void> settled,
) async {
  try {
    if (await store.readValue(BackgroundKeys.enabled) != 'true') return;
    if (await schedulePoll(keepExisting: true)) return;
    // The plugin channel is not always ready the instant the app starts;
    // one hiccup must not switch off a setting the user turned on.
    await delay(const Duration(seconds: 2));
    if (await schedulePoll(keepExisting: true)) return;
    // Refused twice: the switch must not keep reading "on" over a poll
    // that will never run, and the credentials it would have used have no
    // reader. A task registered by an earlier launch may still exist; it
    // goes too, rather than waking the app every 15 minutes to bail out.
    await cancelPoll();
    // The credentials stay: the user is told the device refused, and
    // switching back on must not mean adding the router again.
    await disableBackgroundPoll(store, failed: true, keepRouter: true);
  } catch (e, stack) {
    // Storage refusing at startup is logged, not surfaced: the settings
    // screen must still show its switch.
    Logger.exception(
      'Settling the background poll at startup failed',
      e,
      stack,
    );
  } finally {
    if (!settled.isCompleted) settled.complete();
  }
}

/// Turns the poll off in storage. With [failed], records that it was the
/// platform's refusal rather than the user's choice; with [keepRouter], the
/// stored credentials stay, so switching back on is one tap.
Future<void> disableBackgroundPoll(
  SecureStorageService store, {
  bool failed = false,
  bool keepRouter = false,
}) async {
  await store.writeValue(BackgroundKeys.enabled, 'false');
  if (!keepRouter) await store.deleteValue(BackgroundKeys.router);
  if (failed) {
    await store.writeValue(BackgroundKeys.schedulingFailed, 'true');
  } else {
    await store.deleteValue(BackgroundKeys.schedulingFailed);
  }
}

/// Points the background poll at [router] and drops the old baseline, which
/// belonged to a different router and would report its clients as gone.
Future<void> setMonitoredRouter(
  SecureStorageService store,
  MonitoredRouter router, {
  bool keepBaseline = false,
}) async {
  await store.writeValue(BackgroundKeys.router, jsonEncode(router.toJson()));
  if (!keepBaseline) {
    await store.deleteValue(BackgroundKeys.observation(router.id));
  }
}

/// Points an enabled poll at [router]; a no-op when notifications are off,
/// or when nothing about the router has changed.
///
/// Called on every router switch and whenever the app learns a new way to
/// reach one. Without it the poll keeps using whatever was stored when the
/// switch was flipped: the router selected then, at the address that
/// answered then - and a failover to the other address, which the app
/// handles silently, would leave the poll knocking on the dead one every
/// quarter of an hour while the switch still reads "on".
Future<void> followSelectedRouter(
  MonitoredRouter router, {
  SecureStorageService? storage,
}) async {
  final store = storage ?? SecureStorageService();
  try {
    if (await store.readValue(BackgroundKeys.enabled) != 'true') return;
    final current = await _readRouter(store);
    if (current != null && current.sameAs(router)) return;
    // Only a different router invalidates the baseline; the same one at a
    // new address has the same clients as a moment ago.
    await setMonitoredRouter(
      store,
      router,
      keepBaseline: current?.id == router.id,
    );
  } catch (e, stack) {
    Logger.exception('Could not re-point the background poll', e, stack);
  }
}

/// Stops and forgets the poll when the router it watches is deleted - its
/// address and password would otherwise stay in storage and keep being used.
Future<void> forgetBackgroundRouter(
  String routerId, {
  SecureStorageService? storage,
}) async {
  final store = storage ?? SecureStorageService();
  try {
    // The baseline goes whether or not this was the monitored router: it is
    // per router, and a re-added profile with the same address and account
    // gets the same id.
    await store.deleteValue(BackgroundKeys.observation(routerId));
    final current = await _readRouter(store);
    if (current?.id != routerId) return;
    await cancelPoll();
    await disableBackgroundPoll(store);
  } catch (e, stack) {
    Logger.exception('Could not stop watching a deleted router', e, stack);
  }
}

/// Registers the periodic poll. Returns false when the platform refused.
///
/// [keepExisting] leaves an already-scheduled task alone, so a restart does
/// not reset its timer; the settings toggle replaces it instead.
///
/// The result matters: iOS has no periodic tasks, and an initialise that
/// failed leaves nothing to register with. A switch that turns on over a
/// registration that never happened is exactly the silent failure the
/// notifications screen exists to avoid.
Future<bool> schedulePoll({bool keepExisting = false}) async {
  try {
    await Workmanager().registerPeriodicTask(
      BackgroundMonitor.taskName,
      BackgroundMonitor.taskName,
      frequency: BackgroundMonitor.minimumInterval,
      existingWorkPolicy: keepExisting
          ? ExistingPeriodicWorkPolicy.keep
          : ExistingPeriodicWorkPolicy.replace,
      constraints: Constraints(
        // The router is only reachable over the network, so running
        // without one just burns battery to fail.
        networkType: NetworkType.connected,
      ),
    );
    return true;
  } catch (e, stack) {
    Logger.exception('Scheduling the background poll failed', e, stack);
    return false;
  }
}

Future<void> cancelPoll() async {
  try {
    await Workmanager().cancelByUniqueName(BackgroundMonitor.taskName);
  } catch (e, stack) {
    Logger.exception('Cancelling the background poll failed', e, stack);
  }
}

/// The entry point WorkManager calls. Must be a top-level function.
@pragma('vm:entry-point')
void backgroundDispatcher() {
  Workmanager().executeTask((task, _) async {
    if (task != BackgroundMonitor.taskName) return true;
    try {
      await runBackgroundPoll();
    } catch (e, stack) {
      Logger.exception('Background poll failed', e, stack);
    }
    // Always true: returning false makes WorkManager retry with backoff,
    // and a router that is simply out of range is not a failure to retry —
    // the next scheduled run is soon enough.
    return true;
  });
}

/// Polls the monitored router once and notifies about what changed.
Future<void> runBackgroundPoll({
  SecureStorageService? storage,
  IApiServiceFactory? apiFactory,
  NotificationService? notifications,
  DateTime Function()? clock,
}) async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = storage ?? SecureStorageService();
  final now = (clock ?? DateTime.now)();

  if (await store.readValue(BackgroundKeys.enabled) != 'true') return;

  final router = await _readRouter(store);
  if (router == null) return;

  final api = (apiFactory ?? _defaultApiFactory)();
  final String sysauth;
  try {
    sysauth = await api.login(
      router.ipAddress,
      router.username,
      router.password,
      router.useHttps,
    );
  } catch (e) {
    // Off the network, asleep, or the password changed. None of those is
    // something to wake the user about.
    Logger.info('Background poll could not reach ${router.ipAddress}: $e');
    return;
  }

  var current = await _observe(api, router, sysauth, at: now);
  if (current == null) return;

  final stored = await _readObservation(store, router.id);
  final baseline = (stored == null || stored.isStale(now))
      ? null
      : stored.observation;
  // A poll whose `system.info` failed has nothing to say about the clocks;
  // the last reading stands, so a reboot across the gap is still seen.
  if (current.uptime == null) current = current.withClocksOf(baseline);

  await store.writeValue(
    BackgroundKeys.observation(router.id),
    jsonEncode(StoredObservation(observation: current, at: now).toJson()),
  );

  // Everything that happened goes in the feed - departures, the joins past
  // the notification cap - because the feed is the record; the notification
  // is only the nudge, and is filtered and capped separately.
  final all = baseline == null
      ? const <RouterEvent>[]
      : EventDeriver.diff(
          previous: baseline,
          current: current,
          routerId: router.id,
          at: now,
        );
  if (all.isEmpty) return;
  await EventLog(store).append(router.id, all, fromBackground: true);

  final kinds = await readNotificationKinds(store);
  final events = BackgroundMonitor.capped(
    BackgroundMonitor.notifiable(all, kinds: kinds),
  );
  if (events.isEmpty) return;

  final l10n = await _localizations();
  await (notifications ?? NotificationService()).show([
    for (final event in events) (event: event, text: _describe(l10n, event)),
  ], channelName: l10n.notifyChannelName);
}

Future<RouterObservation?> _observe(
  IApiService api,
  MonitoredRouter router,
  String sysauth, {
  required DateTime at,
}) async {
  try {
    // The calls the dashboard makes, and no more: a background poll should
    // cost the router as little as the foreground one does. `system.info`
    // is there for its uptime and clock, which is how a reboot is noticed.
    final results = await Future.wait([
      api.call(
        router.ipAddress,
        sysauth,
        router.useHttps,
        object: 'network.interface',
        method: 'dump',
      ),
      api.call(
        router.ipAddress,
        sysauth,
        router.useHttps,
        object: 'luci-rpc',
        method: 'getDHCPLeases',
        params: const {},
      ),
      api
          .call(
            router.ipAddress,
            sysauth,
            router.useHttps,
            object: 'system',
            method: 'info',
            params: const {},
          )
          .catchError((Object e) {
            // Uptime is a nice-to-have; a router that refuses it still has a
            // WAN and clients worth reporting on.
            Logger.info('Background poll could not read uptime: $e');
            return null;
          }),
    ]);

    final dump = _payload(results[0]);
    final leaseData = _payload(results[1]);
    final leases = leaseData is Map ? leaseData['dhcp_leases'] : null;
    final sysInfo = _payload(results[2]);

    final wan = wanStateFrom(dump);
    // An unreadable interface dump is not a router with no uplink; there is
    // nothing to compare and this poll is skipped.
    if (wan == null) return null;

    return EventDeriver.observe(
      reachable: true,
      dashboardData: {'wan': wan, if (sysInfo is Map) 'sysInfo': sysInfo},
      clients: clientsFromLeases(leases is List ? leases : const []),
      readAt: at,
    );
  } catch (e, stack) {
    Logger.exception('Background observation failed', e, stack);
    return null;
  }
}

/// Unwraps ubus's `[status, data]` envelope.
dynamic _payload(dynamic result) =>
    result is List && result.length > 1 && result[0] == 0 ? result[1] : null;

/// The WAN block in the shape `EventDeriver.observe` expects, or null when
/// the dump says nothing at all and this poll should be skipped.
///
/// An interface is the uplink when it carries a default route - the rule
/// the dashboard uses, so the two halves of this feature agree - or, for an
/// interface that is down and so has no route left, when it is named like
/// one. A name alone was not enough: on an LTE or tethered uplink named
/// `mobile` or `usb0` the WAN was reported permanently down, and no
/// transition could ever fire.
@visibleForTesting
Map<String, dynamic>? wanStateFrom(dynamic dump) {
  final interfaces = dump is Map ? dump['interface'] : null;
  if (interfaces is! List) return null;
  // Any uplink being up means there is internet. Stopping at the first
  // match let a down `wan6` mask an up `wan`, which the deriver then
  // reported as "Internet connection lost" — a push notification about an
  // outage that never happened.
  var up = false;
  for (final entry in interfaces) {
    if (entry is! Map) continue;
    final name = entry['interface']?.toString() ?? '';
    final isUplink =
        _carriesDefaultRoute(entry) ||
        name.startsWith('wan') ||
        name.startsWith('wwan');
    if (!isUplink) continue;
    up = up || entry['up'] == true;
  }
  return {'up': up};
}

bool _carriesDefaultRoute(Map interface) {
  final routes = interface['route'];
  if (routes is! List) return false;
  return routes.any(
    (r) => r is Map && r['target'] == '0.0.0.0' && r['mask'] == 0,
  );
}

Future<MonitoredRouter?> _readRouter(SecureStorageService store) async {
  try {
    final raw = await store.readValue(BackgroundKeys.router);
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic>
        ? MonitoredRouter.fromJson(decoded)
        : null;
  } catch (e, stack) {
    Logger.exception('Reading the monitored router failed', e, stack);
    return null;
  }
}

Future<StoredObservation?> _readObservation(
  SecureStorageService store,
  String routerId,
) async {
  try {
    final raw = await store.readValue(BackgroundKeys.observation(routerId));
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic>
        ? StoredObservation.fromJson(decoded)
        : null;
  } catch (e, stack) {
    Logger.exception('Reading the last observation failed', e, stack);
    return null;
  }
}

/// The event kinds the user wants notified about.
///
/// Shared with the settings screen: the background poll and the foreground
/// toggle must agree on what is stored, or the switches lie.
Future<Set<RouterEventKind>> readNotificationKinds(
  SecureStorageService store,
) async {
  try {
    final raw = await store.readValue(BackgroundKeys.kinds);
    if (raw == null || raw.isEmpty) return notifiableKinds;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return notifiableKinds;
    final names = {for (final n in decoded) n.toString()};
    final kinds = {
      for (final kind in notifiableKinds)
        if (names.contains(kind.name)) kind,
    };
    return kinds;
  } catch (e, stack) {
    Logger.exception('Reading notification kinds failed', e, stack);
    return notifiableKinds;
  }
}

/// The localizations for the device's language.
///
/// The isolate has no BuildContext, but the delegate does not need one: it
/// loads from the bundle. Without this the lock screen said "Internet
/// connection lost" in English while the in-app feed said the same thing
/// in the user's language, from strings that were already translated.
Future<AppLocalizations> _localizations() async {
  final system = PlatformDispatcher.instance.locale;
  final supported = AppLocalizations.supportedLocales;
  final exact = supported.where(
    (l) =>
        l.languageCode == system.languageCode &&
        l.countryCode == system.countryCode,
  );
  final byLanguage = supported.where(
    (l) => l.languageCode == system.languageCode,
  );
  final locale =
      exact.firstOrNull ?? byLanguage.firstOrNull ?? const Locale('en');
  return AppLocalizations.delegate.load(locale);
}

/// Notification text, in the same words the in-app feed uses.
String _describe(AppLocalizations l10n, RouterEvent event) =>
    switch (event.kind) {
      RouterEventKind.wanDown => l10n.eventWanDown,
      RouterEventKind.wanUp => l10n.eventWanUp,
      RouterEventKind.rebooted => l10n.eventRebooted,
      RouterEventKind.clientJoined => l10n.eventClientJoined(
        event.subject ?? '?',
      ),
      RouterEventKind.clientLeft => l10n.eventClientLeft(event.subject ?? '?'),
      RouterEventKind.routerUnreachable => l10n.eventRouterUnreachable,
      RouterEventKind.routerBack => l10n.eventRouterBack,
    };

typedef IApiServiceFactory = IApiService Function();

IApiService _defaultApiFactory() => RealApiService();
