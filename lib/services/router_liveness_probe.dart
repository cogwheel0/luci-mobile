import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'package:luci_mobile/utils/http_client_manager.dart';

/// Answers "is this router answering HTTP at all?" without credentials.
///
/// Used by reboot recovery and by the UCI apply flow, which both need to know
/// when a router has come back before they can do anything authenticated.
abstract class IRouterLivenessProbe {
  /// Tries a short list of always-present LuCI endpoints. Returns true as soon
  /// as one answers with a status below 500.
  Future<bool> isReachable(String hostWithPort, bool useHttps);
}

class RouterLivenessProbe implements IRouterLivenessProbe {
  const RouterLivenessProbe();

  static const Duration _timeout = Duration(seconds: 5);

  static const List<String> _endpoints = [
    '/', // Root
    '/cgi-bin/luci/', // LuCI login page
    '/cgi-bin/luci/admin', // Admin page
  ];

  @override
  Future<bool> isReachable(String hostWithPort, bool useHttps) async {
    final scheme = useHttps ? 'https' : 'http';

    for (final endpoint in _endpoints) {
      // Create a fresh Dio client for pinging to avoid certificate/connection
      // issues; declared outside try so finally can always close it.
      final dio = Dio(
        BaseOptions(
          connectTimeout: _timeout,
          receiveTimeout: _timeout,
          sendTimeout: _timeout,
          followRedirects: false,
          validateStatus: (code) => code != null && code >= 200 && code < 500,
        ),
      );
      try {
        final uri = _buildProbeUri(scheme, hostWithPort, endpoint);

        if (useHttps) {
          final adapter = IOHttpClientAdapter();
          adapter.createHttpClient = () {
            final httpClient = HttpClient();
            httpClient.connectionTimeout = _timeout;
            // Liveness probe only - no credentials are sent, but still prefer
            // an already-pinned certificate when we have one.
            httpClient.badCertificateCallback = (cert, host, port) {
              return HttpClientManager().isCertificatePinned(host, port, cert);
            };
            return httpClient;
          };
          dio.httpClientAdapter = adapter;
        }

        final response = await dio.getUri(uri);
        final isAlive =
            response.statusCode != null &&
            response.statusCode! >= 200 &&
            response.statusCode! < 500;
        if (isAlive) return true;
      } catch (_) {
        // Try the next endpoint; a router that is down fails all of them.
      } finally {
        // Each attempt uses its own throwaway client; close it so repeated
        // polls don't retain adapters and sockets until process shutdown.
        dio.close(force: true);
      }
    }

    return false;
  }

  /// Builds the probe URI structurally.
  ///
  /// String interpolation produces an invalid authority for IPv6 literals
  /// (missing brackets), while Uri host handling adds them automatically.
  /// Persisted addresses may hold unbracketed IPv6 literals (2+ colons) -
  /// bracket them first or the authority parse throws and every probe fails.
  static Uri _buildProbeUri(String scheme, String hostWithPort, String path) {
    var authorityInput = hostWithPort;
    if (!authorityInput.startsWith('[') &&
        ':'.allMatches(authorityInput).length > 1) {
      authorityInput = '[$authorityInput]';
    }
    final authority = Uri.parse('//$authorityInput');
    return Uri(
      scheme: scheme,
      host: authority.host,
      port: authority.hasPort ? authority.port : null,
      path: path,
    );
  }
}
