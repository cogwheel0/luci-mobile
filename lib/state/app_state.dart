import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/services/router_service.dart';
import 'package:luci_mobile/services/throughput_service.dart';
import 'package:luci_mobile/models/client.dart';
import 'package:luci_mobile/models/router.dart' as model;
import 'package:luci_mobile/models/dashboard_preferences.dart';
import 'package:luci_mobile/models/glinet_data.dart';
import 'package:luci_mobile/services/interfaces/auth_service_interface.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/interfaces/glinet_api_service_interface.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/service_factory.dart';
import 'package:luci_mobile/config/app_config.dart';
import 'package:luci_mobile/utils/http_client_manager.dart';
import 'package:luci_mobile/utils/logger.dart';
import 'package:luci_mobile/models/wifi_scan_result.dart';

class AppState extends ChangeNotifier {
  static AppState? _instance;

  late final SecureStorageService _secureStorageService;
  IApiService? _apiService;
  IAuthService? _authService;
  IGlInetApiService? _glInetService;
  RouterService? _routerService;
  ThroughputService? _throughputService;
  final HttpClientManager _httpClientManager = HttpClientManager();

  // Reviewer mode state
  bool _reviewerModeEnabled = false;
  bool get reviewerModeEnabled => _reviewerModeEnabled;

  bool _isLoading = false;
  String? _errorMessage;
  bool? _canReboot;
  String? _rebootAccessError;
  int _rebootAccessRequestId = 0;

  Map<String, dynamic>? _dashboardData;
  bool _isDashboardLoading = false;
  String? _dashboardError;

  Timer? _throughputTimer;
  Timer? _pollingTimer;
  Timer? _rebootDelayTimer;
  int _pollAttempts = 0;
  static const int _maxPollAttempts =
      40; // Max 40 attempts = ~5 minutes with backoff

  // Target of the reboot poll, captured when reboot starts so that switching
  // routers or logging out mid-reboot can't redirect the poll elsewhere.
  String? _rebootTargetIp;
  bool _rebootTargetUseHttps = false;

  // Monotonically increasing generation for reboot-recovery cycles. Bumped
  // by every cancel/start so an in-flight liveness probe from an older
  // cycle can never act on newer recovery state.
  int _rebootCycleId = 0;

  // Monotonically increasing token used to discard stale async results
  // (e.g. a slow dashboard fetch from router A resolving after the user
  // already switched to router B).
  int _sessionToken = 0;

  // Guards against overlapping throughput polls on slow links.
  bool _throughputUpdateInFlight = false;

  // Set when dispose() runs; suppresses late async notifications.
  bool _isDisposed = false;

  // Serializes authentication operations (login/logout) so overlapping
  // calls cannot interleave mutations of the shared auth-service session
  // fields. A generation check alone cannot undo a stale write.
  Future<void> _authOpQueue = Future<void>.value();

  Future<T> _serializeAuthOp<T>(Future<T> Function() action) {
    final op = _authOpQueue.then((_) => action());
    _authOpQueue = op.then((_) {}, onError: (_) {});
    return op;
  }

  // Add rebooting state
  bool _isRebooting = false;
  bool get isRebooting => _isRebooting;

  // Theme mode state
  ThemeMode _themeMode = ThemeMode.system;
  static const String _themeModeKey = 'themeMode';

  // Clients view mode (aggregate across routers)
  bool _clientsAggregateAllRouters = true;
  static const String _clientsAggregateKey = 'clients_aggregate_all';
  bool get clientsAggregateAllRouters => _clientsAggregateAllRouters;

  // Dashboard preferences state
  DashboardPreferences _dashboardPreferences = DashboardPreferences();
  DashboardPreferences get dashboardPreferences => _dashboardPreferences;

  List<model.Router> get routers => _routerService?.routers ?? [];
  model.Router? get selectedRouter => _routerService?.selectedRouter;

  VoidCallback? onRouterBackOnline;

  // Add requestedTab for programmatic tab switching
  int? requestedTab;
  String? requestedInterfaceToScroll;

  void requestTab(int index, {String? interfaceToScroll}) {
    requestedTab = index;
    requestedInterfaceToScroll = interfaceToScroll;
    notifyListeners();
  }

  AppState._() {
    _initialize();
  }

  @visibleForTesting
  AppState.forTesting({
    required IApiService apiService,
    required IAuthService authService,
    IGlInetApiService? glInetApiService,
  }) : _apiService = apiService,
       _authService = authService,
       _glInetService = glInetApiService;

  static AppState get instance {
    return _instance ??= AppState._();
  }

  Future<void> _initialize() async {
    await _loadReviewerMode();
    _initializeServices();
    await _loadThemeMode();
    await loadRouters(); // Load routers on app start (sets selectedRouter)
    await _migrateGlobalDashboardPreferencesIfNeeded(); // Proactively migrate legacy prefs
    await _loadClientsViewMode();
    await loadDashboardPreferences(); // Load prefs scoped to selected router
  }

  /// One-time migration: if a global 'dashboard_preferences' exists,
  /// copy it to each router-specific key that doesn't already have prefs.
  Future<void> _migrateGlobalDashboardPreferencesIfNeeded() async {
    try {
      final globalKey = 'dashboard_preferences';
      final globalJson = await _secureStorageService.readValue(globalKey);
      if (globalJson == null || globalJson.isEmpty) return;

      final routers = _routerService?.routers ?? const <model.Router>[];
      if (routers.isEmpty) return;

      // Validate JSON format before writing
      try {
        jsonDecode(globalJson);
      } catch (_) {
        return; // Not valid JSON; skip migration
      }

      for (final router in routers) {
        final key = 'dashboard_preferences:${router.id}';
        final existing = await _secureStorageService.readValue(key);
        if (existing == null || existing.isEmpty) {
          await _secureStorageService.writeValue(key, globalJson);
        }
      }

      // If all routers now have scoped prefs, remove the legacy global key
      var allHavePrefs = true;
      for (final router in routers) {
        final key = 'dashboard_preferences:${router.id}';
        final v = await _secureStorageService.readValue(key);
        if (v == null || v.isEmpty) {
          allHavePrefs = false;
          break;
        }
      }
      if (allHavePrefs) {
        await _secureStorageService.deleteValue(globalKey);
      }
    } catch (e, stack) {
      Logger.exception(
        'Failed migrating global dashboard preferences',
        e,
        stack,
      );
    }
  }

  Future<void> _loadReviewerMode() async {
    // Initialize secure storage service with default factory first
    ServiceContainer.configure(reviewerMode: false);
    _secureStorageService = ServiceContainer.instance.factory
        .createSecureStorageService();

    final stored = await _secureStorageService.readValue(
      AppConfig.reviewerModeKey,
    );
    _reviewerModeEnabled = stored == 'true';
  }

  void _initializeServices() {
    // Configure the service container based on reviewer mode
    ServiceContainer.configure(reviewerMode: _reviewerModeEnabled);

    // Create services using the factory
    final factory = ServiceContainer.instance.factory;
    _authService = factory.createAuthService();
    _apiService = factory.createApiService();
    _glInetService = factory.createGlInetApiService();
    _routerService = factory.createRouterService();
    _throughputService = factory.createThroughputService();
  }

  Future<void> setReviewerMode(bool enabled) async {
    _reviewerModeEnabled = enabled;
    await _secureStorageService.writeValue(
      AppConfig.reviewerModeKey,
      enabled.toString(),
    );
    _initializeServices();
    notifyListeners();
  }

