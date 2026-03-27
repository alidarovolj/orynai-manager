import 'package:flutter/foundation.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _apiService = ApiService();

  /// Отправка OTP-кода в WhatsApp.
  /// Возвращает 'OK' при успехе.
  Future<String> sendOtpWhatsApp(String phone) async {
    final result = await _apiService.post(
      '/api/v2/otp/whatsapp/send',
      body: {'phone': phone},
    );

    if (result is Map && result['data'] != null) {
      final body = result['data'].toString();
      return (body == 'OK' || body.isEmpty) ? 'OK' : body;
    }
    final body = result.toString();
    return (body == 'OK' || body.isEmpty) ? 'OK' : body;
  }

  /// Верификация OTP-кода.
  /// Возвращает map с полями: success, token, data, needsRegistration.
  /// После вызова этого метода дополнительных запросов не делается.
  Future<Map<String, dynamic>> verifyOtpWhatsApp(
    String phone,
    String code,
  ) async {
    try {
      final result = await _apiService.post(
        '/api/v2/otp/whatsapp/verify',
        body: {'phone': phone, 'code': code},
      );

      if (result is Map<String, dynamic>) {
        // Ошибка "Role not found"
        if (result['errorCode'] == 500 &&
            result['description']?.toString().contains('Role not found') ==
                true) {
          return {
            'success': false,
            'needsRegistration': true,
            'error': result,
          };
        }

        final token =
            result['token']?.toString() ?? result['data']?['token']?.toString();

        return {
          'success': true,
          'token': token ?? '',
          'data': result,
          'needsRegistration': false,
        };
      }

      return {'success': false, 'error': 'Неверный ответ сервера'};
    } catch (e) {
      debugPrint('verifyOtpWhatsApp error: $e');
      if (e is ApiException) {
        if (e.body?['errorCode'] == 500 &&
            e.body?['description']?.toString().contains('Role not found') ==
                true) {
          return {
            'success': false,
            'needsRegistration': true,
            'error': e.body,
          };
        }
        return {
          'success': false,
          'needsRegistration': false,
          'error': e.body ?? {'description': e.message},
        };
      }
      rethrow;
    }
  }
}
