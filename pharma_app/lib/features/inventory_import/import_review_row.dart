import 'package:flutter/material.dart';

import '../../core/medicine/medicine_display.dart';
import '../../core/widgets/slash_dd_mm_yyyy_input.dart';
import 'import_medicine_matcher.dart';
import 'import_medicine_similarity.dart';
import 'import_models.dart';

/// Status of a review row, used for the colored indicator and confirm gating.
enum ImportRowStatus {
  /// Matched to a medicine and required fields valid.
  ready,

  /// Multiple catalog matches; user must pick one.
  needsChoice,

  /// No match; will be created as a new medicine on confirm.
  newMedicine,

  /// Missing/invalid required fields (qty or expiry).
  invalid,
}

/// Editable per-row state backed by controllers, seeded from an [ExtractedLine].
class ImportReviewRow {
  ImportReviewRow.fromExtracted(this.source)
    : name = TextEditingController(text: source.resolvedName ?? ''),
      genericName = TextEditingController(text: source.genericName ?? ''),
      batchNo = TextEditingController(text: source.batchNo ?? ''),
      expiry = TextEditingController(
        text:
            _isoToSlash(source.expiryDate) ??
            _rawExpiryToSlash(source.expiryDateRaw),
      ),
      qty = TextEditingController(text: _numText(source.quantity)),
      unitCost = TextEditingController(text: _numText(source.unitCost)),
      sellPrice = TextEditingController(text: _numText(source.sellPrice)),
      manualCode = TextEditingController(text: source.resolvedManualCode ?? ''),
      barcode = TextEditingController(text: source.barcode ?? ''),
      reorderLevel = TextEditingController(
        text: source.reorderLevel != null && source.reorderLevel! > 0
            ? _numText(source.reorderLevel)
            : '1',
      ) {
    newCategoryKey = _validCategoryKey(source.categoryKey);
  }

  final ExtractedLine source;

  final TextEditingController name;
  final TextEditingController genericName;
  final TextEditingController batchNo;
  final TextEditingController expiry;
  final TextEditingController qty;
  final TextEditingController unitCost;
  final TextEditingController sellPrice;
  final TextEditingController manualCode;
  final TextEditingController barcode;
  final TextEditingController reorderLevel;

  /// Resolved catalog medicine id once matched or created.
  String? medicineId;

  /// Display label for the currently linked medicine.
  String? medicineLabel;

  /// Latest match result (candidates for the "choose" picker).
  MedicineMatch? match;

  /// When true, this row will create a new medicine on confirm.
  bool createNew = false;

  /// True when this confirm pass created the medicine (for import undo tracking).
  bool medicineCreated = false;

  /// Category for a newly created medicine.
  String newCategoryKey = 'medicine';

  bool removed = false;

  List<String> get displayWarnings => source.warnings
      .where((w) => w.trim().toLowerCase() != 'ambiguous_date_order')
      .toList();

  void applyMatch(MedicineMatch result) {
    match = result;
    switch (result.outcome) {
      case MatchOutcome.single:
        final m = result.best!;
        _linkMedicineFields(m);
      case MatchOutcome.multiple:
        medicineId = null;
        medicineLabel = null;
        createNew = true;
      case MatchOutcome.none:
        medicineId = null;
        medicineLabel = null;
        createNew = true;
    }
  }

  void selectMedicine(Map<String, dynamic> medicine) {
    _linkMedicineFields(medicine);
    match = MedicineMatch(
      outcome: MatchOutcome.single,
      candidates: [medicine],
    );
  }

  void _linkMedicineFields(Map<String, dynamic> medicine) {
    medicineId = medicine['id'] as String?;
    medicineLabel = medicinePrimaryLabel(medicine);
    createNew = false;

    final medName = medicine['name'] as String?;
    if (medName != null && medName.trim().isNotEmpty) {
      name.text = medName.trim();
    }
    final generic = medicine['generic_name'] as String?;
    if (generic != null && generic.trim().isNotEmpty) {
      genericName.text = generic.trim();
    }
  }

  void markCreated(String id, String label) {
    medicineId = id;
    medicineLabel = label;
    createNew = false;
    medicineCreated = true;
    match = MedicineMatch(
      outcome: MatchOutcome.single,
      candidates: [
        {'id': id, 'name': label},
      ],
    );
  }

  ImportRowStatus status(DateTime today) {
    final q = parseImportQty(qty.text);
    final expText = expiry.text.trim();
    final expErr = slashDdMmYyyyExpiryError(expText, today);
    final fieldsValid = q != null && q > 0 && expErr == null;

    if (!fieldsValid) return ImportRowStatus.invalid;
    if (medicineId != null) return ImportRowStatus.ready;
    if (createNew ||
        match == null ||
        match?.outcome == MatchOutcome.none ||
        match?.outcome == MatchOutcome.multiple) {
      return ImportRowStatus.newMedicine;
    }
    return ImportRowStatus.needsChoice;
  }

  /// Specific validation hint for invalid rows (qty/expiry).
  String invalidHint(DateTime today) {
    final q = parseImportQty(qty.text);
    if (q == null || q <= 0) return 'Enter quantity';
    final expErr = slashDdMmYyyyExpiryError(expiry.text.trim(), today);
    return expErr ?? 'Enter qty and expiry';
  }

  void clearMedicineLink() {
    medicineId = null;
    medicineLabel = null;
    createNew = true;
  }

  bool isCommittable(DateTime today) {
    final s = status(today);
    return s == ImportRowStatus.ready || s == ImportRowStatus.newMedicine;
  }

  void dispose() {
    name.dispose();
    genericName.dispose();
    batchNo.dispose();
    expiry.dispose();
    qty.dispose();
    unitCost.dispose();
    sellPrice.dispose();
    manualCode.dispose();
    barcode.dispose();
    reorderLevel.dispose();
  }

  static String _numText(num? v) {
    if (v == null) return '';
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  static String? _isoToSlash(String? iso) {
    if (iso == null || iso.isEmpty) return null;
    final parts = iso.split('-');
    if (parts.length != 3) return null;
    final y = parts[0];
    final m = parts[1].padLeft(2, '0');
    final d = parts[2].padLeft(2, '0');
    if (y.length != 4) return null;
    return '$d/$m/$y';
  }

  static String _rawExpiryToSlash(String? raw) {
    if (raw == null) return '';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    // Only prefill when the raw string already looks like a full DD/MM/YYYY.
    if (digits.length == 8 && raw.contains('/')) {
      return raw.trim();
    }
    return '';
  }

  static String _validCategoryKey(String? key) {
    const allowed = {
      'medicine',
      'consumable',
      'medical_device',
      'supplements',
      'personal_care',
      'diagnostics',
      'other',
    };
    final k = key?.trim().toLowerCase();
    if (k != null && allowed.contains(k)) return k;
    return 'medicine';
  }
}
