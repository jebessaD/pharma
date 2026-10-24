import 'package:flutter_test/flutter_test.dart';
import 'package:pharma_app/core/medicine/medicine_name_normalizer.dart';

void main() {
  test('normalizeMedicineMatchKey lowercases and strips punctuation', () {
    expect(
      normalizeMedicineMatchKey('Amoxil-400mg Tab (10*10)'),
      'amoxil 400mg tab 10*10',
    );
  });

  test('normalizeMedicineMatchKeyLoose removes pack sizes', () {
    expect(
      normalizeMedicineMatchKeyLoose('Paracetamol 500mg Tab 10x10'),
      'paracetamol 500mg tab',
    );
  });

  test('medicineMatchKeys includes name generic and combined', () {
    final keys = medicineMatchKeys(
      name: 'Amoxil 400mg Tab 10*10',
      genericName: 'Amoxicillin',
    );
    expect(keys, contains('amoxil 400mg tab 10*10'));
    expect(keys, contains('amoxicillin'));
    expect(keys, contains('amoxil 400mg tab 10*10 amoxicillin'));
  });
}
