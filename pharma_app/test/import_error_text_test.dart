import 'package:flutter_test/flutter_test.dart';
import 'package:pharma_app/features/inventory_import/import_error_text.dart';
import 'package:pharma_app/features/inventory_import/import_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('maps known extraction codes to friendly text', () {
    expect(
      importErrorText(const ImportExtractionException('quota_exceeded')),
      contains('daily limit'),
    );
    expect(
      importErrorText(
        const ImportExtractionException(
          'unsupported_document',
          detail: 'no_inventory_table_found',
        ),
      ),
      contains('No medicine table'),
    );
  });

  test('parses FunctionException JSON body', () {
    final ex = FunctionException(
      status: 422,
      details: '{"error":"extract_unreadable","detail":"no_json"}',
    );
    expect(
      importErrorText(ex),
      contains('could not read the table'),
    );
  });

  test('maps 404 to deploy message', () {
    final ex = FunctionException(status: 404, details: {});
    expect(importErrorText(ex), contains('not deployed'));
  });

  test('maps HTTP status when body has no error code', () {
    final ex = FunctionException(status: 429, details: {});
    expect(importErrorText(ex), contains('daily limit'));
  });
}
