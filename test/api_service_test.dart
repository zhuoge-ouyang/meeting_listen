import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recordwise/services/api_service.dart';

void main() {
  group('ApiService.describeDioException', () {
    test('uses backend detail instead of Dio status-code help text', () {
      final requestOptions = RequestOptions(path: '/api/meetings');
      final error = DioException(
        requestOptions: requestOptions,
        response: Response(
          requestOptions: requestOptions,
          statusCode: 503,
          data: {
            'detail':
                'Aliyun ASR/OSS is not configured. Set DASHSCOPE_API_KEY and ALIYUN_OSS_* environment variables.',
          },
        ),
        message:
            'This exception was thrown because the response has a status code of 503 and RequestOptions.validateStatus was configured to throw for this status code.',
        type: DioExceptionType.badResponse,
      );

      final message = ApiService.describeDioException(error);

      expect(message, contains('Aliyun ASR/OSS is not configured'));
      expect(message, isNot(contains('developer.mozilla.org')));
      expect(message, isNot(contains('validateStatus')));
    });
  });
}
