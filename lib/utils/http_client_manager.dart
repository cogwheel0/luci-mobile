import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:luci_mobile/l10n/luci_localizations.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'logger.dart';

/// SHA-256 fingerprint (hex) of the certificate's DER encoding.
String _certificateFingerprint(X509Certificate cert) =>
    sha256.convert(cert.der).toString();

/// Normalizes a host for certificate-pin keys. `Uri.host` (and therefore
/// the host passed to `badCertificateCallback`) returns IPv6 literals
/// without brackets, while user input may include them - strip brackets so
/// pin writes and reads always agree.
String _normalizePinHost(String host) =>
    host.startsWith('[') && host.endsWith(']')
    ? host.substring(1, host.length - 1)
    : host;

/// Extracts the host portion of a stored pin key.
///
/// Canonical keys are `[host]:port` (brackets always present), so parsing
/// is unambiguous for every address family. Legacy keys were bare
/// `host:port`; those are split at the last colon, which is correct for
/// keys this app generated because the port suffix was always appended by
/// us (bare IPv6 literals in legacy keys therefore parse correctly too).
(String, int)? _parsePinKey(String key) {
  if (key.startsWith('[')) {
    final close = key.indexOf(']');
    if (close == -1) return null;
    final host = _normalizePinHost(key.substring(1, close));
    final port = int.tryParse(key.substring(close + 2));
    if (port == null) return null;
    return (host, port);
  }
  final match = RegExp(r'^(.+):(\d+)$').firstMatch(key);
  if (match == null) return null;
  return (_normalizePinHost(match.group(1)!), int.parse(match.group(2)!));
}

/// Builds the canonical, unambiguous pin key. Bare IPv6 hosts are bracketed
/// so the appended port can never be confused with part of the address.
String _pinKey(String host, int port) => '[${_normalizePinHost(host)}]:$port';

/// HTTP client manager that provides secure client instances with proper
/// certificate validation and connection pooling.
///
/// Self-signed certificates are trusted only after the user explicitly
/// accepts them, and only as long as the certificate presented on later
/// connections matches the SHA-256 fingerprint recorded at acceptance time
/// (certificate pinning). A different - possibly attacker-supplied -
/// certificate for the same host triggers a fresh warning.
class HttpClientManager {
  static final HttpClientManager _instance = HttpClientManager._internal();
  factory HttpClientManager() => _instance;

  final Map<String, Dio> _clients = {};

  /// Maps `host:port` to the SHA-256 fingerprint of the accepted certificate.
  final Map<String, String> _acceptedCertFingerprints = {};
  static const String _acceptedCertsKey = 'accepted_certificates';

  // Pin-store synchronization: `_loadAcceptedCertificates()` runs async from
  // the constructor. If the user accepts a certificate (or clears pins)
  // before the storage read completes, applying the on-disk snapshot
  // afterwards would clobber newer in-memory state - so mutations set
  // [_pinsMutated] and the loader defers to it.
  bool _pinsMutated = false;

  /// Completes when persisted pins have been merged into memory. Pin-reading
  /// entry points await this so an early connection cannot miss stored pins.
  late final Future<void> _pinsLoaded;

  // All pin-store mutations (load/migration, accept, clear) run through
  // this queue in submission order - an acceptance completing after a
  // clear can never resurrect a removed pin, and vice versa.
  Future<void> _pinMutationQueue = Future<void>.value();

  /// Bumped by every clear so an acceptance dialog that was open during
  /// the clear can detect it and refuse to persist afterwards.
  int _pinGeneration = 0;

  Future<T> _serializePinMutation<T>(Future<T> Function() action) {
    final op = _pinMutationQueue.then((_) => action());
    _pinMutationQueue = op.then((_) {}, onError: (_) {});
    return op;
  }

  HttpClientManager._internal() {
    _pinsLoaded = _serializePinMutation(_loadAcceptedCertificates);
  }

