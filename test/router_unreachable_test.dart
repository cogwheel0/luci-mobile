import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:luci_mobile/services/api_service.dart';

void main() {
  final options = RequestOptions(path: '/cgi-bin/luci/admin/ubus');

  // The activity feed records "router unreachable" on this. It must mean the
  // router did not answer, not that it answered in a way the app disliked.
  test('connection-level failures count as unreachable', () {
    for (final type in [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      expect(
        isRouterUnreachable(DioException(requestOptions: options, type: type)),
        isTrue,
        reason: type.name,
      );
    }
    expect(isRouterUnreachable(const SocketException('refused')), isTrue);
    expect(isRouterUnreachable(TimeoutException('slow')), isTrue);
    expect(
      isRouterUnreachable(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: const SocketException('reset'),
        ),
      ),
      isTrue,
    );
  });

  test('an answer the app rejected is not unreachability', () {
    for (final type in [
      DioExceptionType.badCertificate,
      DioExceptionType.badResponse,
      DioExceptionType.cancel,
      DioExceptionType.unknown,
    ]) {
      expect(
        isRouterUnreachable(DioException(requestOptions: options, type: type)),
        isFalse,
        reason: type.name,
      );
    }
    expect(
      isRouterUnreachable(
        const RpcException(object: 'uci', method: 'changes', status: 6),
      ),
      isFalse,
    );
  });
}
