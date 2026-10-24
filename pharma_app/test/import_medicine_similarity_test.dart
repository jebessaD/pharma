import 'package:flutter_test/flutter_test.dart';
import 'package:pharma_app/features/inventory_import/import_medicine_similarity.dart';

void main() {
  group('parseImportQty', () {
    test('parses comma-separated quantities', () {
      expect(parseImportQty('1,200'), 1200);
      expect(parseImportQty('10'), 10);
    });
  });

  group('scoreMedicineSimilarity', () {
    test('exact generic scores highest', () {
      final score = scoreMedicineSimilarity('Amoxicillin 400mg', {
        'name': 'Amoxil',
        'generic_name': 'Amoxicillin 400mg',
      });
      expect(score, greaterThanOrEqualTo(900));
    });

    test('short name inside long query scores low', () {
      final short = scoreMedicineSimilarity('Ketoconazole 200mg Tablet', {
        'name': 'OCID',
        'generic_name': null,
      });
      final good = scoreMedicineSimilarity('Ketoconazole 200mg Tablet', {
        'name': 'Ketoconazole 200mg',
        'generic_name': 'Ketoconazole',
      });
      expect(good, greaterThan(short));
    });

    test('shouldAutoLinkSimilarity requires clear lead', () {
      expect(shouldAutoLinkSimilarity([920, 400]), isTrue);
      expect(shouldAutoLinkSimilarity([800, 780]), isFalse);
    });
  });
}