  /// Creates or returns a cached HTTP client for the given host
  /// In production builds, certificate validation is enforced with user warnings
  /// In debug builds, self-signed certificates can be allowed automatically
  Dio getClient(String hostWithPort, bool useHttps, {BuildContext? context}) {
    final key = '$hostWithPort-$useHttps';

    if (_clients.containsKey(key)) {
      return _clients[key]!;
    }

    final client = _createSecureClient(useHttps);
    _clients[key] = client;
    return client;
  }

  String _extractHostname(String hostWithPort) {
    if (hostWithPort.startsWith('[')) {
      // IPv6 address
      final endBracket = hostWithPort.indexOf(']');
      if (endBracket != -1) {
        return hostWithPort.substring(0, endBracket + 1);
      }
    }
    // Unbracketed IPv6 literals contain 2+ colons and cannot carry a port
    // suffix - the whole input is the host. (lastIndexOf(':') would
    // otherwise misread e.g. '2001:db8::1' as host '2001:db8:'.)
    if (':'.allMatches(hostWithPort).length > 1) {
      return hostWithPort;
    }
    // IPv4/hostname, optionally with an explicit port
    final colonIndex = hostWithPort.lastIndexOf(':');
    if (colonIndex != -1) {
      final portPart = hostWithPort.substring(colonIndex + 1);
      if (portPart.isNotEmpty && int.tryParse(portPart) != null) {
        return hostWithPort.substring(0, colonIndex);
      }
    }
    return hostWithPort;
  }

  int _effectivePort(String hostWithPort, bool useHttps) {
    if (hostWithPort.startsWith('[')) {
      final endBracket = hostWithPort.indexOf(']');
      if (endBracket != -1 && endBracket + 1 < hostWithPort.length) {
        return int.tryParse(hostWithPort.substring(endBracket + 2)) ??
            (useHttps ? 443 : 80);
      }
    }
    // Only a single colon can denote an explicit port; bare IPv6 literals
    // have none.
    if (':'.allMatches(hostWithPort).length == 1) {
      final port = int.tryParse(
        hostWithPort.substring(hostWithPort.lastIndexOf(':') + 1),
      );
      if (port != null) return port;
    }
    return useHttps ? 443 : 80;
  }

  /// Splits a cached client key (`host[:port]-true|false`) into its parts.
  (String, bool) _parseClientKey(String key) {
    final separator = key.lastIndexOf('-');
    if (separator == -1) return (key, false);
    final flag = key.substring(separator + 1);
    if (flag != 'true' && flag != 'false') return (key, false);
    return (key.substring(0, separator), flag == 'true');
  }

  bool _keyMatchesHost(String key, String host, bool useHttps) {
    final (keyHost, keyUseHttps) = _parseClientKey(key);
    if (keyUseHttps != useHttps) return false;
    return _normalizePinHost(_extractHostname(keyHost)) ==
            _normalizePinHost(_extractHostname(host)) &&
        _effectivePort(keyHost, keyUseHttps) == _effectivePort(host, useHttps);
  }

  void _closeAndRemoveClients(bool Function(String key) matches) {
    final keysToRemove = _clients.keys.where(matches).toList();
    for (final key in keysToRemove) {
      final dio = _clients.remove(key);
      final adapter = dio?.httpClientAdapter;
      if (adapter is IOHttpClientAdapter) {
        adapter.close(force: true);
      }
    }
  }

