enum OfflineSaleSyncStatus { pending, syncing, synced, failed }

class OfflineSaleDto {
  const OfflineSaleDto({
    required this.localOperationId,
    required this.branchId,
    required this.paymentMethod,
    required this.discountTotal,
    required this.items,
    required this.createdAt,
    required this.retryCount,
    required this.status,
    this.referenceNo,
    this.lastError,
    this.syncedSaleId,
  });

  final String localOperationId;
  final String branchId;
  final String paymentMethod;
  final String? referenceNo;
  final num discountTotal;
  final List<Map<String, dynamic>> items;
  final DateTime createdAt;
  final int retryCount;
  final OfflineSaleSyncStatus status;
  final String? lastError;
  final String? syncedSaleId;

  OfflineSaleDto copyWith({
    int? retryCount,
    OfflineSaleSyncStatus? status,
    String? lastError,
    String? syncedSaleId,
  }) {
    return OfflineSaleDto(
      localOperationId: localOperationId,
      branchId: branchId,
      paymentMethod: paymentMethod,
      referenceNo: referenceNo,
      discountTotal: discountTotal,
      items: items,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      status: status ?? this.status,
      lastError: lastError,
      syncedSaleId: syncedSaleId ?? this.syncedSaleId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'local_operation_id': localOperationId,
      'branch_id': branchId,
      'payment_method': paymentMethod,
      'reference_no': referenceNo,
      'discount_total': discountTotal,
      'items': items,
      'created_at': createdAt.toIso8601String(),
      'retry_count': retryCount,
      'status': status.name,
      'last_error': lastError,
      'synced_sale_id': syncedSaleId,
    };
  }

  static OfflineSaleDto fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    return OfflineSaleDto(
      localOperationId: json['local_operation_id'] as String,
      branchId: json['branch_id'] as String,
      paymentMethod: json['payment_method'] as String,
      referenceNo: json['reference_no'] as String?,
      discountTotal: json['discount_total'] as num? ?? 0,
      items: itemsRaw is List
          ? itemsRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : const [],
      createdAt: DateTime.parse(json['created_at'] as String),
      retryCount: json['retry_count'] as int? ?? 0,
      status: OfflineSaleSyncStatus.values.firstWhere(
        (e) => e.name == (json['status'] as String? ?? ''),
        orElse: () => OfflineSaleSyncStatus.pending,
      ),
      lastError: json['last_error'] as String?,
      syncedSaleId: json['synced_sale_id'] as String?,
    );
  }
}
