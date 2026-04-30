import 'package:flutter_test/flutter_test.dart';
import 'package:pharma_app/features/inventory/stock_in_row_state.dart';

void main() {
  final today = DateTime(2026, 5, 1);

  test('returns empty for untouched row', () {
    final state = stockInRowState(
      const StockInDraftRow(
        medicineId: null,
        batchNo: '',
        expiryText: '',
        qtyText: '',
      ),
      today,
    );
    expect(state, StockInRowState.empty);
  });

  test('returns missing when expiry is absent (batch optional)', () {
    final state = stockInRowState(
      const StockInDraftRow(
        medicineId: 'm1',
        batchNo: '',
        expiryText: '',
        qtyText: '10',
      ),
      today,
    );
    expect(state, StockInRowState.missing);
  });

  test('returns invalid for non-positive qty', () {
    final state = stockInRowState(
      const StockInDraftRow(
        medicineId: 'm1',
        batchNo: 'B-001',
        expiryText: '10/05/2026',
        qtyText: '0',
      ),
      today,
    );
    expect(state, StockInRowState.invalid);
  });

  test('returns ready for complete valid row', () {
    final state = stockInRowState(
      const StockInDraftRow(
        medicineId: 'm1',
        batchNo: 'B-001',
        expiryText: '10/05/2026',
        qtyText: '12',
      ),
      today,
    );
    expect(state, StockInRowState.ready);
  });

  test('returns ready without batch number', () {
    final state = stockInRowState(
      const StockInDraftRow(
        medicineId: 'm1',
        batchNo: '',
        expiryText: '10/05/2026',
        qtyText: '5',
      ),
      today,
    );
    expect(state, StockInRowState.ready);
  });
}
