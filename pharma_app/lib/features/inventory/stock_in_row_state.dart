import '../../core/widgets/slash_dd_mm_yyyy_input.dart';

enum StockInRowState { empty, missing, invalid, ready }

class StockInDraftRow {
  const StockInDraftRow({
    required this.medicineId,
    required this.batchNo,
    required this.expiryText,
    required this.qtyText,
  });

  final String? medicineId;
  final String batchNo;
  final String expiryText;
  final String qtyText;
}

StockInRowState stockInRowState(StockInDraftRow row, DateTime today) {
  final isEmpty =
      row.medicineId == null &&
      row.batchNo.trim().isEmpty &&
      row.qtyText.trim().isEmpty &&
      row.expiryText.trim().isEmpty;
  if (isEmpty) return StockInRowState.empty;

  final qty = num.tryParse(row.qtyText.trim());
  if (row.medicineId == null || row.expiryText.trim().isEmpty || qty == null) {
    return StockInRowState.missing;
  }

  final expErr = slashDdMmYyyyExpiryError(row.expiryText.trim(), today);
  if (qty <= 0 || expErr != null) return StockInRowState.invalid;
  return StockInRowState.ready;
}
