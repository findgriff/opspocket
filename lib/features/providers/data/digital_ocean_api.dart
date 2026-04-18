import 'package:dio/dio.dart';

import '../../../app/core/constants/app_constants.dart';
import '../../../app/core/errors/app_error.dart';
import '../../../shared/models/server_profile.dart';
import '../domain/provider_api.dart';

/// DigitalOcean v2 API client. Token injection is via constructor so we never
/// leak it into logs or request interceptors.
class DigitalOceanApi implements ProviderApi {
  final Dio _dio;
  DigitalOceanApi({required String token, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConstants.digitalOceanBaseUrl,
              connectTimeout: AppConstants.providerHttpTimeout,
              receiveTimeout: AppConstants.providerHttpTimeout,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
            ),);

  @override
  ProviderType get type => ProviderType.digitalOcean;

  @override
  Future<ProviderInstanceStatus> getStatus({required String resourceId}) async {
    try {
      final res = await _dio.get('/droplets/$resourceId');
      final d = res.data['droplet'];
      if (d == null) {
        throw const ProviderApiError('Droplet not found', statusCode: 404);
      }
      return ProviderInstanceStatus(
        id: d['id'].toString(),
        name: d['name']?.toString() ?? 'unknown',
        status: d['status']?.toString() ?? 'unknown',
        region: d['region']?['slug']?.toString(),
        ipv4: (d['networks']?['v4'] as List<dynamic>? ?? [])
            .map((e) => e['ip_address']?.toString())
            .whereType<String>()
            .toList(),
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  @override
  Future<void> reboot({required String resourceId}) async {
    try {
      await _dio.post(
        '/droplets/$resourceId/actions',
        data: {'type': 'reboot'},
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  @override
  Future<void> powerCycle({required String resourceId}) async {
    try {
      await _dio.post(
        '/droplets/$resourceId/actions',
        data: {'type': 'power_cycle'},
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  AppError _mapDioError(DioException e) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return const ProviderApiError('DigitalOcean token invalid or insufficient scope', statusCode: 401);
    }
    if (status == 404) {
      return const ProviderApiError('DigitalOcean resource not found', statusCode: 404);
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return const ProviderApiError('DigitalOcean API timed out');
    }
    return ProviderApiError('DigitalOcean API error (${status ?? 'network'})', statusCode: status, cause: e);
  }
}