  Future<void> _loadThemeMode() async {
    final stored = await _secureStorageService.readValue(_themeModeKey);
    if (stored == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (stored == 'light') {
      _themeMode = ThemeMode.light;
    } else if (stored == 'system') {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  ThemeMode get themeMode => _themeMode;
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _secureStorageService.writeValue(_themeModeKey, mode.name);
    notifyListeners();
  }

  Future<void> _loadClientsViewMode() async {
    final stored = await _secureStorageService.readValue(_clientsAggregateKey);
    if (stored == 'true') {
      _clientsAggregateAllRouters = true;
    } else if (stored == 'false') {
      _clientsAggregateAllRouters = false;
    }
  }

  Future<void> setClientsAggregateAllRouters(bool aggregate) async {
    _clientsAggregateAllRouters = aggregate;
    await _secureStorageService.writeValue(
      _clientsAggregateKey,
      aggregate.toString(),
    );
    notifyListeners();
  }

  /// Loads dashboard preferences scoped to the selected router. When
  /// [expectedToken] is provided, results are discarded if the session
  /// changed while loading - rapid router switches must not apply the
  /// previous router's preferences to the new one.
  Future<void> loadDashboardPreferences({int? expectedToken}) async {
    try {
      // Scope preferences by selected router if available
      final routerId = _routerService?.selectedRouter?.id;
      final key = routerId != null
          ? 'dashboard_preferences:$routerId'
          : 'dashboard_preferences';

      // Try router-specific key first
      String? json = await _secureStorageService.readValue(key);
      // Backward-compat: if missing, fall back to global key
      if ((json == null || json.isEmpty) && routerId != null) {
        json = await _secureStorageService.readValue('dashboard_preferences');
      }
      // The selection changed while loading - these are the previous
      // router's preferences; applying them would leak state across
      // routers and a later save could persist them under the wrong key.
      if (expectedToken != null && expectedToken != _sessionToken) return;
      if (json != null && json.isNotEmpty) {
        _dashboardPreferences = DashboardPreferences.fromJson(jsonDecode(json));
        notifyListeners();
      }
    } catch (e, stack) {
      Logger.exception('Failed to load dashboard preferences', e, stack);
      // A stale read must not reset the newly selected router's
      // preferences to defaults (a later save would persist them).
      if (expectedToken != null && expectedToken != _sessionToken) return;
      _dashboardPreferences = DashboardPreferences();
    }
  }

  Future<void> saveDashboardPreferences(DashboardPreferences prefs) async {
    try {
      _dashboardPreferences = prefs;
      final routerId = _routerService?.selectedRouter?.id;
      final key = routerId != null
          ? 'dashboard_preferences:$routerId'
          : 'dashboard_preferences';
      await _secureStorageService.writeValue(key, jsonEncode(prefs.toJson()));
      notifyListeners();
    } catch (e, stack) {
      Logger.exception('Failed to save dashboard preferences', e, stack);
      rethrow;
    }
  }

  String? get sysauth => _authService?.sysauth;
  bool get isAuthenticated => _authService?.isAuthenticated ?? false;
  bool get hasRouters =>
      _routerService != null && _routerService!.routers.isNotEmpty;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool? get canReboot => _reviewerModeEnabled ? true : _canReboot;
  String? get rebootAccessError => _rebootAccessError;

  void setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  Map<String, dynamic>? get dashboardData => _dashboardData;
  List<double> get rxHistory => _throughputService?.rxHistory ?? [];
  List<double> get txHistory => _throughputService?.txHistory ?? [];
  double get currentRxRate => _throughputService?.currentRxRate ?? 0.0;
  double get currentTxRate => _throughputService?.currentTxRate ?? 0.0;
  bool get isDashboardLoading => _isDashboardLoading;
  String? get dashboardError => _dashboardError;

  // Interface-specific throughput getters
  List<double> getRxHistoryForInterface(String interface) {
    final deviceName = _getDeviceNameForInterface(interface);
    return _throughputService?.getRxHistoryForInterface(
          deviceName ?? interface,
        ) ??
        [];
  }

  List<double> getTxHistoryForInterface(String interface) {
    final deviceName = _getDeviceNameForInterface(interface);
    return _throughputService?.getTxHistoryForInterface(
          deviceName ?? interface,
        ) ??
        [];
  }

  double getCurrentRxRateForInterface(String interface) {
    final deviceName = _getDeviceNameForInterface(interface);
    return _throughputService?.getCurrentRxRateForInterface(
          deviceName ?? interface,
        ) ??
        0.0;
  }

  double getCurrentTxRateForInterface(String interface) {
    final deviceName = _getDeviceNameForInterface(interface);
    return _throughputService?.getCurrentTxRateForInterface(
          deviceName ?? interface,
        ) ??
        0.0;
  }

  Future<void> loadRouters() async {
    await _routerService?.loadRouters();
    notifyListeners();
  }

  Future<void> addRouter(model.Router router) async {
    await _routerService?.addRouter(router);
    notifyListeners();
  }

  Future<void> removeRouter(String id) async {
    if (_routerService == null) return;

    // Get the router before removing to clear its certificates
    final router = _routerService!.routers.firstWhere(
      (r) => r.id == id,
      orElse: () => throw Exception('Router not found'),
    );

    // Clear certificates for this specific router
    await _httpClientManager.clearCertificatesForHost(router.ipAddress);
    if (router.alternateAddress != null) {
      await _httpClientManager.clearCertificatesForHost(
        router.alternateAddress!,
      );
    }

    final needsSwitch = await _routerService!.removeRouter(id);
    if (needsSwitch && _routerService!.routers.isNotEmpty) {
      await selectRouter(_routerService!.routers.first.id);
    } else if (_routerService!.routers.isEmpty) {
      // All routers deleted — clear auth state so tryAutoLogin won't
      // succeed with stale credentials and cause a navigation loop
      await logout();
    } else {
      notifyListeners();
    }
  }

  Future<void> selectRouter(String id, {BuildContext? context}) async {
    if (_routerService == null || _routerService!.routers.isEmpty) return;

    final found = _routerService!.selectRouter(id);
    if (found == null) return;

    // Invalidate any in-flight requests from the previously selected router
    _sessionToken++;
    final token = _sessionToken;
    _cancelRebootPolling();
    // Cancelling the poll removes the only path that clears this flag, so
    // reset it here or the new router gets no throughput timer.
    _isRebooting = false;

    _isLoading = true;
    _dashboardError = null;
    _canReboot = null;
    _rebootAccessError = null;

    // Clear throughput data and GL.iNet session when switching routers
    _cancelThroughputTimer();
    _glInetService?.clearSession();

    // Determine a safe context before any awaits
    final safeContext = context?.mounted == true
        ? context
        : null; // ignore: use_build_context_synchronously

    // Load router-scoped dashboard preferences immediately on selection
    await loadDashboardPreferences(expectedToken: token);
    if (token != _sessionToken) return;

    notifyListeners();
    // ignore: use_build_context_synchronously
    final loginSuccess = await login(
      found.activeAddress,
      found.username,
      found.password,
      found.activeUseHttps,
      fromRouter: true,
      alternateAddress: found.inactiveAddress,
      alternateUseHttps: found.inactiveUseHttps,
      activeAddressIndex: found.activeAddressIndex,
      context: safeContext, // ignore: use_build_context_synchronously
    );
    // A newer session started while this switch was in flight - it owns the
    // loading and error state now.
    if (token != _sessionToken) return;
    // login() already fetches dashboard data on success; fetching again here
    // would double the RPC burst on every router switch.
    if (!loginSuccess) {
      _dashboardError =
          'Login Failed: Invalid credentials or host unreachable.';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> updateRouter(model.Router router) async {
    await _routerService?.updateRouter(router);
    notifyListeners();
  }

  Future<bool> login(
    String ip,
    String user,
    String pass,
    bool useHttps, {
    bool fromRouter = false,
    String? alternateAddress,
    bool? alternateUseHttps,
    int activeAddressIndex = 0,
    BuildContext? context,
  }) async {
    // A fresh login starts a new session; discard stale results from the
    // previous one. A manual login also supersedes any pending reboot
    // recovery - that recovery belongs to the session that started it and
    // must not adopt the replacement session.
    //
    // When delegated from selectRouter, the selection already bumped the
    // token and captured it - incrementing again here would make every
    // post-login check in selectRouter see a stale session (e.g. failed
    // saved-router logins could never surface their error).
    if (!fromRouter) {
      _sessionToken++;
      _cancelRebootPolling();
      _isRebooting = false;
    }
    final token = _sessionToken;
    _isLoading = true;
    _errorMessage = null;
    _canReboot = null;
    _rebootAccessError = null;

    // Clear throughput data when logging in to prevent mixing data from different sessions
    _cancelThroughputTimer();

    notifyListeners();

    try {
      final result = await _serializeAuthOp<FallbackLoginResult>(
        () => _authService!.loginWithFallback(
          activeAddress: ip,
          activeHttps: useHttps,
          activeIndex: activeAddressIndex,
          fallbackAddress: alternateAddress,
          fallbackHttps: alternateUseHttps,
          username: user,
          password: pass,
          context: context,
        ),
      );
      // A newer session (logout / another login) superseded this one while
      // the credential exchange was in flight - do not touch any state.
      if (token != _sessionToken) return false;

      if (result.success && _authService!.isAuthenticated) {
        final actualUseHttps = _authService!.useHttps;

        if (!fromRouter) {
          if (_routerService != null) {
            final primaryUseHttps = result.usedAddressIndex == 0
                ? actualUseHttps
                : useHttps;
            final router = _routerService!.createRouter(
              ip,
              user,
              pass,
              primaryUseHttps,
            );
            // Preserve alternate address in the new router
            final routerWithAlternate = router.copyWith(
              alternateAddress: alternateAddress,
              alternateUseHttps: result.usedAddressIndex == 1
                  ? actualUseHttps
                  : alternateUseHttps,
              activeAddressIndex: result.usedAddressIndex,
            );
            final idx = _routerService!.routers.indexWhere(
              (r) => r.id == routerWithAlternate.id,
            );
            if (idx == -1) {
              await addRouter(routerWithAlternate);
            } else {
              await updateRouter(routerWithAlternate);
            }
          }
        } else if (_routerService != null) {
          final router = _routerService!.selectedRouter;
          if (router != null) {
            final needsUpdate =
                actualUseHttps != useHttps ||
                result.usedAddressIndex != router.activeAddressIndex;
            if (needsUpdate) {
              final updatedRouter = result.usedAddressIndex == 0
                  ? router.copyWith(
                      useHttps: actualUseHttps,
                      activeAddressIndex: 0,
                    )
                  : router.copyWith(
                      alternateUseHttps: actualUseHttps,
                      activeAddressIndex: 1,
                    );
              await updateRouter(updatedRouter);
              if (result.usedAddressIndex != router.activeAddressIndex) {
                Logger.info(
                  'Switched to ${result.usedAddressIndex == 0 ? "primary" : "alternate"} address',
                );
              }
            }
          }
        }
        await fetchDashboardData();
        if (token != _sessionToken) return false;
        _startThroughputTimer();
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        if (token != _sessionToken) return false;
        _errorMessage =
            'Login Failed: Invalid credentials or host unreachable.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      if (token != _sessionToken) return false;
      _errorMessage = 'An error occurred: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    final token = ++_sessionToken;
    _cancelRebootPolling();
    _isRebooting = false;
    try {
      await _serializeAuthOp<void>(
        () => _authService?.logout() ?? Future<void>.value(),
      );
    } catch (e) {
      // Storage cleanup may have been incomplete; still clear in-memory
      // session state and proceed with logout.
      Logger.exception(
        'Credential cleanup incomplete during logout',
        e,
        StackTrace.current,
      );
    }
    // A newer session started while cleanup ran - it owns the state now.
    if (token != _sessionToken) return;
    _glInetService?.clearSession();
    _dashboardData = null;
    _dashboardError = null;
    _canReboot = null;
    _rebootAccessError = null;
    _cancelThroughputTimer();
    notifyListeners();
  }

  Future<void> fetchDashboardData({bool isRetryAfterFallback = false}) async {
    if (_reviewerModeEnabled) {
      // For reviewer mode, return mock data immediately
      _isDashboardLoading = true;
      _dashboardError = null;
      notifyListeners();

      await Future.delayed(
        const Duration(milliseconds: 500),
      ); // Simulate network delay

      try {
        final results = await Future.wait([
          _apiService!.callSimple('system', 'board', {}),
          _apiService!.callSimple('system', 'info', {}),
          _apiService!.callSimple('network', 'device', {}),
          _apiService!.callSimple('network.interface', 'dump', {}),
          _apiService!.callSimple('wireless', 'devices', {}),
          _apiService!.callSimple('luci-rpc', 'getDHCPLeases', {}),
          _apiService!.callSimple('uci', 'get', {'config': 'wireless'}),
        ]);

        final interfaceDump = results[3][1] as Map<String, dynamic>;
        final rawDhcpData = results[5][1] as Map<String, dynamic>;
        final processedDhcpData = _processDhcpLeases(rawDhcpData);

        _dashboardData = {
          'boardInfo': results[0][1],
          'sysInfo': results[1][1],
          'networkDevices': results[2][1],
          'interfaceDump': interfaceDump,
          'wireless': results[4][1],
          'dhcpLeases': processedDhcpData,
          'uciWirelessConfig': results[6][1],
          'wan': _extractWanData(interfaceDump),
          'wireguard': <String, dynamic>{}, // Empty for reviewer mode
          '_lastUpdated':
              DateTime.now().millisecondsSinceEpoch, // Force UI updates
        };
        _canReboot = true;
        _rebootAccessError = null;

        // Update throughput data with mock network data for reviewer mode
        if (_throughputService != null) {
          final networkData = results[2][1] as Map<String, dynamic>?;
          final wanDeviceNames = {
            'eth0',
            'wlan0',
            'br-lan',
          }; // Mock all devices

          // Check if we should track specific interface
          final prefs = _dashboardPreferences;
          String? specificInterface;
          if (!prefs.showAllThroughput &&
              prefs.primaryThroughputInterface != null) {
            // Map interface name to actual device name
            specificInterface = _getDeviceNameForInterface(
              prefs.primaryThroughputInterface!,
            );
          }

          _throughputService!.updateThroughput(
            networkData,
            wanDeviceNames,
            specificInterface: specificInterface,
          );
        }

        // Start throughput timer for reviewer mode
        _startThroughputTimer();

        // Schedule an immediate throughput update to get initial data faster
        Future.delayed(const Duration(milliseconds: 100), () {
          _updateThroughputOnly();
        });

        _isDashboardLoading = false;
        notifyListeners();
      } catch (e) {
        _dashboardError = 'Failed to fetch dashboard data: $e';
        _isDashboardLoading = false;
        notifyListeners();
      }
      return;
    }

    if (_routerService?.selectedRouter == null ||
        _authService?.sysauth == null) {
      return;
    }

    // If already loading, don't start another request (but this shouldn't prevent pull-to-refresh)
    // We'll let the new request proceed and the loading state will be handled properly
    final selectedRouter = _routerService!.selectedRouter!;
    // Use the address and protocol that actually succeeded during login.
    final ip = _authService!.ipAddress ?? selectedRouter.activeAddress;
    final useHttps = _authService!.useHttps;
    final routerPassword = selectedRouter.password;
    // Snapshot the credentials for this exact session: reading the mutable
    // auth service mid-flight could send newer credentials to this router.
    final sysauth = _authService!.sysauth!;
    final token = _sessionToken;

    _isDashboardLoading = true;
    _dashboardError = null;
    _canReboot = null;
    _rebootAccessError = null;
    final rebootAccessRequestId = ++_rebootAccessRequestId;
    notifyListeners();

    unawaited(
      _refreshRebootAccess(
        ip: ip,
        sysauth: sysauth,
        useHttps: useHttps,
        token: token,
        requestId: rebootAccessRequestId,
      ),
    );

    try {
      // Perform all API calls in parallel
      Future<dynamic> callOptionalRpc({
        required String object,
        required String method,
        Map<String, dynamic>? params,
      }) async {
        try {
          return await _apiService!.call(
            ip,
            sysauth,
            useHttps,
            object: object,
            method: method,
            params: params,
          );
        } catch (e, stack) {
          Logger.warning('Optional RPC $object.$method failed: $e');
          Logger.debug('Optional RPC $object.$method stack: $stack');
          return null;
        }
      }

      final wirelessFuture = callOptionalRpc(
        object: 'luci-rpc',
        method: 'getWirelessDevices',
        params: {},
      );

      // UCI wireless config is optional — wired-only routers may not have it
      final uciWirelessFuture = callOptionalRpc(
        object: 'uci',
        method: 'get',
        params: {'config': 'wireless'},
      );

      final results = await Future.wait([
        _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'system',
          method: 'board',
          params: {},
        ),
        _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'system',
          method: 'info',
          params: {},
        ),
        _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'luci-rpc',
          method: 'getNetworkDevices',
          params: {},
        ),
        _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'network.interface',
          method: 'dump',
          params: {},
        ),
        _apiService!.call(
          ip,
          sysauth,
          useHttps,
          object: 'luci-rpc',
          method: 'getDHCPLeases',
          params: {},
        ),
      ]);

      // Helper to safely extract data and handle errors from LuCI's [status, data] responses
      dynamic getData(dynamic result) {
        if (result is List && result.length > 1) {
          if (result[0] == 0) {
            return result[1]; // Success
          } else {
            // Throw an exception with the error message from the API
            final errorMessage = result[1] is String
                ? result[1]
                : 'Unknown API Error';
            throw Exception(errorMessage);
          }
        }
        // Handle cases where the result is not in the expected format
        return result;
      }

      dynamic getOptionalData(dynamic result, String label) {
        try {
          return getData(result);
        } catch (e) {
          Logger.warning('Optional RPC $label returned error: $e');
          return null;
        }
      }

      final boardInfoData = getData(results[0]);
      final sysInfoData = getData(results[1]);
      final networkData = getData(results[2]) as Map<String, dynamic>?;
      final interfaceDump = getData(results[3]) as Map<String, dynamic>?;
      final dhcpLeases = getData(results[4]) as Map<String, dynamic>?;

      // Await optional wireless futures in parallel (won't throw — wired-only routers are fine)
      final optionalResults = await Future.wait([
        wirelessFuture,
        uciWirelessFuture,
      ]);
      final wirelessRaw = optionalResults[0];
      final uciWirelessRaw = optionalResults[1];

      Map<String, dynamic>? wirelessData;
      if (wirelessRaw != null) {
        final parsedWireless = getOptionalData(
          wirelessRaw,
          'luci-rpc.getWirelessDevices',
        );
        if (parsedWireless is Map<String, dynamic>) {
          wirelessData = parsedWireless;
        }
      }

      dynamic uciWirelessConfig;
      if (uciWirelessRaw != null) {
        uciWirelessConfig = getOptionalData(uciWirelessRaw, 'uci.get wireless');
      }

      // Fetch WireGuard peer information for WireGuard interfaces
      final wireguardData = <String, dynamic>{};
      if (interfaceDump != null && interfaceDump['interface'] is List) {
        // Check if there are any WireGuard interfaces
        final hasWireGuardInterfaces = interfaceDump['interface'].any((
          interface,
        ) {
          if (interface is Map<String, dynamic>) {
            final proto = interface['proto'] as String?;
            return proto == 'wireguard';
          }
          return false;
        });

        if (hasWireGuardInterfaces) {
          // This is the last target-sensitive RPC of the fetch; a session
          // switch must not send newer credentials to the previous router.
          if (token != _sessionToken) return;
          // Fetch all WireGuard data at once
          final allWireGuardData = await _apiService!.fetchWireGuardPeers(
            ipAddress: ip,
            sysauth: sysauth,
            useHttps: useHttps,
            interface: '', // Empty string to get all interfaces
          );
          if (token != _sessionToken) return;

          if (allWireGuardData != null) {
            // The new endpoint returns data for all interfaces
            // We need to extract data for each WireGuard interface
            for (final interface in interfaceDump['interface']) {
              if (interface is Map<String, dynamic>) {
                final ifname = interface['interface'] as String?;
                final proto = interface['proto'] as String?;
                if (proto == 'wireguard' && ifname != null) {
                  // Look for this interface in the WireGuard data
                  final interfaceData = allWireGuardData[ifname];

                  if (interfaceData != null) {
                    wireguardData[ifname] = interfaceData;
                  }
                }
              }
            }
          }
        }
      }

      // Throughput calculation - collect ALL interface devices
      final wanDeviceNames = <String>{};
      if (interfaceDump != null && interfaceDump['interface'] is List) {
        for (final interface in interfaceDump['interface']) {
          if (interface is Map<String, dynamic>) {
            final ifname = interface['interface'] as String?;
            // Skip only loopback interface
            if (ifname != null && ifname != 'loopback' && ifname != 'lo') {
              final device = interface['device'] as String?;
              final l3Device = interface['l3_device'] as String?;
              if (device != null) {
                wanDeviceNames.add(device);
              }
              if (l3Device != null && l3Device != device) {
                wanDeviceNames.add(l3Device);
              }
            }
          }
        }
      }

      // Update throughput data using the service
      // Check if we should track specific interface
      final prefs = _dashboardPreferences;
      String? specificInterface;
      if (!prefs.showAllThroughput &&
          prefs.primaryThroughputInterface != null) {
        // Map interface name to actual device name
        specificInterface = _getDeviceNameForInterface(
          prefs.primaryThroughputInterface!,
        );
      }
      // A newer session started while this fetch was in flight - drop the
      // stale results instead of clobbering the current router's data.
      if (token != _sessionToken) return;

      _throughputService?.updateThroughput(
        networkData,
        wanDeviceNames,
        specificInterface: specificInterface,
      );

      GlInetData? glInetData;
      final routerModel = boardInfoData?['model']?.toString() ?? '';
      if (routerModel.contains('GL-') || routerModel.contains('GL.iNet')) {
        if (token != _sessionToken) return;
        try {
          glInetData = await _glInetService?.fetchData(
            ip,
            routerPassword,
            useHttps,
          );
          final cpuCores = _getGlInetCoreCount(routerModel);
          if (cpuCores != null) {
            glInetData = glInetData?.withCpuCores(cpuCores);
          }
        } catch (error) {
          Logger.warning('GL.iNet supplementary fetch failed: $error');
        }
      }

      if (token != _sessionToken) return;

      _dashboardData = {
        'boardInfo': boardInfoData,
        'sysInfo': sysInfoData,
        'networkDevices': networkData,
        'interfaceDump': interfaceDump,
        'wireless': wirelessData ?? <String, dynamic>{},
        'dhcpLeases': dhcpLeases,
        'wan': _extractWanData(interfaceDump),
        'uciWirelessConfig': uciWirelessConfig,
        'wireguard': wireguardData,
        'glinet': ?glInetData,
        '_lastUpdated':
            DateTime.now().millisecondsSinceEpoch, // Force UI updates
      };

      // Hybrid approach: update lastKnownHostname for the selected router
      final boardInfo = _dashboardData?['boardInfo'] as Map<String, dynamic>?;
      final hostname = boardInfo?['hostname']?.toString();
      if (hostname != null && hostname.isNotEmpty) {
        await _routerService?.updateSelectedRouterHostname(hostname);
      }

      // Ensure throughput timer is running
      _startThroughputTimer();

      // Schedule an immediate throughput update to get initial data faster
      Future.delayed(const Duration(milliseconds: 100), () {
        _updateThroughputOnly();
      });
    } catch (e) {
      // A newer session started; don't surface this fetch's error.
      if (token != _sessionToken) return;
      final status = e is DioException ? e.response?.statusCode : null;
      final retryable =
          e is DioException &&
          (status == 401 ||
              status == 403 ||
              e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout);
      final router = _routerService?.selectedRouter;
      if (retryable &&
          !isRetryAfterFallback &&
          router != null &&
          router.hasFallback &&
          _authService != null) {
        final result = await _serializeAuthOp<FallbackLoginResult>(
          () => _authService!.loginWithFallback(
            activeAddress: router.activeAddress,
            activeHttps: router.activeUseHttps,
            activeIndex: router.activeAddressIndex,
            fallbackAddress: router.inactiveAddress,
            fallbackHttps: router.inactiveUseHttps,
            username: router.username,
            password: router.password,
          ),
        );
        if (token != _sessionToken) return;
        if (result.success) {
          if (result.usedAddressIndex != router.activeAddressIndex) {
            await updateRouter(
              router.copyWith(activeAddressIndex: result.usedAddressIndex),
            );
          }
          _isDashboardLoading = false;
          return await fetchDashboardData(isRetryAfterFallback: true);
        }
      }
      _dashboardError = userFacingApiError(e);
    } finally {
      // A newer session (router switch / re-login / logout) started while this
      // fetch was in flight - drop the stale results instead of clobbering it.
      if (token == _sessionToken) {
        _isDashboardLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _refreshRebootAccess({
    required String ip,
    required String sysauth,
    required bool useHttps,
    required int token,
    required int requestId,
  }) async {
    bool? allowed;
    String? error;
    try {
      final result = await _apiService!.call(
        ip,
        sysauth,
        useHttps,
        object: 'session',
        method: 'access',
        params: {'scope': 'ubus', 'object': 'system', 'function': 'reboot'},
      );
      allowed = rpcAccessAllowed(result);
      if (allowed == null) {
        error = 'Could not check administrator access. Refresh to retry.';
      }
    } catch (e) {
      Logger.warning('Could not check reboot access: $e');
      error = 'Could not check administrator access. Refresh to retry.';
    }
    if (token != _sessionToken || requestId != _rebootAccessRequestId) return;
    _canReboot = allowed;
    _rebootAccessError = error;
    notifyListeners();
  }

  Map<String, dynamic> _processDhcpLeases(Map<String, dynamic> rawDhcpData) {
    final stdout = rawDhcpData['stdout'] as String? ?? '';
    final leases = <Map<String, dynamic>>[];

    for (final line in stdout.split('\n')) {
      if (line.trim().isEmpty) continue;

      final parts = line.trim().split(' ');
      if (parts.length >= 5) {
        // Format: timestamp mac_address ip_address hostname client_id
        final timestamp = int.tryParse(parts[0]) ?? 0;
        final macAddress = parts[1];
        final ipAddress = parts[2];
        final hostname = parts[3];

        leases.add({
          'expires': timestamp,
          'macaddr': macAddress,
          'ipaddr': ipAddress,
          'hostname': hostname,
          'activetime': 0, // Default for mock data
          'leasetime': timestamp,
        });
      }
    }

    return {'dhcp_leases': leases};
  }

  Map<String, dynamic>? _extractWanData(Map<String, dynamic>? interfaceDump) {
    if (interfaceDump == null || interfaceDump['interface'] == null) {
      return null;
    }
    try {
      for (var interface in interfaceDump['interface']) {
        if (interface['route'] is List) {
          for (var route in interface['route']) {
            if (route is Map &&
                route['target'] == '0.0.0.0' &&
                route['mask'] == 0) {
              return interface;
            }
          }
        }
      }
    } catch (e) {
      // print('WAN data extraction error: $e');
      return null;
    }
    return null;
  }

  String? _getDeviceNameForInterface(String interfaceName) {
    // Handle wireless format: "SSID (deviceName)"
    if (interfaceName.contains('(')) {
      final match = RegExp(r'\(([^)]+)\)').firstMatch(interfaceName);
      return match?.group(1);
    }

    // Map interface names to their actual device names from interface dump
    final interfaceDump =
        _dashboardData?['interfaceDump'] as Map<String, dynamic>?;
    if (interfaceDump != null && interfaceDump['interface'] is List) {
      for (final interface in interfaceDump['interface']) {
        if (interface is Map<String, dynamic>) {
          final ifname = interface['interface'] as String?;
          if (ifname == interfaceName) {
            // Return the device or l3_device field
            return (interface['device'] ?? interface['l3_device']) as String?;
          }
        }
      }
    }

    // If not found in interface dump, check if it's already a device name
    // (e.g., eth0, br-lan, wlan0)
    return interfaceName;
  }

  void _startThroughputTimer() {
    _throughputTimer?.cancel();
    // Don't start timer if we're rebooting
    if (_isRebooting) {
      return;
    }
    _throughputTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _updateThroughputOnly();
    });
  }

  /// Updates only throughput data without refetching the entire dashboard
  Future<void> _updateThroughputOnly() async {
    // Don't try to update throughput during reboot
    if (_isRebooting) {
      return;
    }

    // Skip this tick if the previous poll is still outstanding - on slow
    // links requests would otherwise pile up concurrently.
    if (_throughputUpdateInFlight) {
      return;
    }
    _throughputUpdateInFlight = true;
    final token = _sessionToken;
    try {
      await _updateThroughputInternal(token);
    } finally {
      _throughputUpdateInFlight = false;
    }
  }

  Future<void> _updateThroughputInternal(int token) async {
    if (_reviewerModeEnabled) {
      // For reviewer mode, get network devices data only
      try {
        final result = await _apiService!.callSimple('network', 'device', {});
        final networkData = result[1] as Map<String, dynamic>?;
        final wanDeviceNames = {'eth0'}; // Mock WAN device

        // Check if we should track specific interface
        final prefs = _dashboardPreferences;
        String? specificInterface;
        if (!prefs.showAllThroughput &&
            prefs.primaryThroughputInterface != null) {
          // Extract device name from interface ID (format: "SSID (deviceName)" or just "deviceName")
          final interfaceId = prefs.primaryThroughputInterface!;
          if (interfaceId.contains('(')) {
            // Wireless format: "SSID (deviceName)"
            final match = RegExp(r'\(([^)]+)\)').firstMatch(interfaceId);
            specificInterface = match?.group(1);
          } else {
            // Wired format: just device name
            specificInterface = interfaceId;
          }
        }

        // Drop stale results before they can touch rate history.
        if (token != _sessionToken) return;
        _throughputService?.updateThroughput(
          networkData,
          wanDeviceNames,
          specificInterface: specificInterface,
        );
        notifyListeners();
      } catch (e) {
        // Throughput updates are non-critical, but log so persistent
        // failures (e.g. expired session) are visible when debugging.
        Logger.debug('Reviewer throughput update failed: $e');
      }
      return;
    }

    if (_routerService?.selectedRouter == null ||
        _authService?.sysauth == null) {
      return;
    }

    // Use the address that actually succeeded during login
    final ip =
        _authService!.ipAddress ?? _routerService!.selectedRouter!.ipAddress;
    final useHttps = _authService!.useHttps;

    try {
      // Only fetch network devices for throughput calculation
      final result = await _apiService!.call(
        ip,
        _authService!.sysauth!,
        useHttps,
        object: 'luci-rpc',
        method: 'getNetworkDevices',
        params: {},
      );

      if (result is List && result.length > 1 && result[0] == 0) {
        final networkData = result[1] as Map<String, dynamic>?;

        // Get ALL device names from cached dashboard data (except loopback)
        final wanDeviceNames = <String>{};
        final interfaceDump =
            _dashboardData?['interfaceDump'] as Map<String, dynamic>?;
        if (interfaceDump != null && interfaceDump['interface'] is List) {
          for (final interface in interfaceDump['interface']) {
            if (interface is Map<String, dynamic>) {
              final ifname = interface['interface'] as String?;
              final device = interface['device'] as String?;
              final l3Device = interface['l3_device'] as String?;
              // Include all interfaces except loopback
              if (ifname != null && ifname != 'loopback' && ifname != 'lo') {
                if (device != null) wanDeviceNames.add(device);
                if (l3Device != null && l3Device != device) {
                  wanDeviceNames.add(l3Device);
                }
              }
            }
          }
        }

        // Check if we should track specific interface
        final prefs = _dashboardPreferences;
        String? specificInterface;
        if (!prefs.showAllThroughput &&
            prefs.primaryThroughputInterface != null) {
          // Extract device name from interface ID (format: "SSID (deviceName)" or just "deviceName")
          final interfaceId = prefs.primaryThroughputInterface!;
          if (interfaceId.contains('(')) {
            // Wireless format: "SSID (deviceName)"
            final match = RegExp(r'\(([^)]+)\)').firstMatch(interfaceId);
            specificInterface = match?.group(1);
          } else {
            // Wired format: just device name
            specificInterface = interfaceId;
          }
        }

        // Drop stale results before they can touch rate history.
        if (token != _sessionToken) return;
        _throughputService?.updateThroughput(
          networkData,
          wanDeviceNames,
          specificInterface: specificInterface,
        );
        notifyListeners();
      }
    } catch (e) {
      // Throughput updates are non-critical, but log so persistent failures
      // (e.g. expired session) are visible when debugging.
      Logger.debug('Throughput update failed: $e');
    }
  }

  void _cancelThroughputTimer() {
    _throughputTimer?.cancel();
    _throughputService?.clear();
  }

  Future<bool> reboot({BuildContext? context}) async {
    if (!_reviewerModeEnabled && _canReboot != true) return false;
    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    // Cancel throughput timer before starting reboot to prevent "client closed" errors
    _cancelThroughputTimer();
    // Start a fresh recovery cycle (drops any pending one)
    _cancelRebootPolling();
    // The router is going down: invalidate in-flight dashboard/throughput
    // continuations so their results cannot land after the service cleared.
    _sessionToken++;

    // Snapshot the identity of THIS recovery attempt: session, generation,
    // and target. An overlapping older reboot() call must not mutate this
    // cycle's state when its RPC resolves later.
    final token = _sessionToken;
    final cycle = _rebootCycleId;
    final targetIp = _authService!.ipAddress!;
    final targetUseHttps = _authService!.useHttps;

    _isRebooting = true;
    notifyListeners();

    try {
      final result = await _apiService!.reboot(
        targetIp,
        _authService!.sysauth!,
        targetUseHttps,
        context: context,
      );
      // A newer recovery cycle took over (second reboot) or the session
      // changed while this RPC was in flight - leave state alone.
      if (cycle != _rebootCycleId || token != _sessionToken) {
        return false;
      }
      if (!result) {
        // The RPC reported failure - don't leave the UI stuck in the
        // rebooting state polling for a router that never restarted.
        _isRebooting = false;
        // The timer was cancelled before the RPC; the router never went
        // down, so resume throughput polling.
        _startThroughputTimer();
        notifyListeners();
        return false;
      }
      // Store the captured target so polling keeps pinging the rebooted
      // router even if the user switches routers or logs out meanwhile.
      _rebootTargetIp = targetIp;
      _rebootTargetUseHttps = targetUseHttps;
      // Wait 30 seconds before starting to poll for router availability
      // Some routers take longer to reboot
      _rebootDelayTimer?.cancel();
      _rebootDelayTimer = Timer(const Duration(seconds: 30), () {
        _pollRouterAvailability();
      });
      return result;
    } catch (e) {
      if (cycle == _rebootCycleId && token == _sessionToken) {
        _isRebooting = false;
        // The router never went down; resume throughput polling.
        _startThroughputTimer();
        notifyListeners();
      }
      return false;
    }
  }

  /// Cancels any pending reboot polling (delay timer + poll timer).
  ///
  /// Bumps the recovery generation so a probe that is already awaiting
  /// `_pingRouter()` is discarded instead of acting on newer state.
  void _cancelRebootPolling() {
    _rebootCycleId++;
    _rebootDelayTimer?.cancel();
    _rebootDelayTimer = null;
    _pollingTimer?.cancel();
    _pollingTimer = null;
    _pollAttempts = 0;
  }

  void _pollRouterAvailability() {
    // Reset poll attempts
    _pollAttempts = 0;
    _pollingTimer?.cancel();

    // Start polling with exponential backoff
    _scheduleNextPoll();
  }

  void _scheduleNextPoll() {
    if (_pollAttempts >= _maxPollAttempts) {
      // Max attempts reached, stop polling
      _isRebooting = false;
      notifyListeners();
      // print('[Reboot] Timeout: Router did not come back online after $_maxPollAttempts attempts');

      // Show a user-friendly message
      if (onRouterBackOnline != null) {
        // Reuse the callback to show timeout message
        onRouterBackOnline!();
      }
      return;
    }

    // Calculate delay with exponential backoff: 3s, 3s, 5s, 8s, 12s, 18s, then 20s intervals
    int delaySeconds;
    if (_pollAttempts < 2) {
      delaySeconds = 3;
    } else if (_pollAttempts < 4) {
      delaySeconds = 5;
    } else if (_pollAttempts < 6) {
      delaySeconds = 8;
    } else if (_pollAttempts < 8) {
      delaySeconds = 12;
    } else if (_pollAttempts < 10) {
      delaySeconds = 18;
    } else {
      delaySeconds = 20; // Cap at 20 seconds for remaining attempts
    }

    _pollingTimer = Timer(Duration(seconds: delaySeconds), () async {
      _pollAttempts++;
      // Snapshot everything the continuation validates against: the session
      // this recovery belongs to, its generation, and the reboot target it
      // is probing.
      final token = _sessionToken;
      final cycle = _rebootCycleId;
      final targetIp = _rebootTargetIp;
      final available = await _pingRouter();

      // Cancelling the timer does not abort an in-flight probe. Discard the
      // result when the session changed, the recovery was superseded or
      // cancelled (generation mismatch), or the target moved - otherwise
      // recovery could fire callbacks or re-login based on another router's
      // answer or an older cycle's probe.
      if (token != _sessionToken ||
          cycle != _rebootCycleId ||
          !_isRebooting ||
          _rebootTargetIp != targetIp) {
        return;
      }

      if (available) {
        // Router is back online
        _pollingTimer?.cancel();
        _pollingTimer = null;
        _isRebooting = false;
        _pollAttempts = 0;
        notifyListeners();

        // Notify UI that router is back online
        if (onRouterBackOnline != null) {
          onRouterBackOnline!();
        }

        // Force relogin using active address (may have changed via fallback)
        final reloginRouter = _routerService?.selectedRouter;
        if (reloginRouter != null) {
          await login(
            reloginRouter.activeAddress,
            reloginRouter.username,
            reloginRouter.password,
            reloginRouter.activeUseHttps,
            fromRouter: true,
            alternateAddress: reloginRouter.inactiveAddress,
            alternateUseHttps: reloginRouter.inactiveUseHttps,
            activeAddressIndex: reloginRouter.activeAddressIndex,
          );
        }
      } else {
        // Schedule next poll
        _scheduleNextPoll();
      }
    });
  }

  Future<bool> _pingRouter() async {
    final targetIp = _rebootTargetIp ?? _authService?.ipAddress;
    if (targetIp == null) return false;
    final targetUseHttps = _rebootTargetUseHttps;

    // Clear cached HTTP clients for this host to avoid stale connections.
    // The poll counter is incremented before each attempt, so the first
    // probe sees 1.
    if (_pollAttempts <= 1) {
      _httpClientManager.disposeClient(targetIp, targetUseHttps);
    }

    // Try multiple endpoints in order
    final scheme = targetUseHttps ? 'https' : 'http';
    final endpoints = [
      '/', // Root
      '/cgi-bin/luci/', // LuCI login page
      '/cgi-bin/luci/admin', // Admin page
    ];

    for (final endpoint in endpoints) {
      // Create a fresh Dio client for pinging to avoid certificate/connection
      // issues; declared outside try so finally can always close it.
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
          followRedirects: false,
          validateStatus: (code) => code != null && code >= 200 && code < 500,
        ),
      );
      try {
        // Build the URI structurally: string interpolation produces an
        // invalid authority for IPv6 literals (missing brackets), while
        // Uri host handling adds them automatically. Persisted addresses
        // may hold unbracketed IPv6 literals (2+ colons) - bracket them
        // first or the authority parse throws and every probe fails.
        var authorityInput = targetIp;
        if (!authorityInput.startsWith('[') &&
            ':'.allMatches(authorityInput).length > 1) {
          authorityInput = '[$authorityInput]';
        }
        final authority = Uri.parse('//$authorityInput');
        final uri = Uri(
          scheme: scheme,
          host: authority.host,
          port: authority.hasPort ? authority.port : null,
          path: endpoint,
        );

        if (targetUseHttps) {
          final adapter = IOHttpClientAdapter();
          adapter.createHttpClient = () {
            final httpClient = HttpClient();
            httpClient.connectionTimeout = const Duration(seconds: 5);
            // Liveness probe only - no credentials are sent, but still prefer
            // an already-pinned certificate when we have one.
            httpClient.badCertificateCallback = (cert, host, port) {
              return HttpClientManager().isCertificatePinned(host, port, cert);
            };
            return httpClient;
          };
          dio.httpClientAdapter = adapter;
        }

        // print('[Ping] Attempt $_pollAttempts: Checking $url');
        final response = await dio.getUri(uri);
        // print('[Ping] Response from $endpoint: ${response.statusCode}');

        // Accept various status codes as "alive"
        final isAlive =
            response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 500;

        if (isAlive) {
          if (_pollAttempts > 5) {
            // If we've been polling for a while and get a response,
            // wait a bit more to ensure services are fully started
            await Future.delayed(const Duration(seconds: 5));
          }
          return true;
        }
      } catch (e) {
        // Try next endpoint
        if (endpoint == endpoints.last) {
          // print('[Ping] All endpoints failed on attempt $_pollAttempts');
          // print('[Ping] Last error: ${e.toString()}');

          if (e is SocketException) {
            // print('[Ping] Socket error: ${e.message}, OS Error: ${e.osError}');
          } else if (e is HandshakeException) {
            // print('[Ping] SSL handshake error - router may still be starting');
          }
        }
      } finally {
        // Each attempt uses its own throwaway client; close it so repeated
        // polls don't retain adapters and sockets until process shutdown.
        dio.close(force: true);
      }
    }

    return false;
  }

  Future<bool> checkRouterAvailability() async {
    if (_reviewerModeEnabled || _authService?.ipAddress == null) {
      return _reviewerModeEnabled;
    }
    return await _authService!.checkRouterAvailability(
      _authService!.ipAddress!,
      _authService!.useHttps,
    );
  }

  /// Unwraps a LuCI `uci.get` RPC response into a flat section map.
  ///
  /// Real API shape: `[0, {"values": {"section": {...}, ...}}]`
  /// Mock shape:     `[0, {"<configName>": {"section": {...}, ...}}]`
  /// Some implementations return sections directly under `result[1]`.
  ///
  /// Returns `null` when the response cannot be parsed.
  Map<String, dynamic>? _resolveUciSections(dynamic result, String configName) {
    if (result is! List || result.length < 2) return null;
    final outer = result[1];
    if (outer is! Map) return null;
    // Real API: sections under 'values'
    if (outer['values'] is Map) {
      return Map<String, dynamic>.from(outer['values'] as Map);
    }
    // Mock: sections under the config name key (e.g. 'wireless', 'firewall')
    if (outer[configName] is Map) {
      return Map<String, dynamic>.from(outer[configName] as Map);
    }
    // Flat map — sections directly at result[1]
    return Map<String, dynamic>.from(outer);
  }

  bool _isUciDisabled(dynamic value) => value is List
      ? value.any(_isUciDisabled)
      : value == true || value?.toString() == '1';

  /// Restarts a specific radio via UCI disable/enable cycle.
  /// This is more reliable than `wifi reload` which doesn't work on all routers.
  /// Throws if the re-enable step fails (leaving the radio disabled is worse
  /// than surfacing the error to the caller).
  Future<void> _restartRadioViaUci(
    String radioName, {
    BuildContext? context,
    int delaySeconds = 5,
  }) async {
    final ip = _authService!.ipAddress!;
    final auth = _authService!.sysauth!;
    final https = _authService!.useHttps;
    var disableStaged = false;
    try {
      await _apiService!.uciSet(
        ip,
        auth,
        https,
        config: 'wireless',
        section: radioName,
        values: {'disabled': '1'},
        context: context,
      );
      disableStaged = true;
      await _apiService!.uciCommit(
        ip,
        auth,
        https,
        config: 'wireless',
        context: context?.mounted == true ? context : null,
      );
      await _apiService!.systemExec(
        ip,
        auth,
        https,
        command: '/sbin/wifi',
        params: ['down', radioName],
        context: context?.mounted == true ? context : null,
      );
      await Future.delayed(Duration(seconds: delaySeconds));

      await _apiService!.uciSet(
        ip,
        auth,
        https,
        config: 'wireless',
        section: radioName,
        values: {'disabled': '0'},
        context: context?.mounted == true ? context : null,
      );
      await _apiService!.uciCommit(
        ip,
        auth,
        https,
        config: 'wireless',
        context: context?.mounted == true ? context : null,
      );
      await _apiService!.systemExec(
        ip,
        auth,
        https,
        command: '/sbin/wifi',
        params: ['up', radioName],
        context: context?.mounted == true ? context : null,
      );
      disableStaged = false;

      await Future.delayed(Duration(seconds: delaySeconds));
      try {
        await fetchDashboardData();
      } catch (_) {}
    } catch (error, stack) {
      Object? restoreError;
      if (disableStaged) {
        try {
          await _apiService!.uciSet(
            ip,
            auth,
            https,
            config: 'wireless',
            section: radioName,
            values: {'disabled': '0'},
            context: context?.mounted == true ? context : null,
          );
          await _apiService!.uciCommit(
            ip,
            auth,
            https,
            config: 'wireless',
            context: context?.mounted == true ? context : null,
          );
          await _apiService!.systemExec(
            ip,
            auth,
            https,
            command: '/sbin/wifi',
            params: ['up', radioName],
            context: context?.mounted == true ? context : null,
          );
        } catch (e, restoreStack) {
          restoreError = e;
          Logger.exception(
            'Failed to restore radio $radioName after restart failure',
            e,
            restoreStack,
          );
        }
      }
      if (restoreError != null) {
        Error.throwWithStackTrace(
          Exception('$error; radio restore also failed: $restoreError'),
          stack,
        );
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  /// Helper: restarts all known radios via UCI disable/enable cycle.
  /// Used after operations that need wifi to reload (toggle, modify, delete).
  /// Propagates restart failures so callers cannot report stale runtime state.
  Future<void> _wifiReload({BuildContext? context}) async {
    final result = await _apiService!.uciGetAll(
      _authService!.ipAddress!,
      _authService!.sysauth!,
      _authService!.useHttps,
      config: 'wireless',
      context: context,
    );
    final sections = _resolveUciSections(result, 'wireless');
    if (sections == null) {
      throw const FormatException('Invalid wireless configuration response');
    }
    final radios = sections.entries
        .where(
          (entry) =>
              entry.value is Map &&
              entry.value['.type']?.toString() == 'wifi-device' &&
              !_isUciDisabled(entry.value['disabled']),
        )
        .map((entry) => entry.key)
        .toList();

    if (radios.isEmpty) {
      Logger.info('_wifiReload: no enabled radios to restart');
      try {
        await fetchDashboardData();
      } catch (_) {}
      return;
    }

    // Cycle only enabled radios; disabled radios must remain disabled.
    for (final radio in radios) {
      await _restartRadioViaUci(
        radio,
        context: context?.mounted == true ? context : null,
        delaySeconds: 3,
      );
    }
  }

  Future<bool> setWirelessRadioState(
    String device,
    bool enabled, {
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) {
      // Simulate operation for reviewer mode
      await Future.delayed(const Duration(milliseconds: 500));
      await fetchDashboardData();
      return true;
    }

    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    try {
      // 1. Set the disabled state
      await _apiService!.uciSet(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        section: device,
        values: {'disabled': enabled ? '0' : '1'},
        context: context,
      );

      // 2. Commit the changes
      await _apiService!.uciCommit(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        context: context?.mounted == true ? context : null,
      );

      // 3. Reload wifi to apply changes
      await _apiService!.systemExec(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        command: '/sbin/wifi',
        params: ['reload'],
        context: context?.mounted == true ? context : null,
      );

      // Refresh dashboard data to reflect the change
      await fetchDashboardData();

      return true;
    } catch (e) {
      _dashboardError = 'Failed to toggle Wi-Fi: $e';
      notifyListeners();
      return false;
    }
  }

  /// Cancel any ongoing wireless network scan.
  void cancelWirelessScan() {
    _apiService?.cancelScan();
  }

  /// Scans for nearby wireless networks on a given radio interface.
  /// [device] is the wireless device name (e.g., 'wlan0', 'phy0-ap0').
  Future<List<WifiScanResult>> scanWirelessNetworks({
    required String device,
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) {
      // Use mock scan results in reviewer mode
      final mockResults = await _apiService!.scanWirelessNetworks(
        ipAddress: 'mock',
        sysauth: 'mock',
        useHttps: false,
        device: device,
        context: context,
      );
      return mockResults.map((r) => WifiScanResult.fromJson(r)).toList()
        ..sort((a, b) => b.signal.compareTo(a.signal));
    }

    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      throw Exception('Not authenticated');
    }

    try {
      final results = await _apiService!.scanWirelessNetworks(
        ipAddress: _authService!.ipAddress!,
        sysauth: _authService!.sysauth!,
        useHttps: _authService!.useHttps,
        device: device,
        context: context,
      );

      if (results.isEmpty) {
        // Try with phy name (strip -ap0, -sta0 suffix) as fallback
        final phyMatch = RegExp(r'^(phy\d+)-').firstMatch(device);
        if (phyMatch != null) {
          final phyName = phyMatch.group(1)!;
          Logger.info('Scan returned empty on $device, retrying with $phyName');
          final retryResults = await _apiService!.scanWirelessNetworks(
            ipAddress: _authService!.ipAddress!,
            sysauth: _authService!.sysauth!,
            useHttps: _authService!.useHttps,
            device: phyName,
            context: context?.mounted == true ? context : null,
          );
          if (retryResults.isNotEmpty) {
            return retryResults.map((r) => WifiScanResult.fromJson(r)).toList()
              ..sort((a, b) => b.signal.compareTo(a.signal));
          }
        }
      }

      final scanResults =
          results.map((r) => WifiScanResult.fromJson(r)).toList()
            ..sort((a, b) => b.signal.compareTo(a.signal));
      return scanResults;
    } catch (e, stack) {
      Logger.exception('Failed to scan wireless networks', e, stack);
      rethrow; // Let the UI show the actual error
    }
  }

  /// Returns a list of available wireless radio devices (e.g., wlan0, wlan1)
  /// from the current dashboard data.
  List<Map<String, String>> getAvailableRadioDevices() {
    final wirelessData =
        _dashboardData?['wireless'] as Map<String, dynamic>? ?? {};
    final devices = <Map<String, String>>[];

    wirelessData.forEach((radioName, radioData) {
      if (radioData is Map<String, dynamic>) {
        final interfaces = radioData['interfaces'] as List<dynamic>?;

        // Determine band from frequency/channel.
        // Only accept frequencies within known Wi-Fi ranges (MHz);
        // out-of-range values fall through to channel-based classification.
        final freq = radioData['frequency'];
        final channel = radioData['channel'];
        String band = '';
        if (freq is int) {
          // Valid Wi-Fi ranges: 2.4 GHz (2400–2500), 4.9 GHz (4900–5000),
          // 5 GHz (5000–5925), 6 GHz (5925–7125).
          final isValidFreq =
              (freq >= 2400 && freq <= 2500) || (freq >= 4900 && freq <= 7125);
          if (isValidFreq) {
            band = freq >= 5925
                ? '6 GHz'
                : freq >= 5000
                ? '5 GHz'
                : freq >= 4900
                ? '4.9 GHz'
                : '2.4 GHz';
          }
        }
        if (band.isEmpty && channel is int) {
          // Frequency-based is preferred; channel fallback can't distinguish 6 GHz
          band = channel >= 36 ? '5 GHz' : '2.4 GHz';
        }

        if (interfaces != null && interfaces.isNotEmpty) {
          // Find the best interface for scanning:
          // Prefer an AP interface, fall back to any active interface
          String? bestIfname;
          String bestSsid = radioName;
          for (final iface in interfaces) {
            final ifname = iface['ifname'] as String?;
            if (ifname == null) continue;
            final config = iface['config'] as Map<String, dynamic>? ?? {};
            final iwinfo = iface['iwinfo'] as Map<String, dynamic>? ?? {};
            final mode = config['mode']?.toString() ?? '';
            final ssid = (iwinfo['ssid'] ?? config['ssid'] ?? '').toString();

            if (bestIfname == null || mode == 'ap') {
              bestIfname = ifname;
              if (ssid.isNotEmpty) bestSsid = ssid;
            }
            // If we found an AP interface, stop looking
            if (mode == 'ap') break;
          }

          devices.add({
            'ifname': bestIfname ?? radioName,
            'radioName': radioName,
            'ssid': bestSsid,
            'band': band,
          });
        } else {
          // Radio exists but has no interfaces - still usable for scanning
          devices.add({
            'ifname': radioName,
            'radioName': radioName,
            'ssid': radioName,
            'band': band,
          });
        }
      }
    });
    return devices;
  }

  /// Restarts a wireless radio via UCI disable/enable cycle.
  Future<bool> restartWirelessRadio(
    String radioName, {
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) {
      await Future.delayed(const Duration(seconds: 2));
      await fetchDashboardData();
      return true;
    }

    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    try {
      final result = await _apiService!.uciGetAll(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        context: context,
      );
      final sections = _resolveUciSections(result, 'wireless');
      final radio = sections?[radioName];
      if (radio is! Map) {
        throw FormatException('Radio $radioName not found');
      }
      if (_isUciDisabled(radio['disabled'])) {
        _dashboardError = 'Enable $radioName before restarting it';
        notifyListeners();
        return false;
      }
      Logger.info('Restarting radio $radioName via UCI cycle');
      await _restartRadioViaUci(
        radioName,
        context: context?.mounted == true ? context : null,
      );
      return true;
    } catch (e, stack) {
      Logger.exception('Failed to restart radio $radioName', e, stack);
      _dashboardError = 'Failed to restart radio: $e';
      notifyListeners();
      return false;
    }
  }

  /// Connects to a wireless network by creating a new wifi-iface in station mode.
  ///
  /// [radioDevice] is the radio to use (e.g., 'radio0').
  /// [ssid] is the network SSID to connect to.
  /// [encryption] is the OpenWrt encryption type (e.g., 'psk2', 'sae', 'none').
  /// [password] is the network password (empty for open networks).
  Future<bool> connectToWirelessNetwork({
    required String radioDevice,
    required String ssid,
    required String encryption,
    String password = '',
    String? bssid,
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) {
      await Future.delayed(const Duration(seconds: 2));
      await fetchDashboardData();
      return true;
    }

    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    try {
      final ip = _authService!.ipAddress!;
      final auth = _authService!.sysauth!;
      final https = _authService!.useHttps;

      // Use radio-specific network name to avoid conflicts between radios
      // radio0 -> wwan, radio1 -> wwan1, radio2 -> wwan2, etc
      final radioIndex = int.tryParse(radioDevice.replaceAll('radio', '')) ?? 0;
      final staNetworkName = radioIndex == 0 ? 'wwan' : 'wwan$radioIndex';

      final wirelessResult = await _apiService!.uciGetAll(
        ip,
        auth,
        https,
        config: 'wireless',
        context: context,
      );
      final wirelessSections = _resolveUciSections(wirelessResult, 'wireless');
      if (wirelessSections == null) {
        throw const FormatException('Invalid wireless configuration response');
      }
      final radio = wirelessSections[radioDevice];
      if (radio is! Map) {
        throw FormatException('Radio $radioDevice not found');
      }
      if (_isUciDisabled(radio['disabled'])) {
        _dashboardError = 'Enable $radioDevice before connecting';
        notifyListeners();
        return false;
      }

      String? existingStaSection;
      Map? existingStaConfig;
      var maxWifinetIndex = -1;
      for (final entry in wirelessSections.entries) {
        final section = entry.value;
        if (entry.key.startsWith('wifinet')) {
          final index = int.tryParse(entry.key.substring('wifinet'.length));
          if (index != null && index > maxWifinetIndex) {
            maxWifinetIndex = index;
          }
        }
        if (section is Map &&
            section['device']?.toString() == radioDevice &&
            section['mode']?.toString() == 'sta') {
          existingStaSection = entry.key;
          existingStaConfig = section;
        }
      }
      final sectionName = existingStaSection ?? 'wifinet${maxWifinetIndex + 1}';

      var createdNetwork = false;
      var addedToWan = false;
      var wanZoneIndex = -1;
      var createdStation = false;
      var updatedStation = false;
      var restartAttempted = false;
      try {
        // Persist the dependency first. A wireless station is never staged or
        // restarted unless its DHCP interface has committed successfully.
        final networkResult = await _apiService!.uciGetAll(
          ip,
          auth,
          https,
          config: 'network',
          context: context?.mounted == true ? context : null,
        );
        final networkSections = _resolveUciSections(networkResult, 'network');
        if (networkSections == null) {
          throw const FormatException('Invalid network configuration response');
        }
        if (!networkSections.containsKey(staNetworkName)) {
          await _apiService!.uciAdd(
            ip,
            auth,
            https,
            config: 'network',
            type: 'interface',
            name: staNetworkName,
            values: {'proto': 'dhcp'},
            context: context?.mounted == true ? context : null,
          );
          createdNetwork = true;
        }
        await _apiService!.uciCommit(
          ip,
          auth,
          https,
          config: 'network',
          context: context?.mounted == true ? context : null,
        );

        // WAN membership is optional when the firewall config is absent, but a
        // failed read must abort before wireless is staged.
        Map<String, dynamic>? firewallSections;
        try {
          final firewallResult = await _apiService!.uciGetAll(
            ip,
            auth,
            https,
            config: 'firewall',
            context: context?.mounted == true ? context : null,
          );
          firewallSections = _resolveUciSections(firewallResult, 'firewall');
        } on RpcException catch (e) {
          if (e.status != 4) rethrow;
          firewallSections = {};
        }
        if (firewallSections == null) {
          throw const FormatException(
            'Invalid firewall configuration response',
          );
        }
        var zoneIndex = 0;
        var foundInWan = false;
        for (final entry in firewallSections.entries) {
          final section = entry.value;
          if (section is! Map || section['.type']?.toString() != 'zone') {
            continue;
          }
          if (section['name']?.toString() == 'wan') {
            wanZoneIndex = zoneIndex;
            final networks = section['network'];
            foundInWan = networks is List
                ? networks
                      .map((value) => value.toString())
                      .contains(staNetworkName)
                : networks
                          ?.toString()
                          .split(RegExp(r'\s+'))
                          .contains(staNetworkName) ==
                      true;
            break;
          }
          zoneIndex++;
        }
        if (!foundInWan && wanZoneIndex >= 0) {
          await _apiService!.systemExec(
            ip,
            auth,
            https,
            command: '/sbin/uci',
            params: [
              'add_list',
              'firewall.@zone[$wanZoneIndex].network=$staNetworkName',
            ],
            context: context?.mounted == true ? context : null,
          );
          addedToWan = true;
          await _apiService!.uciCommit(
            ip,
            auth,
            https,
            config: 'firewall',
            context: context?.mounted == true ? context : null,
          );
        }

        if (existingStaSection != null) {
          await _apiService!.uciSet(
            ip,
            auth,
            https,
            config: 'wireless',
            section: sectionName,
            values: {
              'network': staNetworkName,
              'ssid': ssid,
              'encryption': encryption,
              if (password.isNotEmpty) 'key': password,
              if (bssid?.isNotEmpty == true) 'bssid': bssid!,
            },
            context: context?.mounted == true ? context : null,
          );
          updatedStation = true;
          if (password.isEmpty &&
              existingStaConfig?.containsKey('key') == true) {
            await _apiService!.uciDelete(
              ip,
              auth,
              https,
              config: 'wireless',
              section: sectionName,
              option: 'key',
              context: context?.mounted == true ? context : null,
            );
          }
          if (bssid?.isNotEmpty != true &&
              existingStaConfig?.containsKey('bssid') == true) {
            await _apiService!.uciDelete(
              ip,
              auth,
              https,
              config: 'wireless',
              section: sectionName,
              option: 'bssid',
              context: context?.mounted == true ? context : null,
            );
          }
        } else {
          await _apiService!.uciAdd(
            ip,
            auth,
            https,
            config: 'wireless',
            type: 'wifi-iface',
            name: sectionName,
            values: {
              'device': radioDevice,
              'network': staNetworkName,
              'mode': 'sta',
              'ssid': ssid,
              'encryption': encryption,
              if (password.isNotEmpty) 'key': password,
              if (bssid?.isNotEmpty == true) 'bssid': bssid!,
            },
            context: context?.mounted == true ? context : null,
          );
          createdStation = true;
        }
        await _apiService!.uciCommit(
          ip,
          auth,
          https,
          config: 'wireless',
          context: context?.mounted == true ? context : null,
        );

        restartAttempted = true;
        await _restartRadioViaUci(
          radioDevice,
          context: context?.mounted == true ? context : null,
        );
      } catch (error, stack) {
        final rollbackErrors = <String>[];
        var wirelessRolledBack = false;

        Future<void> attemptRollback(
          String label,
          Future<void> Function() action,
        ) async {
          try {
            await action();
          } catch (e, rollbackStack) {
            rollbackErrors.add('$label: $e');
            Logger.exception('Failed to roll back $label', e, rollbackStack);
          }
        }

        if (createdStation) {
          await attemptRollback('wireless section $sectionName', () async {
            await _apiService!.uciDelete(
              ip,
              auth,
              https,
              config: 'wireless',
              section: sectionName,
              context: context?.mounted == true ? context : null,
            );
            await _apiService!.uciCommit(
              ip,
              auth,
              https,
              config: 'wireless',
              context: context?.mounted == true ? context : null,
            );
            wirelessRolledBack = true;
          });
        } else if (updatedStation && existingStaConfig != null) {
          await attemptRollback('wireless section $sectionName', () async {
            const touchedOptions = {
              'network',
              'ssid',
              'encryption',
              'key',
              'bssid',
            };
            final setOptions = {
              'network',
              'ssid',
              'encryption',
              if (password.isNotEmpty) 'key',
              if (bssid?.isNotEmpty == true) 'bssid',
            };
            final originalValues = <String, String>{};
            for (final option in touchedOptions) {
              final value = existingStaConfig![option];
              if (value != null) {
                originalValues[option] = value is List
                    ? value.join(' ')
                    : value.toString();
              }
            }
            if (originalValues.isNotEmpty) {
              await _apiService!.uciSet(
                ip,
                auth,
                https,
                config: 'wireless',
                section: sectionName,
                values: originalValues,
                context: context?.mounted == true ? context : null,
              );
            }
            for (final option in setOptions) {
              if (!existingStaConfig!.containsKey(option)) {
                await _apiService!.uciDelete(
                  ip,
                  auth,
                  https,
                  config: 'wireless',
                  section: sectionName,
                  option: option,
                  context: context?.mounted == true ? context : null,
                );
              }
            }
            await _apiService!.uciCommit(
              ip,
              auth,
              https,
              config: 'wireless',
              context: context?.mounted == true ? context : null,
            );
            wirelessRolledBack = true;
          });
        }

        final canRemoveDependencies =
            (!createdStation && !updatedStation) || wirelessRolledBack;
        if (canRemoveDependencies) {
          var wanMembershipRolledBack = !addedToWan;
          if (addedToWan) {
            await attemptRollback('WAN firewall membership', () async {
              await _apiService!.systemExec(
                ip,
                auth,
                https,
                command: '/sbin/uci',
                params: [
                  'del_list',
                  'firewall.@zone[$wanZoneIndex].network=$staNetworkName',
                ],
                context: context?.mounted == true ? context : null,
              );
              await _apiService!.uciCommit(
                ip,
                auth,
                https,
                config: 'firewall',
                context: context?.mounted == true ? context : null,
              );
              wanMembershipRolledBack = true;
            });
          }

          if (createdNetwork && wanMembershipRolledBack) {
            await attemptRollback(
              'network interface $staNetworkName',
              () async {
                await _apiService!.uciDelete(
                  ip,
                  auth,
                  https,
                  config: 'network',
                  section: staNetworkName,
                  context: context?.mounted == true ? context : null,
                );
                await _apiService!.uciCommit(
                  ip,
                  auth,
                  https,
                  config: 'network',
                  context: context?.mounted == true ? context : null,
                );
              },
            );
          } else if (createdNetwork) {
            rollbackErrors.add(
              'kept network interface $staNetworkName because WAN firewall '
              'membership could not be removed',
            );
          }
        } else {
          rollbackErrors.add(
            'kept $staNetworkName dependencies because wireless section '
            '$sectionName could not be restored',
          );
        }

        if (restartAttempted && wirelessRolledBack) {
          await attemptRollback('wireless runtime state', () async {
            await _apiService!.uciSet(
              ip,
              auth,
              https,
              config: 'wireless',
              section: radioDevice,
              values: {'disabled': '0'},
              context: context?.mounted == true ? context : null,
            );
            await _apiService!.uciCommit(
              ip,
              auth,
              https,
              config: 'wireless',
              context: context?.mounted == true ? context : null,
            );
            await _apiService!.systemExec(
              ip,
              auth,
              https,
              command: '/sbin/wifi',
              params: ['up', radioDevice],
              context: context?.mounted == true ? context : null,
            );
          });
        }

        if (rollbackErrors.isNotEmpty) {
          Error.throwWithStackTrace(
            Exception(
              '$error; rollback incomplete: ${rollbackErrors.join('; ')}',
            ),
            stack,
          );
        }
        Error.throwWithStackTrace(error, stack);
      }

      return true;
    } catch (e, stack) {
      Logger.exception('Failed to connect to wireless network', e, stack);
      _dashboardError = 'Failed to connect to $ssid: $e';
      notifyListeners();
      return false;
    }
  }

  /// Enables or disables a specific wifi-iface UCI section.
  ///
  /// [uciSection] is the UCI section name (e.g., 'default_radio0', 'wifinet0').
  /// [enabled] true to enable, false to disable.
  Future<bool> setWirelessInterfaceEnabled(
    String uciSection,
    bool enabled, {
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) {
      await Future.delayed(const Duration(milliseconds: 500));
      await fetchDashboardData();
      return true;
    }

    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    try {
      Logger.info(
        'Toggle interface $uciSection → ${enabled ? 'enabled' : 'disabled'}',
      );

      await _apiService!.uciSet(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        section: uciSection,
        values: {'disabled': enabled ? '0' : '1'},
        context: context,
      );
      Logger.info('UCI set done');

      await _apiService!.uciCommit(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        context: context?.mounted == true ? context : null,
      );
      Logger.info('UCI commit done');
    } catch (e, stack) {
      // UCI operations failed — actual error
      Logger.exception('Failed to toggle wireless interface (UCI)', e, stack);
      _dashboardError = 'Failed to toggle interface: $e';
      notifyListeners();
      return false;
    }

    // UCI changes are committed — reload wireless to apply at runtime.
    // Reload failure is handled here so the UI can show the snackbar
    // and the toggle row does not remain stuck in its transitioning state.
    try {
      await _wifiReload(context: context?.mounted == true ? context : null);
    } catch (e, stack) {
      Logger.exception(
        'Wireless reload failed after toggle (interface may still be disabled)',
        e,
        stack,
      );
      _dashboardError = 'Interface toggled but wireless reload failed: $e';
      notifyListeners();
      return false;
    }
    Logger.info('Toggle interface $uciSection complete');
    return true;
  }

  /// Modifies properties of an existing wifi-iface UCI section.
  ///
  /// [uciSection] is the UCI section name (e.g., 'default_radio0').
  /// [values] is a map of UCI option key-value pairs to set.
  Future<bool> modifyWirelessInterface(
    String uciSection,
    Map<String, String> values, {
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) {
      await Future.delayed(const Duration(seconds: 1));
      await fetchDashboardData();
      return true;
    }

    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    try {
      await _apiService!.uciSet(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        section: uciSection,
        values: values,
        context: context,
      );

      await _apiService!.uciCommit(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        context: context?.mounted == true ? context : null,
      );
    } catch (e, stack) {
      Logger.exception('Failed to modify wireless interface (UCI)', e, stack);
      _dashboardError = 'Failed to modify interface: $e';
      notifyListeners();
      return false;
    }

    try {
      await _wifiReload(context: context?.mounted == true ? context : null);
    } catch (e, stack) {
      Logger.exception('Wireless reload failed after interface edit', e, stack);
      _dashboardError = 'Interface modified but wireless reload failed: $e';
      notifyListeners();
      return false;
    }
    return true;
  }

  /// Deletes a wifi-iface UCI section.
  ///
  /// [uciSection] is the UCI section name to remove.
  Future<bool> deleteWirelessInterface(
    String uciSection, {
    BuildContext? context,
  }) async {
    if (_reviewerModeEnabled) {
      await Future.delayed(const Duration(milliseconds: 500));
      await fetchDashboardData();
      return true;
    }

    if (_authService?.sysauth == null || _authService?.ipAddress == null) {
      return false;
    }

    try {
      await _apiService!.uciDelete(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        section: uciSection,
        context: context,
      );

      await _apiService!.uciCommit(
        _authService!.ipAddress!,
        _authService!.sysauth!,
        _authService!.useHttps,
        config: 'wireless',
        context: context?.mounted == true ? context : null,
      );
    } catch (e, stack) {
      Logger.exception('Failed to delete wireless interface (UCI)', e, stack);
      _dashboardError = 'Failed to delete interface: $e';
      notifyListeners();
      return false;
    }

    try {
      await _wifiReload(context: context?.mounted == true ? context : null);
    } catch (e, stack) {
      Logger.exception(
        'Wireless reload failed after interface deletion',
        e,
        stack,
      );
      _dashboardError = 'Interface deleted but wireless reload failed: $e';
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<bool> tryAutoLogin({BuildContext? context}) async {
    if (_reviewerModeEnabled) {
      return await _authService!.tryAutoLogin(
        null,
        null,
        null,
        null,
        context: context,
      );
    }

    // Ensure routers are loaded (constructor fires _initialize async,
    // so it may not have finished by the time login_screen calls us)
    if (_routerService != null && _routerService!.routers.isEmpty) {
      await loadRouters();
    }

    // No routers saved — nothing to auto-login to.
    // Also clear any stale credentials from secure storage.
    if (_routerService == null || _routerService!.routers.isEmpty) {
      await _authService?.logout();
      return false;
    }

    // If we have a selected router, use loginWithFallback
    final router = _routerService?.selectedRouter;
    if (router != null && _authService != null) {
      final result = await _serializeAuthOp<FallbackLoginResult>(
        () => _authService!.loginWithFallback(
          activeAddress: router.activeAddress,
          activeHttps: router.activeUseHttps,
          activeIndex: router.activeAddressIndex,
          fallbackAddress: router.inactiveAddress,
          fallbackHttps: router.inactiveUseHttps,
          username: router.username,
          password: router.password,
          context: context?.mounted == true ? context : null,
        ),
      );
      if (result.success) {
        if (result.usedAddressIndex != router.activeAddressIndex) {
          await updateRouter(
            router.copyWith(activeAddressIndex: result.usedAddressIndex),
          );
        }
        return true;
      }
      return false;
    }

    // Fallback to legacy auto-login from secure storage
    return await _authService?.tryAutoLogin(
          null,
          null,
          null,
          null,
          context: context?.mounted == true ? context : null,
        ) ??
        false;
  }

  /// Fetch all associated wireless MAC addresses from all wireless interfaces
  Future<Set<String>> fetchAllAssociatedWirelessMacs() async {
    if (_reviewerModeEnabled) {
      // Use the interface method for mock/reviewer mode
      final stationsMap = await _apiService!.fetchAssociatedStations();
      final macs = <String>{};
      stationsMap.forEach((_, stations) {
        macs.addAll(stations.map((m) => m.toLowerCase()));
      });
      return macs;
    } else {
      // Use the context-aware method for real API calls
      if (_routerService?.selectedRouter == null ||
          _authService?.sysauth == null) {
        return {};
      }

      // Use the address that actually succeeded during login
      final ip =
          _authService!.ipAddress ?? _routerService!.selectedRouter!.ipAddress;
      final useHttps = _authService!.useHttps;

      final stationsMap = await _apiService!
          .fetchAllAssociatedWirelessMacsWithContext(
            ipAddress: ip,
            sysauth: _authService!.sysauth!,
            useHttps: useHttps,
          );
      final macs = <String>{};
      stationsMap.forEach((_, stations) {
        macs.addAll(stations.map((m) => m.toLowerCase()));
      });
      return macs;
    }
  }

  @override
  void notifyListeners() {
    // Async continuations can outlive disposal; suppress their notifications
    // instead of letting them throw on a disposed ChangeNotifier.
    if (_isDisposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _isDisposed = true;
    // Invalidate every token-checked continuation (dashboard fetch,
    // throughput polls, login flows) that may still be in flight.
    _sessionToken++;
    _throughputTimer?.cancel();
    _cancelRebootPolling();
    _isRebooting = false;
    super.dispose();
  }

  /// Aggregates DHCP leases across all configured routers and classifies clients
  /// as wireless if their MAC appears in any router's associated stations list.
  Future<List<Client>> fetchAggregatedClients() async {
    try {
      var wirelessMacs = <String>{};
      Object? wirelessError;
      StackTrace? wirelessStack;
      try {
        wirelessMacs = await fetchAllAssociatedWirelessMacsAggregated();
      } catch (e, stack) {
        wirelessError = e;
        wirelessStack = stack;
      }

      var leases = <Map<String, dynamic>>[];
      Object? leaseError;
      StackTrace? leaseStack;
      try {
        leases = await fetchAggregatedDhcpLeases();
      } catch (e, stack) {
        leaseError = e;
        leaseStack = stack;
      }

      if (wirelessError != null) {
        if (leases.isEmpty) {
          Error.throwWithStackTrace(wirelessError, wirelessStack!);
        }
        Logger.warning(
          'Using DHCP clients without wireless data: $wirelessError',
        );
      }
      if (leaseError != null) {
        if (wirelessMacs.isEmpty) {
          Error.throwWithStackTrace(leaseError, leaseStack!);
        }
        Logger.warning('Using wireless clients without DHCP data: $leaseError');
      }

      final normalizedWireless = wirelessMacs
          .map((m) => m.toUpperCase().replaceAll('-', ':'))
          .toSet();

      // Convert to Client models with connection type
      final clients = <String, Client>{}; // key by normalized MAC
      for (final lease in leases) {
        final client = Client.fromLease(lease);
        final macNorm = client.macAddress.toUpperCase().replaceAll('-', ':');
        final isWireless = normalizedWireless.contains(macNorm);
        // If confirmed wireless by assoclist, mark wireless; otherwise keep heuristic
        final enriched = isWireless
            ? client.copyWith(connectionType: ConnectionType.wireless)
            : client;
        // Prefer entries that have more info (hostname length as heuristic)
        if (!clients.containsKey(macNorm) ||
            (enriched.hostname.isNotEmpty &&
                enriched.hostname.length >
                    (clients[macNorm]?.hostname.length ?? 0))) {
          clients[macNorm] = enriched;
        }
      }

      // Add wireless stations not in DHCP leases (AP-mode fallback)
      for (final mac in normalizedWireless) {
        if (!clients.containsKey(mac)) {
          clients[mac] = Client.fromWirelessStation(mac);
        }
      }

      final list = clients.values.toList();
      _sortClients(list);
      return list;
    } catch (e, stack) {
      Logger.exception('Failed to aggregate clients', e, stack);
      Error.throwWithStackTrace(e, stack);
    }
  }

  /// Returns clients for the currently selected router only
  Future<List<Client>> fetchClientsForSelectedRouter() async {
    try {
      if (_reviewerModeEnabled) {
        final stationsMap = await _apiService!.fetchAssociatedStations();
        final macs = <String>{};
        stationsMap.forEach((_, stations) {
          macs.addAll(stations.map((m) => m.toLowerCase()));
        });
        final result = await _apiService!.callSimple(
          'luci-rpc',
          'getDHCPLeases',
          {},
        );
        final leases = <Map<String, dynamic>>[];
        if (result is List && result.length > 1 && result[0] == 0) {
          final data = result[1] as Map<String, dynamic>;
          leases.addAll(
            (data['dhcp_leases'] as List<dynamic>? ?? [])
                .cast<Map<String, dynamic>>(),
          );
        }
        // Normalize wireless MACs for consistent lookup
        final normalizedMacs = macs
            .map((m) => m.toUpperCase().replaceAll('-', ':'))
            .toSet();
        final clientMap = <String, Client>{};
        for (final l in leases) {
          final c = Client.fromLease(l);
          final macNorm = c.macAddress.toUpperCase().replaceAll('-', ':');
          final isWireless = normalizedMacs.contains(macNorm);
          clientMap[macNorm] = isWireless
              ? c.copyWith(connectionType: ConnectionType.wireless)
              : c;
        }
        // Add wireless stations not in DHCP leases (AP-mode fallback)
        for (final mac in normalizedMacs) {
          if (!clientMap.containsKey(mac)) {
            clientMap[mac] = Client.fromWirelessStation(mac);
          }
        }
        final reviewerClients = clientMap.values.toList();
        _sortClients(reviewerClients);
        return reviewerClients;
      }

      if (_routerService?.selectedRouter == null ||
          _authService?.sysauth == null) {
        return [];
      }

      // Use the address that actually succeeded during login (may differ
      // from router.ipAddress after fallback)
      final activeIp =
          _authService!.ipAddress ??
          _routerService!.selectedRouter!.activeAddress;
      final activeHttps = _authService!.useHttps;

      final wireless = <String>{};
      Object? wirelessError;
      StackTrace? wirelessStack;
      try {
        final stationsMap = await _apiService!
            .fetchAllAssociatedWirelessMacsWithContext(
              ipAddress: activeIp,
              sysauth: _authService!.sysauth!,
              useHttps: activeHttps,
            );
        stationsMap.forEach(
          (_, stations) =>
              wireless.addAll(stations.map((mac) => mac.toLowerCase())),
        );
      } catch (e, stack) {
        wirelessError = e;
        wirelessStack = stack;
      }

      final leases = <Map<String, dynamic>>[];
      Object? leaseError;
      StackTrace? leaseStack;
      try {
        final callRes = await _apiService!.call(
          activeIp,
          _authService!.sysauth!,
          activeHttps,
          object: 'luci-rpc',
          method: 'getDHCPLeases',
          params: {},
        );
        if (callRes is! List || callRes.length < 2 || callRes[0] != 0) {
          throw const RpcException(
            object: 'luci-rpc',
            method: 'getDHCPLeases',
            detail: 'invalid response',
          );
        }
        final data = callRes[1] as Map<String, dynamic>;
        leases.addAll(
          (data['dhcp_leases'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>(),
        );
      } catch (e, stack) {
        leaseError = e;
        leaseStack = stack;
      }

      if (wirelessError != null) {
        if (leases.isEmpty) {
          Error.throwWithStackTrace(wirelessError, wirelessStack!);
        }
        Logger.warning(
          'Using DHCP clients without wireless data: $wirelessError',
        );
      }
      if (leaseError != null) {
        if (wireless.isEmpty) {
          Error.throwWithStackTrace(leaseError, leaseStack!);
        }
        Logger.warning('Using wireless clients without DHCP data: $leaseError');
      }

      // Normalize wireless MACs for consistent lookup
      final normalizedWireless = wireless
          .map((m) => m.toUpperCase().replaceAll('-', ':'))
          .toSet();

      final clientMap = <String, Client>{};
      for (final l in leases) {
        final c = Client.fromLease(l);
        final macNorm = c.macAddress.toUpperCase().replaceAll('-', ':');
        final isWireless = normalizedWireless.contains(macNorm);
        clientMap[macNorm] = isWireless
            ? c.copyWith(connectionType: ConnectionType.wireless)
            : c;
      }

      // Add wireless stations not in DHCP leases (AP-mode fallback)
      for (final mac in normalizedWireless) {
        if (!clientMap.containsKey(mac)) {
          clientMap[mac] = Client.fromWirelessStation(mac);
        }
      }

      // Enrich with GL.iNet data
      _enrichClientsWithGlInet(clientMap);

      final clients = clientMap.values.toList();
      _sortClients(clients);
      return clients;
    } catch (e, stack) {
      Logger.exception('Failed to fetch clients for selected router', e, stack);
      Error.throwWithStackTrace(e, stack);
    }
  }

  /// Returns a union set of associated wireless MAC addresses across all routers
  /// Known GL.iNet model → CPU core count mapping.
  static int? _getGlInetCoreCount(String model) {
    // IPQ5332 (BE9300, BE6500): Quad-core Cortex-A53
    // IPQ8071A (B2200): Quad-core Cortex-A53
    // MT7981B (MT3000): Dual-core Cortex-A53
    // MT7986A (MT6000): Quad-core Cortex-A53
    if (model.contains('BE9300') || model.contains('BE6500')) return 4;
    if (model.contains('MT6000') || model.contains('B2200')) return 4;
    if (model.contains('MT3000') || model.contains('MT2500')) return 2;
    return null;
  }

  /// Enrich client map with GL.iNet API data (band, online, device class).
  void _enrichClientsWithGlInet(Map<String, Client> clients) {
    final glinetClients = (_dashboardData?['glinet'] as GlInetData?)?.clients;
    if (glinetClients == null) return;

    for (final macNorm in clients.keys.toList()) {
      final glData = glinetClients[macNorm.toLowerCase().replaceAll('-', ':')];
      if (glData != null) {
        final currentClient = clients[macNorm]!;
        final iface = glData.wifiBand;
        final isOnline = glData.online;
        final deviceClass = glData.deviceClass;
        final connType = iface != null
            ? ConnectionType.wireless
            : (isOnline == true &&
                      currentClient.connectionType == ConnectionType.unknown
                  ? ConnectionType.wired
                  : currentClient.connectionType);
        // Prefer GL.iNet alias > GL.iNet name > existing hostname
        final alias = glData.alias;
        final glName = glData.name;
        final currentHostname = currentClient.hostname;
        final bestName = (alias != null && alias.isNotEmpty)
            ? alias
            : (glName != null &&
                  glName.isNotEmpty &&
                  (currentHostname == 'Unknown' || currentHostname == 'N/A'))
            ? glName
            : null;

        clients[macNorm] = currentClient.copyWith(
          connectionType: connType,
          wifiBand: iface,
          isOnline: isOnline,
          deviceClass: deviceClass,
          hostname: bestName,
        );
      }
    }
  }

  /// Sort clients: online first, then wireless > wired > unknown, then by hostname.
  void _sortClients(List<Client> clients) {
    clients.sort((a, b) {
      final aOnline = a.isOnline ?? true;
      final bOnline = b.isOnline ?? true;
      if (aOnline != bOnline) return aOnline ? -1 : 1;

      int typeOrder(ConnectionType t) {
        switch (t) {
          case ConnectionType.wireless:
            return 0;
          case ConnectionType.wired:
            return 1;
          default:
            return 2;
        }
      }

      final cmpType = typeOrder(
        a.connectionType,
      ).compareTo(typeOrder(b.connectionType));
      if (cmpType != 0) return cmpType;
      return a.hostname.toLowerCase().compareTo(b.hostname.toLowerCase());
    });
  }

  Future<Set<String>> fetchAllAssociatedWirelessMacsAggregated() async {
    try {
      if (_reviewerModeEnabled) {
        final stationsMap = await _apiService!.fetchAssociatedStations();
        final macs = <String>{};
        stationsMap.forEach((_, stations) {
          macs.addAll(stations.map((m) => m.toLowerCase()));
        });
        return macs;
      }

      final routers = _routerService?.routers ?? const <model.Router>[];
      if (routers.isEmpty) return {};

      Object? firstError;
      StackTrace? firstStack;
      var successfulRouters = 0;
      final tasks = routers.map((r) async {
        try {
          if (_apiService is RealApiService) {
            final real = _apiService as RealApiService;
            final res = await real.loginWithProtocolDetection(
              r.activeAddress,
              r.username,
              r.password,
              r.activeUseHttps,
            );
            if (res.token == null) {
              throw Exception('Login failed for ${r.ipAddress}');
            }
            final map = await _apiService!
                .fetchAllAssociatedWirelessMacsWithContext(
                  ipAddress: r.activeAddress,
                  sysauth: res.token!,
                  useHttps: res.actualUseHttps,
                );
            successfulRouters++;
            final set = <String>{};
            map.forEach((_, stations) {
              set.addAll(stations.map((m) => m.toLowerCase()));
            });
            return set;
          }
        } catch (e, stack) {
          firstError ??= e;
          firstStack ??= stack;
        }
        return <String>{};
      }).toList();

      final results = await Future.wait(tasks);
      if (successfulRouters == 0 && firstError != null) {
        Error.throwWithStackTrace(firstError!, firstStack!);
      }
      return results.fold<Set<String>>(<String>{}, (acc, s) => acc..addAll(s));
    } catch (e, stack) {
      Logger.exception('Failed to aggregate wireless MACs', e, stack);
      Error.throwWithStackTrace(e, stack);
    }
  }

  /// Returns a combined list of DHCP lease maps from all routers
  Future<List<Map<String, dynamic>>> fetchAggregatedDhcpLeases() async {
    try {
      if (_reviewerModeEnabled) {
        // Use mock data
        final result = await _apiService!.callSimple(
          'luci-rpc',
          'getDHCPLeases',
          {},
        );
        if (result is List && result.length > 1 && result[0] == 0) {
          final data = result[1] as Map<String, dynamic>;
          final leases = (data['dhcp_leases'] as List<dynamic>? ?? [])
              .cast<Map<String, dynamic>>();
          return leases;
        }
        return [];
      }

      final routers = _routerService?.routers ?? const <model.Router>[];
      if (routers.isEmpty) return [];

      Object? firstError;
      StackTrace? firstStack;
      var successfulRouters = 0;
      final tasks = routers.map((r) async {
        try {
          if (_apiService is RealApiService) {
            final real = _apiService as RealApiService;
            final res = await real.loginWithProtocolDetection(
              r.activeAddress,
              r.username,
              r.password,
              r.activeUseHttps,
            );
            if (res.token == null) {
              throw Exception('Login failed for ${r.ipAddress}');
            }
            final callRes = await _apiService!.call(
              r.activeAddress,
              res.token!,
              res.actualUseHttps,
              object: 'luci-rpc',
              method: 'getDHCPLeases',
              params: {},
            );
            if (callRes is List && callRes.length > 1 && callRes[0] == 0) {
              final data = callRes[1] as Map<String, dynamic>;
              final leases = (data['dhcp_leases'] as List<dynamic>? ?? [])
                  .cast<Map<String, dynamic>>();
              successfulRouters++;
              return leases;
            }
            throw const RpcException(
              object: 'luci-rpc',
              method: 'getDHCPLeases',
              detail: 'invalid response',
            );
          }
        } catch (e, stack) {
          firstError ??= e;
          firstStack ??= stack;
        }
        return <Map<String, dynamic>>[];
      }).toList();

      final results = await Future.wait(tasks);
      if (successfulRouters == 0 && firstError != null) {
        Error.throwWithStackTrace(firstError!, firstStack!);
      }
      // Deduplicate by MAC + IP
      final seen = <String, Map<String, dynamic>>{};
      for (final list in results) {
        for (final lease in list) {
          final mac = (lease['macaddr']?.toString() ?? '').toUpperCase();
          final ip = lease['ipaddr']?.toString() ?? '';
          final key = '$mac|$ip';
          if (!seen.containsKey(key)) {
            seen[key] = lease;
          }
        }
      }
      return seen.values.toList();
    } catch (e, stack) {
      Logger.exception('Failed to aggregate DHCP leases', e, stack);
      Error.throwWithStackTrace(e, stack);
    }
  }
}
