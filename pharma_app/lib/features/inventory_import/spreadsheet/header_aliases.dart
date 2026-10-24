import 'spreadsheet_models.dart';

String normalizeHeader(String raw) {
  return raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s_\-/]+'), ' ')
      .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

const Map<ImportCanonicalField, List<String>> kHeaderAliases = {
  ImportCanonicalField.name: [
    'name',
    'medicine',
    'medicine name',
    'product',
    'product name',
    'item',
    'item name',
    'brand',
    'trade name',
    'drug name',
    'description',
  ],
  ImportCanonicalField.genericName: [
    'generic',
    'generic name',
    'inn',
    'active ingredient',
    'composition',
  ],
  ImportCanonicalField.manualCode: [
    'code',
    'item code',
    'item no',
    'item number',
    'sku',
    'product code',
    'stock code',
    'article',
    'article no',
    'supplier code',
  ],
  ImportCanonicalField.barcode: [
    'barcode',
    'ean',
    'upc',
    'gtin',
    'bar code',
  ],
  ImportCanonicalField.batchNo: [
    'batch',
    'batch no',
    'batch number',
    'lot',
    'lot no',
    'lot number',
  ],
  ImportCanonicalField.expiryDate: [
    'expiry',
    'expiry date',
    'exp',
    'exp date',
    'expiration',
    'best before',
    'use by',
  ],
  ImportCanonicalField.quantity: [
    'qty',
    'quantity',
    'qty received',
    'stock qty',
    'units',
    'pcs',
    'amount',
  ],
  ImportCanonicalField.unitCost: [
    'unit cost',
    'cost',
    'buy',
    'buy price',
    'purchase price',
    'buying price',
    'cost price',
    'rate',
  ],
  ImportCanonicalField.sellPrice: [
    'sell',
    'sell price',
    'selling price',
    'sp',
    'mrp',
    'retail',
  ],
  ImportCanonicalField.categoryKey: ['category', 'type', 'product type'],
  ImportCanonicalField.subcategory: [
    'subcategory',
    'class',
    'therapeutic class',
  ],
  ImportCanonicalField.strength: ['strength', 'potency', 'dose strength'],
  ImportCanonicalField.dosageForm: ['form', 'dosage form', 'unit form'],
  ImportCanonicalField.presentation: [
    'presentation',
    'pack',
    'pack size',
    'packaging',
  ],
  ImportCanonicalField.company: ['company', 'manufacturer', 'mfr', 'maker'],
  ImportCanonicalField.country: ['country', 'origin', 'country of origin'],
  ImportCanonicalField.reorderLevel: [
    'reorder',
    'reorder level',
    'min stock',
    'minimum stock',
  ],
};

bool headerLooksLikeMoney(String header) {
  final n = normalizeHeader(header);
  if (n.contains('etb') ||
      n.contains('br') ||
      n.contains('birr') ||
      n.contains('usd') ||
      n.contains('money') ||
      n.contains('currency')) {
    return true;
  }
  if (n == 'price' || n.endsWith(' price') || n.startsWith('price ')) {
    return true;
  }
  if (n.contains('amount') &&
      (n.contains('etb') ||
          n.contains('paid') ||
          n.contains('total') ||
          n.contains('value') ||
          n.contains('money'))) {
    return true;
  }
  return false;
}

bool cellsLookLikeMoney(List<String> samples) {
  var hits = 0;
  for (final s in samples) {
    final t = s.trim().toLowerCase();
    if (t.isEmpty) continue;
    if (RegExp(r'(etb|br\.?|birr|\$|usd)').hasMatch(t)) hits++;
  }
  return hits >= 2 || (samples.where((s) => s.trim().isNotEmpty).length <= 3 && hits >= 1);
}
