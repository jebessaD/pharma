import 'package:flutter_test/flutter_test.dart';
import 'package:pharma_app/core/auth/ethiopian_phone.dart';

void main() {
  group('tryNormalizeEthiopianPhone', () {
    test('normalizes local 0-prefix', () {
      final phone = tryNormalizeEthiopianPhone('0911234567');
      expect(phone?.msisdn, '251911234567');
      expect(phone?.e164, '+251911234567');
      expect(phone?.national, '0911234567');
    });

    test('normalizes nine-digit mobile', () {
      final phone = tryNormalizeEthiopianPhone('911234567');
      expect(phone?.msisdn, '251911234567');
    });

    test('normalizes E.164 input', () {
      final phone = tryNormalizeEthiopianPhone('+251911234567');
      expect(phone?.e164, '+251911234567');
    });

    test('rejects invalid prefix', () {
      expect(tryNormalizeEthiopianPhone('0811234567'), isNull);
      expect(tryNormalizeEthiopianPhone('not-a-phone'), isNull);
    });
  });
}
