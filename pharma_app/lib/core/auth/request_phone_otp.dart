import 'package:supabase_flutter/supabase_flutter.dart';

class PhoneOtpRequestException implements Exception {
  PhoneOtpRequestException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Sends (or resends) a phone OTP through the rate-limited edge function.
Future<void> requestPhoneOtp({
  required String phoneE164,
  Map<String, dynamic>? data,
  bool resend = false,
  bool shouldCreateUser = true,
}) async {
  try {
    final response = await Supabase.instance.client.functions.invoke(
      'request-phone-otp',
      body: {
        'phone': phoneE164,
        if (data != null) 'data': data,
        'action': resend ? 'resend' : 'send',
        'should_create_user': shouldCreateUser,
      },
    );

    if (response.status == 200) return;

    throw PhoneOtpRequestException(
      _messageFromPayload(response.data, response.status),
      statusCode: response.status,
    );
  } on FunctionException catch (e) {
    throw PhoneOtpRequestException(
      _messageFromPayload(e.details, e.status),
      statusCode: e.status,
    );
  }
}

String _messageFromPayload(dynamic payload, int status) {
  if (payload is Map) {
    final message = payload['message'];
    if (message is String && message.trim().isNotEmpty && message.trim() != '{}') {
      return message.trim();
    }
    final error = payload['error'];
    if (error is String && error.trim().isNotEmpty && error.trim() != '{}') {
      return _errorCodeToMessage(error.trim());
    }
    final detail = payload['detail'];
    if (detail is String && detail.trim().isNotEmpty) {
      return detail.trim();
    }
  }
  if (payload is String && payload.trim().isNotEmpty && payload.trim() != '{}') {
    return payload.trim();
  }
  return 'Could not send verification code (HTTP $status).';
}

String _errorCodeToMessage(String code) {
  switch (code) {
    case 'phone_daily_limit':
      return 'Too many codes sent to this number today. Try again tomorrow.';
    case 'phone_hourly_limit':
      return 'Too many codes sent to this number. Wait an hour and try again.';
    case 'ip_daily_limit':
      return 'Too many code requests from your network today. Try again tomorrow.';
    case 'sms_hook_failed':
    case 'smsethiopia_recipient_not_whitelisted':
      return 'Could not deliver SMS to this number. On trial SMS accounts, each number must be verified with SMSEthiopia first.';
    case 'rate_limit_check_failed':
      return 'Could not verify SMS limits. Try again in a moment.';
    default:
      return code.replaceAll('_', ' ');
  }
}
