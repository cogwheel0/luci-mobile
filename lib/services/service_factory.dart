import 'package:luci_mobile/services/interfaces/auth_service_interface.dart';
import 'package:luci_mobile/services/interfaces/api_service_interface.dart';
import 'package:luci_mobile/services/auth_service.dart';
import 'package:luci_mobile/services/api_service.dart';
import 'package:luci_mobile/services/mock_auth_service.dart';
import 'package:luci_mobile/services/mock_api_service.dart';
import 'package:luci_mobile/services/secure_storage_service.dart';
import 'package:luci_mobile/services/router_service.dart';
import 'package:luci_mobile/services/throughput_service.dart';
import 'package:luci_mobile/services/app_lock_service.dart';

abstract class ServiceFactory {
  IAuthService createAuthService();
  IApiService createApiService();
  SecureStorageService createSecureStorageService();
  RouterService createRouterService();
  ThroughputService createThroughputService();
  AppLockService createAppLockService();
}

class ProductionServiceFactory implements ServiceFactory {
  @override
  IAuthService createAuthService() => RealAuthService(createApiService());

  @override
  IApiService createApiService() => RealApiService();

  @override
  SecureStorageService createSecureStorageService() => SecureStorageService();

  @override
  RouterService createRouterService() => RouterService();

  @override
  ThroughputService createThroughputService() => ThroughputService();

  @override
  AppLockService createAppLockService() => AppLockService();
}

class ReviewerModeServiceFactory implements ServiceFactory {
  @override
  IAuthService createAuthService() => MockAuthService();

  @override
  IApiService createApiService() => MockApiService();

  @override
  SecureStorageService createSecureStorageService() => SecureStorageService();

  @override
  RouterService createRouterService() => RouterService();

  @override
  ThroughputService createThroughputService() => ThroughputService();

  @override
  AppLockService createAppLockService() => AppLockService();
}

class ServiceContainer {
  static ServiceContainer? _instance;
  static ServiceContainer get instance => _instance ??= ServiceContainer._();
  
  ServiceContainer._();

  ServiceFactory? _factory;
  
  void setFactory(ServiceFactory factory) {
    _factory = factory;
  }
  
  ServiceFactory get factory {
    if (_factory == null) {
      throw StateError('ServiceFactory not initialized. Call setFactory() first.');
    }
    return _factory!;
  }
  
  static void configure({required bool reviewerMode}) {
    instance.setFactory(
      reviewerMode 
        ? ReviewerModeServiceFactory()
        : ProductionServiceFactory()
    );
  }
}