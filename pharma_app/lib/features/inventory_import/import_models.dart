import 'dart:convert';

/// Which downstream flow the imported rows should feed into.
enum ImportMode {
  /// Creates a purchase draft (supplier + invoice) to be received later.
  purchaseInvoice,

  /// Commits directly through `bulk_stock_in`.
  directStockIn,
}

extension ImportModeX on ImportMode {
  String get wire => switch (this) {
    ImportMode.purchaseInvoice => 'purchase_invoice',
    ImportMode.directStockIn => 'direct_stock_in',
  };

  bool get isPurchase => this == ImportMode.purchaseInvoice;
}

/// Header fields extracted from the document (all optional).
class ExtractedHeader {
  const ExtractedHeader({
    this.supplierName,
    this.customerName,
    this.invoiceNo,
    this.invoiceDate,
    this.currency,
    this.grandTotal,
  });

  final String? supplierName;
  final String? customerName;
  final String? invoiceNo;
  final String? invoiceDate;
  final String? currency;
  final num? grandTotal;

  factory ExtractedHeader.fromJson(Map<String, dynamic> json) {
    return ExtractedHeader(
      supplierName: json['supplier_name'] as String?,
      customerName: json['customer_name'] as String?,
      invoiceNo: json['invoice_no'] as String?,
      invoiceDate: json['invoice_date'] as String?,
      currency: json['currency'] as String?,
      grandTotal: json['grand_total'] as num?,
    );
  }
}

/// Per-field extraction confidence (0..1).
class FieldConfidence {
  const FieldConfidence({
    this.description = 0,
    this.name = 0,
    this.genericName = 0,
    this.batchNo = 0,
    this.expiryDate = 0,
    this.quantity = 0,
    this.unitCost = 0,
  });

  final double description;
  final double name;
  final double genericName;
  final double batchNo;
  final double expiryDate;
  final double quantity;
  final double unitCost;

  factory FieldConfidence.fromJson(Map<String, dynamic> json) {
    double d(Object? v) {
      final n = (v is num) ? v.toDouble() : double.tryParse('${v ?? ''}');
      if (n == null) return 0;
      return n.clamp(0, 1).toDouble();
    }

    return FieldConfidence(
      description: d(json['description'] ?? json['name']),
      name: d(json['name']),
      genericName: d(json['generic_name']),
      batchNo: d(json['batch_no']),
      expiryDate: d(json['expiry_date']),
      quantity: d(json['quantity']),
      unitCost: d(json['unit_cost']),
    );
  }
}

/// A single extracted line item, exactly as returned by the extractor.
class ExtractedLine {
  const ExtractedLine({
    required this.rowIndex,
    this.description,
    this.name,
    this.genericName,
    this.supplierCode,
    this.manualCode,
    this.barcode,
    this.reorderLevel,
    this.categoryKey,
    this.subcategory,
    this.strength,
    this.dosageForm,
    this.presentation,
    this.batchNo,
    this.expiryDate,
    this.expiryDateRaw,
    this.uom,
    this.quantity,
    this.unitCost,
    this.sellPrice,
    this.lineTotal,
    this.confidence = const FieldConfidence(),
    this.warnings = const [],
  });

  final int rowIndex;

  /// Display summary: name plus generic in parentheses when known.
  final String? description;

  /// Brand/trade line including strength, form, and pack (e.g. "Amoxil 400mg Tab 10*10").
  final String? name;

  /// Active ingredient / INN when present.
  final String? genericName;

  /// Legacy alias for [manualCode] from older extractor payloads.
  final String? supplierCode;

  /// Internal item / stock code from the document.
  final String? manualCode;
  final String? barcode;
  final num? reorderLevel;

  /// One of: medicine, consumable, medical_device, supplements, personal_care,
  /// diagnostics, other.
  final String? categoryKey;
  final String? subcategory;
  final String? strength;
  final String? dosageForm;
  final String? presentation;
  final String? batchNo;

  /// ISO `YYYY-MM-DD` when the extractor could normalize it, else null.
  final String? expiryDate;
  final String? expiryDateRaw;
  final String? uom;
  final num? quantity;
  final num? unitCost;
  final num? sellPrice;
  final num? lineTotal;
  final FieldConfidence confidence;
  final List<String> warnings;

  /// Resolved manual code (prefers [manualCode], falls back to [supplierCode]).
  String? get resolvedManualCode {
    final manual = manualCode?.trim();
    if (manual != null && manual.isNotEmpty) return manual;
    final supplier = supplierCode?.trim();
    if (supplier != null && supplier.isNotEmpty) return supplier;
    return null;
  }

