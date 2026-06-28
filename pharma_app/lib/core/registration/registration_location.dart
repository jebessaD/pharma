import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const registrationCountryCodeKey = 'registration_country_code';
const registrationCountryNameKey = 'registration_country_name';
const registrationRegionKey = 'registration_region';
const registrationCityKey = 'registration_city';
const registrationLocationSourceKey = 'registration_location_source';

class RegistrationLocation {
  const RegistrationLocation({
    this.countryCode,
    this.countryName,
    this.region,
    this.city,
    this.source,
  });

  static const empty = RegistrationLocation();

  final String? countryCode;
  final String? countryName;
  final String? region;
  final String? city;
  final String? source;

  bool get isEmpty =>
      countryCode == null &&
      countryName == null &&
      region == null &&
      city == null &&
      source == null;

  Map<String, dynamic> toAuthMetadata() {
    if (isEmpty) return const {};
    return {
      if (countryCode != null) registrationCountryCodeKey: countryCode,
      if (countryName != null) registrationCountryNameKey: countryName,
      if (region != null) registrationRegionKey: region,
      if (city != null) registrationCityKey: city,
      if (source != null) registrationLocationSourceKey: source,
    };
  }

  Map<String, dynamic> toRpcParams() {
    if (isEmpty) return const {};
    return {
      if (countryCode != null) 'p_registration_country_code': countryCode,
      if (countryName != null) 'p_registration_country_name': countryName,
      if (region != null) 'p_registration_region': region,
      if (city != null) 'p_registration_city': city,
      if (source != null) 'p_registration_location_source': source,
    };
  }

  static RegistrationLocation fromAuthMetadata(Map<String, dynamic> metadata) {
    return RegistrationLocation(
      countryCode: _text(metadata[registrationCountryCodeKey])?.toUpperCase(),
      countryName: _text(metadata[registrationCountryNameKey]),
      region: _text(metadata[registrationRegionKey]),
      city: _text(metadata[registrationCityKey]),
      source: _source(metadata[registrationLocationSourceKey]),
    ).normalized();
  }

  static RegistrationLocation fromFunctionPayload(Object? payload) {
    if (payload is! Map) return RegistrationLocation.empty;
    return RegistrationLocation(
      countryCode: _text(payload['country_code'])?.toUpperCase(),
      countryName: _text(payload['country_name']),
      region: _text(payload['region']),
      city: _text(payload['city']),
      source: _source(payload['source']),
    ).normalized();
  }

  static RegistrationLocation fromIpapiPayload(Object? payload) {
    if (payload is! Map) return RegistrationLocation.empty;
    return RegistrationLocation(
      countryCode: _text(payload['country_code'])?.toUpperCase(),
      countryName: _text(payload['country_name']),
      region: _text(payload['region']),
      city: _text(payload['city']),
      source: 'ip',
    ).normalized();
  }

  static RegistrationLocation fromIpwhoPayload(Object? payload) {
    if (payload is! Map) return RegistrationLocation.empty;
    if (payload['success'] == false) return RegistrationLocation.empty;
    return RegistrationLocation(
      countryCode: _text(payload['country_code'])?.toUpperCase(),
      countryName: _text(payload['country']),
      region: _text(payload['region']),
      city: _text(payload['city']),
      source: 'ip',
    ).normalized();
  }

  RegistrationLocation normalized() {
    final countryCodeUpper = countryCode?.toUpperCase();
    final normalizedCountryCode =
        countryCodeUpper != null &&
            RegExp(r'^[A-Z]{2}$').hasMatch(countryCodeUpper)
        ? countryCodeUpper
        : null;
    final normalizedSource = source == 'ip' ? source : null;
    final hasLocation =
        normalizedCountryCode != null ||
        countryName != null ||
        region != null ||
        city != null;
    return RegistrationLocation(
      countryCode: normalizedCountryCode,
      countryName: countryName,
      region: region,
      city: city,
      source: hasLocation ? (normalizedSource ?? 'ip') : null,
    );
  }
}

Future<RegistrationLocation> inferRegistrationLocation() async {
  _debugLocationLog('Starting registration location lookup');
  try {
    _debugLocationLog('Calling Supabase Edge Function: registration-location');
    final response = await Supabase.instance.client.functions.invoke(
      'registration-location',
    );
    final location = RegistrationLocation.fromFunctionPayload(response.data);
    _debugLocationLog('Edge Function result: ${_locationSummary(location)}');
    if (!location.isEmpty) return location;
  } catch (error) {
    _debugLocationLog('Edge Function lookup failed: $error');
    // Fall through to direct lookup if the edge function is unavailable.
  }

  final fallbackLocation = await _inferRegistrationLocationDirectly();
  _debugLocationLog(
    'Final fallback result: ${_locationSummary(fallbackLocation)}',
  );
  return fallbackLocation;
}

Future<RegistrationLocation> _inferRegistrationLocationDirectly() async {
  final ipwhoLocation = await _fetchDirectLocation(
    'ipwho.is',
    Uri.https('ipwho.is', '/'),
    RegistrationLocation.fromIpwhoPayload,
  );
  if (!ipwhoLocation.isEmpty) return ipwhoLocation;

  return _fetchDirectLocation(
    'ipapi.co',
    Uri.https('ipapi.co', '/json/'),
    RegistrationLocation.fromIpapiPayload,
  );
}

Future<RegistrationLocation> _fetchDirectLocation(
  String provider,
  Uri uri,
  RegistrationLocation Function(Object? payload) parsePayload,
) async {
  try {
    _debugLocationLog('Calling direct location provider: $provider');
    final response = await http
        .get(uri, headers: const {'Accept': 'application/json'})
        .timeout(const Duration(milliseconds: 1500));
    _debugLocationLog('$provider HTTP status: ${response.statusCode}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return RegistrationLocation.empty;
    }
    final location = parsePayload(jsonDecode(response.body));
    _debugLocationLog('$provider result: ${_locationSummary(location)}');
    return location;
  } catch (error) {
    _debugLocationLog('$provider lookup failed: $error');
    return RegistrationLocation.empty;
  }
}

void _debugLocationLog(String message) {
  if (!kDebugMode) return;
  debugPrint('[RegistrationLocation] $message');
}

String _locationSummary(RegistrationLocation location) {
  if (location.isEmpty) return 'empty';
  return 'countryCode=${location.countryCode ?? "-"}, '
      'countryName=${location.countryName ?? "-"}, '
      'region=${location.region ?? "-"}, '
      'city=${location.city ?? "-"}, '
      'source=${location.source ?? "-"}';
}

String? _text(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

String? _source(Object? value) {
  final source = _text(value)?.toLowerCase();
  return source == 'ip' ? source : null;
}
