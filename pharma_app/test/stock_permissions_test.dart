import 'package:flutter_test/flutter_test.dart';
import 'package:pharma_app/core/roles/stock_permissions.dart';

void main() {
  group('canAddStockInForRole', () {
    test('allows owner and admin roles', () {
      expect(canAddStockInForRole('owner'), isTrue);
      expect(canAddStockInForRole('admin'), isTrue);
      expect(canAddStockInForRole(' Owner '), isTrue);
    });

    test('blocks pharmacy staff roles', () {
      expect(canAddStockInForRole('pharmacist'), isFalse);
      expect(canAddStockInForRole('cashier'), isFalse);
      expect(canAddStockInForRole('seller'), isFalse);
      expect(canAddStockInForRole(null), isFalse);
    });
  });
}