  Dio _createSecureClient(bool useHttps) {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 15),
        followRedirects: true,
        // Status is validated per request when needed (e.g., handle 302 on login)
      ),
    );

    // Only log request errors; suppress per-request debug noise
    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (e, handler) {
          Logger.error(
            'HTTP ${e.requestOptions.method} ${e.requestOptions.uri} failed',
            e,
            e.stackTrace,
          );
          handler.next(e);
        },
      ),
    );

    if (useHttps) {
      final adapter = IOHttpClientAdapter();
      adapter.createHttpClient = () {
        final httpClient = HttpClient();
        httpClient.connectionTimeout = const Duration(seconds: 10);
        httpClient.badCertificateCallback = (cert, certHost, port) {
          // Trust the certificate only if its fingerprint was accepted
          // for this exact host:port pair.
          final expected = _acceptedCertFingerprints[_pinKey(certHost, port)];
          return expected != null && expected == _certificateFingerprint(cert);
        };
        return httpClient;
      };
      dio.httpClientAdapter = adapter;
    }

    return dio;
  }

  /// Loads pinned certificate fingerprints from secure storage.
  ///
  /// Entries written by older app versions stored plain `true` booleans
  /// without a fingerprint; those are discarded so affected hosts get a
  /// fresh acceptance prompt under the stricter pinning scheme.
  /// Loads persisted pins, migrating legacy key formats to the canonical
  /// `[host]:port` form in memory.
  Future<void> _loadAcceptedCertificates() async {
    try {
      final storage = const FlutterSecureStorage();
      final certsJson = await storage.read(key: _acceptedCertsKey);
      // A mutation (accept/clear) happened while the read was in flight -
      // in-memory state is newer than the on-disk snapshot, so keep it.
      if (_pinsMutated) return;
      if (certsJson != null) {
        final certs = Map<String, dynamic>.from(jsonDecode(certsJson));
        var migrated = false;
        certs.forEach((key, value) {
          if (value is! String || value.isEmpty) return;
          final parsed = _parsePinKey(key);
          if (parsed == null) return;
          final (host, port) = parsed;
          final canonical = _pinKey(host, port);
          if (_pinsMutated) return;
          _acceptedCertFingerprints.putIfAbsent(canonical, () => value);
          if (canonical != key) migrated = true;
        });
        // Persist the rewritten keys so the legacy format disappears even
        // if nothing else changes this session. Mutations that raced the
        // load already saved their own state; only rewrite when we know
        // the in-memory map reflects disk.
        if (migrated && !_pinsMutated) await _saveAcceptedCertificates();
      }
    } catch (e) {
      Logger.warning('Failed to load accepted certificates: $e');
    }
  }

  /// Saves pinned certificate fingerprints to secure storage
  Future<void> _saveAcceptedCertificates() async {
    try {
      final storage = const FlutterSecureStorage();
      await storage.write(
        key: _acceptedCertsKey,
        value: jsonEncode(_acceptedCertFingerprints),
      );
    } catch (e) {
      Logger.warning('Failed to save accepted certificates: $e');
    }
  }

  /// Whether [cert] matches the pinned fingerprint for `host:port`.
  bool isCertificatePinned(String host, int port, X509Certificate cert) {
    return _acceptedCertFingerprints[_pinKey(host, port)] ==
        _certificateFingerprint(cert);
  }

  /// Disposes of cached clients for the given host
  void disposeClient(String host, bool useHttps) {
    _closeAndRemoveClients((key) => _keyMatchesHost(key, host, useHttps));
  }

  /// Clear accepted certificates (useful for logout or security reset)
  Future<void> clearAcceptedCertificates() {
    return _serializePinMutation(() async {
      _pinsMutated = true;
      _pinGeneration++;
      _acceptedCertFingerprints.clear();

      // Clear all cached HTTP clients
      _closeAndRemoveClients((_) => true);

      // Delete from secure storage
      try {
        final storage = const FlutterSecureStorage();
        await storage.delete(key: _acceptedCertsKey);
      } catch (e) {
        Logger.warning('Failed to delete accepted certificates: $e');
      }
    });
  }

  /// Clears pinned certificates and cached clients for a specific host
  /// (across all ports)
  Future<void> clearCertificatesForHost(String host) {
    return _serializePinMutation(() async {
      _pinsMutated = true;
      _pinGeneration++;
      final hostname = _normalizePinHost(_extractHostname(host));
      _acceptedCertFingerprints.removeWhere((key, value) {
        final parsed = _parsePinKey(key);
        return parsed != null && _normalizePinHost(parsed.$1) == hostname;
      });

      _closeAndRemoveClients(
        (key) =>
            _normalizePinHost(_extractHostname(_parseClientKey(key).$1)) ==
            hostname,
      );

      await _saveAcceptedCertificates();
    });
  }

  /// Prompts user to pin the certificate for a given host.
  /// Returns true if the user accepts, false otherwise.
  Future<bool> promptForCertificateAcceptance({
    required BuildContext context,
    required String hostWithPort,
    required bool useHttps,
  }) async {
    if (!useHttps) return true; // Non-HTTPS doesn't need certificate acceptance
    if (!context.mounted) return false;
    // Make sure persisted pins are in memory before deciding whether to
    // prompt - otherwise an early connection could re-prompt for a host
    // that was already accepted.
    await _pinsLoaded;

    final host = _extractHostname(hostWithPort);

    // Probe the endpoint once, capturing the presented certificate if the
    // TLS handshake fails validation.
    X509Certificate? presentedCert;
    final testClient = HttpClient();
    testClient.connectionTimeout = const Duration(seconds: 5);
    testClient.badCertificateCallback = (cert, certHost, port) {
      // Keep the certificate of the originally requested host; a redirect
      // target's certificate must not be pinned under this host's key.
      presentedCert ??= cert;
      // Accept for this probe only so we can inspect the certificate;
      // nothing is persisted unless the user approves below.
      return true;
    };

    try {
      // Build the probe URI structurally: string interpolation breaks for
      // unbracketed IPv6 literals, while the Uri constructor brackets them.
      final port = _effectivePort(hostWithPort, useHttps);
      final uri = Uri(
        scheme: 'https',
        host: _normalizePinHost(host),
        port: port == 443 ? null : port,
      );
      final request = await testClient.getUrl(uri);
      // Never pin a redirect target's certificate under this host.
      request.followRedirects = false;
      await request.close();

      if (presentedCert == null) {
        // Certificate chains to a trusted CA - nothing to accept.
        return true;
      }

      final certKey = _pinKey(host, _effectivePort(hostWithPort, useHttps));
      final fingerprint = _certificateFingerprint(presentedCert!);

      // Already pinned with this exact certificate.
      if (_acceptedCertFingerprints[certKey] == fingerprint) {
        return true;
      }

      if (!context.mounted) return false;
      // Snapshot the generation before showing the dialog: if a clear runs
      // while the dialog is open, the user's approval must be rejected
      // instead of restoring a pin the user just revoked.
      final generation = _pinGeneration;
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) => AlertDialog(
          icon: Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
            size: 32,
          ),
          title: Text(context.l10n.certificateWarning),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.untrustedCertificateDescription(host),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.certificateDetails,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildCertDetail(
                        context.l10n.certificateSubject,
                        presentedCert!.subject,
                      ),
                      _buildCertDetail(
                        context.l10n.certificateIssuer,
                        presentedCert!.issuer,
                      ),
                      _buildCertDetail(
                        context.l10n.certificateValidFrom,
                        presentedCert!.startValidity.toLocal().toString().split(
                          '.',
                        )[0],
                      ),
                      _buildCertDetail(
                        context.l10n.certificateValidUntil,
                        presentedCert!.endValidity.toLocal().toString().split(
                          '.',
                        )[0],
                      ),
                      _buildCertDetail('SHA-256', fingerprint),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.errorContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.error.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Theme.of(context).colorScheme.error,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.l10n.certificateSafetyWarning,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.error,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: Text(context.l10n.acceptRisk),
            ),
          ],
        ),
      );

      if (result == true) {
        // Pin the accepted certificate's fingerprint persistently, in
        // order with load/clear operations - unless a clear ran while the
        // dialog was open, in which case the approval is stale.
        if (generation != _pinGeneration) {
          Logger.info(
            'Certificate acceptance discarded: pins changed while dialog was open',
          );
          return false;
        }
        await _serializePinMutation(() async {
          _pinsMutated = true;
          _pinGeneration++;
          _acceptedCertFingerprints[certKey] = fingerprint;
          await _saveAcceptedCertificates();
        });
        return true;
      }
    } catch (e) {
      if (e is! HandshakeException) {
        Logger.warning('Certificate probe failed: $e');
      }
    } finally {
      testClient.close();
    }

    return false;
  }

  Widget _buildCertDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
