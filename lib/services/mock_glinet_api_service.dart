import 'package:luci_mobile/models/glinet_data.dart';
import 'package:luci_mobile/services/interfaces/glinet_api_service_interface.dart';

class MockGlInetApiService implements IGlInetApiService {
  @override
  bool get isAuthenticated => false;

  @override
  Future<GlInetData?> fetchData(
    String host,
    String password,
    bool useHttps,
  ) async => null;

  @override
  void clearSession() {}
}
