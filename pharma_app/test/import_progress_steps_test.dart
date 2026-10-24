import 'package:flutter_test/flutter_test.dart';
import 'package:pharma_app/features/inventory_import/import_progress_steps.dart';

void main() {
  group('importSumLineTotals', () {
    test('prefers qty × unit cost over extracted line total', () {
      final total = importSumLineTotals([
        (qty: 10, unitCost: 5, lineTotal: 999),
        (qty: 2, unitCost: 3.5, lineTotal: null),
      ]);
      expect(total, 57);
    });

    test('falls back to line total when qty or cost missing', () {
      final total = importSumLineTotals([
        (qty: null, unitCost: 5, lineTotal: 20),
        (qty: 3, unitCost: null, lineTotal: 15),
      ]);
      expect(total, 35);
    });
  });

  group('importTotalsMismatch', () {
    test('returns false when document total missing', () {
      expect(
        importTotalsMismatch(documentTotal: null, linesTotal: 100),
        isFalse,
      );
    });

    test('returns true when difference exceeds tolerance', () {
      expect(
        importTotalsMismatch(documentTotal: 500, linesTotal: 480),
        isTrue,
      );
    });

    test('returns false within one unit tolerance', () {
      expect(
        importTotalsMismatch(documentTotal: 500, linesTotal: 499.5),
        isFalse,
      );
    });
  });

  group('importFormatTotal', () {
    test('drops decimals for whole numbers', () {
      expect(importFormatTotal(120), '120');
      expect(importFormatTotal(120.0), '120');
    });

    test('keeps two decimals otherwise', () {
      expect(importFormatTotal(120.5), '120.50');
    });
  });
}
