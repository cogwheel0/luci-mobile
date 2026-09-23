import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/services/api_service.dart';

void main() {
  final options = RequestOptions(path: '/cgi-bin/luci/admin/ubus');

  // The classification is what makes the message translatable: the screens
  // no longer read an English sentence out of the exception.
  test('a missing module names the package to install', () {
    const error = RpcException(
      object: 'luci-rpc',
      method: 'getHostHints',
      status: 4,
    );
    final info = describeApiError(error);

    expect(info.kind, ApiErrorKind.missingPackage);
    expect(info.call, 'luci-rpc.getHostHints');
    expect(info.package, 'rpcd-mod-luci');
    expect(
      describeApiError(
        const RpcException(object: 'iwinfo', method: 'assoclist', status: 3),
      ).package,
      'rpcd-mod-iwinfo',
    );
  });

  test('a refusal is told apart from a module that is absent', () {
    expect(
      describeApiError(
        const RpcException(object: 'uci', method: 'set', status: 6),
      ).kind,
      ApiErrorKind.noPermission,
    );
    // An object the app has no package name for is just a failed call.
    final other = describeApiError(
      const RpcException(object: 'rc', method: 'init', status: 4),
    );
    expect(other.kind, ApiErrorKind.rpcFailed);
    expect(other.package, isNull);
  });

  test('a rejected session is told apart from an unreachable router', () {
    expect(
      describeApiError(
        DioException(
          requestOptions: options,
          response: Response<void>(requestOptions: options, statusCode: 403),
        ),
      ).kind,
      ApiErrorKind.sessionRejected,
    );
    final http = describeApiError(
      DioException(
        requestOptions: options,
        response: Response<void>(requestOptions: options, statusCode: 500),
      ),
    );
    expect(http.kind, ApiErrorKind.httpStatus);
    expect(http.status, 500);
    expect(
      describeApiError(
        DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        ),
      ).kind,
      ApiErrorKind.unreachable,
    );
    expect(
      describeApiError(const SocketException('refused')).kind,
      ApiErrorKind.unreachable,
    );
  });

  test('anything else keeps its own words', () {
    final info = describeApiError(Exception('something specific'));
    expect(info.kind, ApiErrorKind.other);
    expect(info.detail, 'something specific');
  });

  // The router's own explanation cannot be translated, so it is carried
  // through rather than replaced.
  test('the router\'s explanation is carried through', () {
    final info = describeApiError(
      const RpcException(
        object: 'uci',
        method: 'apply',
        status: 9,
        detail: 'commit failed',
      ),
    );
    expect(info.kind, ApiErrorKind.rpcFailed);
    expect(info.detail, 'commit failed');
  });
}