  /// Product name for catalog create/match (strength and pack stay here).
  String? get resolvedName {
    final n = name?.trim();
    if (n != null && n.isNotEmpty) return n;
    final d = description?.trim();
    if (d != null && d.isNotEmpty) return d;
    return null;
  }

  factory ExtractedLine.fromJson(Map<String, dynamic> json) {
    final manualCode =
        json['manual_code'] as String? ?? json['supplier_code'] as String?;
    final name = json['name'] as String?;
    final genericName = json['generic_name'] as String?;
    final description =
        json['description'] as String? ??
        _buildDescription(name, genericName);

    return ExtractedLine(
      rowIndex: (json['row_index'] as num?)?.toInt() ?? 0,
      description: description,
      name: name,
      genericName: genericName,
      supplierCode: json['supplier_code'] as String?,
      manualCode: manualCode,
      barcode: json['barcode'] as String?,
      reorderLevel: json['reorder_level'] as num?,
      categoryKey: json['category_key'] as String?,
      subcategory: json['subcategory'] as String?,
      strength: json['strength'] as String?,
      dosageForm: json['dosage_form'] as String?,
      presentation: json['presentation'] as String?,
      batchNo: json['batch_no'] as String?,
      expiryDate: json['expiry_date'] as String?,
      expiryDateRaw: json['expiry_date_raw'] as String?,
      uom: json['uom'] as String?,
      quantity: json['quantity'] as num?,
      unitCost: json['unit_cost'] as num?,
      sellPrice: json['sell_price'] as num?,
      lineTotal: json['line_total'] as num?,
      confidence: FieldConfidence.fromJson(
        (json['field_confidence'] as Map?)?.cast<String, dynamic>() ??
            const {},
      ),
      warnings:
          (json['warnings'] as List?)
              ?.map((e) => '$e')
              .where((e) => e.isNotEmpty)
              .toList() ??
          const [],
    );
  }
}

String? _buildDescription(String? name, String? genericName) {
  final n = name?.trim();
  final g = genericName?.trim();
  if (n != null && n.isNotEmpty && g != null && g.isNotEmpty) {
    return '$g ($n)';
  }
  if (n != null && n.isNotEmpty) return n;
  return null;
}

/// Full extraction result returned by the `inventory-import-extract` function.
class ExtractionResult {
  const ExtractionResult({
    required this.documentType,
    required this.isSupported,
    required this.header,
    required this.lines,
    this.ignoredSummary = const [],
    this.documentWarnings = const [],
    this.model,
    this.elapsedMs,
  });

  final String documentType;
  final bool isSupported;
  final ExtractedHeader header;
  final List<ExtractedLine> lines;
  final List<String> ignoredSummary;
  final List<String> documentWarnings;
  final String? model;
  final int? elapsedMs;

  factory ExtractionResult.fromResponse(Map<String, dynamic> json) {
    final result =
        (json['result'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ExtractionResult(
      documentType: result['document_type'] as String? ?? 'unknown',
      isSupported: result['is_supported_inventory_document'] == true,
      header: ExtractedHeader.fromJson(
        (result['header'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
      lines:
          (result['lines'] as List?)
              ?.map(
                (e) => ExtractedLine.fromJson(
                  (e as Map).cast<String, dynamic>(),
                ),
              )
              .toList() ??
          const [],
      ignoredSummary:
          (result['ignored_content_summary'] as List?)
              ?.map((e) => '$e')
              .toList() ??
          const [],
      documentWarnings:
          (result['document_warnings'] as List?)
              ?.map((e) => '$e')
              .toList() ??
          const [],
      model: json['model'] as String?,
      elapsedMs: (json['elapsed_ms'] as num?)?.toInt(),
    );
  }

  static ExtractionResult parse(Object? data) {
    final map = _asMap(data);
    if (map == null) {
      throw const ImportExtractionException('extract_unreadable');
    }
    if (map['error'] != null) {
      throw ImportExtractionException(
        map['error'] as String? ?? 'extract_failed',
        detail: map['detail'] as String?,
      );
    }
    return ExtractionResult.fromResponse(map);
  }
}

Map<String, dynamic>? _asMap(Object? data) {
  if (data is Map<String, dynamic>) return data;
  if (data is Map) return data.cast<String, dynamic>();
  if (data is String && data.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(data);
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Thrown when the extractor returns an error or unreadable payload.
class ImportExtractionException implements Exception {
  const ImportExtractionException(
    this.code, {
    this.detail,
    this.keysTried,
    this.failoverAttempts,
  });

  final String code;
  final String? detail;

  /// How many API keys the server attempted (from edge function failover).
  final int? keysTried;

  /// Total failover attempts logged by the server.
  final int? failoverAttempts;

  @override
  String toString() => 'ImportExtractionException($code, $detail)';
}
