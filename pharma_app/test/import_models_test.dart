import 'package:flutter_test/flutter_test.dart';
import 'package:pharma_app/features/inventory_import/import_models.dart';

void main() {
  group('ExtractionResult.parse', () {
    test('parses a well-formed success payload', () {
      final data = {
        'mode': 'purchase_invoice',
        'model': 'gemini-2.5-flash',
        'elapsed_ms': 1200,
        'result': {
          'document_type': 'supplier_invoice',
          'is_supported_inventory_document': true,
          'header': {
            'supplier_name': 'Mebratu Legesse',
            'invoice_no': '00008657',
            'invoice_date': '2026-05-16',
            'grand_total': 22964,
          },
          'lines': [
            {
              'row_index': 1,
              'description': 'PANTOPRAZOLE 40MG',
              'supplier_code': 'P010',
              'batch_no': 'T4045',
              'expiry_date': '2028-01-10',
              'expiry_date_raw': '10/01/2028',
              'uom': 'Pkt',
              'quantity': 1,
              'unit_cost': 1236,
              'line_total': 1236,
              'field_confidence': {
                'description': 0.9,
                'quantity': 0.95,
              },
              'warnings': ['ambiguous_date_order'],
            },
          ],
          'ignored_content_summary': ['watermark ATTACHMENT'],
          'document_warnings': [],
        },
      };
      final result = ExtractionResult.parse(data);
      expect(result.isSupported, isTrue);
      expect(result.header.supplierName, 'Mebratu Legesse');
      expect(result.header.invoiceNo, '00008657');
      expect(result.lines, hasLength(1));
      final line = result.lines.first;
      expect(line.description, 'PANTOPRAZOLE 40MG');
      expect(line.supplierCode, 'P010');
      expect(line.expiryDate, '2028-01-10');
      expect(line.quantity, 1);
      expect(line.confidence.description, closeTo(0.9, 1e-9));
      expect(line.warnings, contains('ambiguous_date_order'));
      expect(result.ignoredSummary, contains('watermark ATTACHMENT'));
    });

    test('throws ImportExtractionException with code on error payload', () {
      final data = {'error': 'quota_exceeded', 'detail': null};
      expect(
        () => ExtractionResult.parse(data),
        throwsA(
          isA<ImportExtractionException>().having(
            (e) => e.code,
            'code',
            'quota_exceeded',
          ),
        ),
      );
    });

    test('throws on null/unreadable payload', () {
      expect(
        () => ExtractionResult.parse(null),
        throwsA(isA<ImportExtractionException>()),
      );
    });

    test('parses structured medicine fields', () {
      final line = ExtractedLine.fromJson({
        'row_index': 1,
        'name': 'Amoxil 400mg Tab 10*10',
        'generic_name': 'Amoxicillin',
        'manual_code': 'P010',
        'barcode': '1234567890123',
        'category_key': 'medicine',
        'subcategory': 'ANTI-INFECTIVE',
        'reorder_level': 5,
        'quantity': 2,
      });
      expect(line.resolvedName, 'Amoxil 400mg Tab 10*10');
      expect(line.genericName, 'Amoxicillin');
      expect(line.description, 'Amoxil 400mg Tab 10*10 (Amoxicillin)');
      expect(line.resolvedManualCode, 'P010');
      expect(line.categoryKey, 'medicine');
      expect(line.reorderLevel, 5);
    });

    test('builds description from legacy payload', () {
      final line = ExtractedLine.fromJson({
        'row_index': 1,
        'description': 'PANTOPRAZOLE 40MG',
        'supplier_code': 'P010',
      });
      expect(line.resolvedName, 'PANTOPRAZOLE 40MG');
      expect(line.resolvedManualCode, 'P010');
    });

    test('parses a JSON string payload', () {
      const raw =
          '{"result":{"document_type":"stock_table",'
          '"is_supported_inventory_document":true,"header":{},'
          '"lines":[{"row_index":1,"description":"X","quantity":3}]}}';
      final result = ExtractionResult.parse(raw);
      expect(result.lines, hasLength(1));
      expect(result.lines.first.quantity, 3);
    });
  });

  group('ImportModeX', () {
    test('maps wire values', () {
      expect(ImportMode.purchaseInvoice.wire, 'purchase_invoice');
      expect(ImportMode.directStockIn.wire, 'direct_stock_in');
      expect(ImportMode.purchaseInvoice.isPurchase, isTrue);
      expect(ImportMode.directStockIn.isPurchase, isFalse);
    });
  });

  group('FieldConfidence', () {
    test('clamps out-of-range confidence', () {
      final c = FieldConfidence.fromJson({
        'description': 2.0,
        'quantity': -1,
      });
      expect(c.description, 1.0);
      expect(c.quantity, 0.0);
    });
  });
}
