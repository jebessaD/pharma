import 'package:flutter_test/flutter_test.dart';
import 'package:pharma_app/features/inventory_import/import_medicine_matcher.dart';
import 'package:pharma_app/features/inventory_import/import_models.dart';
import 'package:pharma_app/features/inventory_import/import_review_row.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final today = DateTime(2026, 5, 1);

  ExtractedLine line({
    String? description = 'PANTOPRAZOLE 40MG',
    String? expiryIso = '2028-01-10',
    String? expiryRaw,
    num? quantity = 5,
    num? unitCost,
    num? sellPrice,
    String? code,
    String? barcode,
    List<String> warnings = const [],
  }) {
    return ExtractedLine(
      rowIndex: 1,
      description: description,
      supplierCode: code,
      barcode: barcode,
      expiryDate: expiryIso,
      expiryDateRaw: expiryRaw,
      quantity: quantity,
      unitCost: unitCost,
      sellPrice: sellPrice,
      warnings: warnings,
    );
  }

  test('prefills expiry from ISO as DD/MM/YYYY', () {
    final row = ImportReviewRow.fromExtracted(line());
    expect(row.expiry.text, '10/01/2028');
    row.dispose();
  });

  test('invalid when quantity missing', () {
    final row = ImportReviewRow.fromExtracted(line(quantity: null));
    expect(row.status(today), ImportRowStatus.invalid);
    row.dispose();
  });

  test('leaves sell price empty when not extracted', () {
    final row = ImportReviewRow.fromExtracted(line(unitCost: 101));
    expect(row.sellPrice.text, '');
    row.dispose();
  });

  test('keeps extracted sell price over recommended price', () {
    final row = ImportReviewRow.fromExtracted(
      line(unitCost: 101, sellPrice: 140),
    );
    expect(row.sellPrice.text, '140');
    row.dispose();
  });

  test('filters legacy ambiguous date warning', () {
    final row = ImportReviewRow.fromExtracted(
      line(warnings: ['ambiguous_date_order', 'rotated_image']),
    );
    expect(row.displayWarnings, ['rotated_image']);
    row.dispose();
  });

  test('invalid when expiry unusable', () {
    final row = ImportReviewRow.fromExtracted(
      line(expiryIso: null, expiryRaw: 'Jan 2028'),
    );
    expect(row.status(today), ImportRowStatus.invalid);
    row.dispose();
  });

  test('newMedicine when no match and fields valid', () {
    final row = ImportReviewRow.fromExtracted(line());
    row.applyMatch(
      const MedicineMatch(outcome: MatchOutcome.none, candidates: []),
    );
    expect(row.status(today), ImportRowStatus.newMedicine);
    row.dispose();
  });

  test('newMedicine when multiple candidates (no auto-link)', () {
    final row = ImportReviewRow.fromExtracted(line());
    row.applyMatch(
      const MedicineMatch(
        outcome: MatchOutcome.multiple,
        candidates: [
          {'id': 'a', 'name': 'A'},
          {'id': 'b', 'name': 'B'},
        ],
      ),
    );
    expect(row.status(today), ImportRowStatus.newMedicine);
    expect(row.isCommittable(today), isTrue);
    row.dispose();
  });

  test('ready when single match and fields valid', () {
    final row = ImportReviewRow.fromExtracted(line());
    row.applyMatch(
      const MedicineMatch(
        outcome: MatchOutcome.single,
        candidates: [
          {'id': 'a', 'name': 'Pantoprazole', 'generic_name': 'Pantoprazole'},
        ],
      ),
    );
    expect(row.medicineId, 'a');
    expect(row.name.text, 'Pantoprazole');
    expect(row.genericName.text, 'Pantoprazole');
    expect(row.status(today), ImportRowStatus.ready);
    expect(row.isCommittable(today), isTrue);
    row.dispose();
  });

  test('selectMedicine fills name and generic and marks matched', () {
    final row = ImportReviewRow.fromExtracted(line(description: 'Wrong name'));
    row.applyMatch(
      const MedicineMatch(outcome: MatchOutcome.none, candidates: []),
    );
    row.selectMedicine({
      'id': 'x',
      'name': 'Amoxil 400mg',
      'generic_name': 'Amoxicillin',
    });
    expect(row.medicineId, 'x');
    expect(row.medicineLabel, 'Amoxicillin');
    expect(row.name.text, 'Amoxil 400mg');
    expect(row.genericName.text, 'Amoxicillin');
    expect(row.createNew, isFalse);
    expect(row.match?.outcome, MatchOutcome.single);
    expect(row.status(today), ImportRowStatus.ready);
    row.dispose();
  });

  test('markCreated makes row ready', () {
    final row = ImportReviewRow.fromExtracted(line());
    row.applyMatch(
      const MedicineMatch(outcome: MatchOutcome.none, candidates: []),
    );
    row.markCreated('new-id', 'New Med');
    expect(row.medicineId, 'new-id');
    expect(row.status(today), ImportRowStatus.ready);
    row.dispose();
  });
}
