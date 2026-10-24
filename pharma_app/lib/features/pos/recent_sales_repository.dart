import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/medicine/medicine_display.dart';

typedef RecentSalesQuery = ({
  String teamId,
  String branchId,
  String role,
  String userId,
  int limit,
});

class RecentSale {
  const RecentSale({
    required this.id,
    required this.createdAt,
    required this.grandTotal,
    required this.items,
    required this.paymentMethod,
    required this.referenceNo,
    required this.sellerName,
  });

  final String id;
  final DateTime? createdAt;
  final num grandTotal;
  final List<RecentSaleItem> items;
  final String? paymentMethod;
  final String? referenceNo;
  final String? sellerName;

  int get itemCount => items.length;
}

class RecentSaleItem {
  const RecentSaleItem({
    required this.primaryLabel,
    this.brandLabel,
    required this.qty,
  });

  /// Generic (or sole name when no generic).
  final String primaryLabel;

  /// Brand / trade name when distinct from [primaryLabel].
  final String? brandLabel;
  final num qty;
}

class RecentSalesRefreshNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() {
    state = state + 1;
  }
}

final recentSalesRefreshTickProvider =
    NotifierProvider<RecentSalesRefreshNotifier, int>(
      RecentSalesRefreshNotifier.new,
    );

final recentSalesProvider = FutureProvider.family
    .autoDispose<List<RecentSale>, RecentSalesQuery>((ref, params) async {
      ref.watch(recentSalesRefreshTickProvider);
      if (params.teamId.isEmpty || params.branchId.isEmpty) {
        return const [];
      }

      final role = params.role.trim().toLowerCase();
      final ownSalesOnly =
          role == 'cashier' || role == 'seller' || role == 'pharmacist';

      var query = Supabase.instance.client
          .from('sales')
          .select(
            'id, created_at, grand_total, sold_by, '
            'sale_items(qty, medicine_batches(medicines(name, generic_name))), '
            'payments(method, reference_no)',
          )
          .eq('team_id', params.teamId)
          .eq('branch_id', params.branchId);

      if (ownSalesOnly && params.userId.isNotEmpty) {
        query = query.eq('sold_by', params.userId);
      }

      final raw = await query
          .order('created_at', ascending: false)
          .limit(params.limit);
      final rows = List<Map<String, dynamic>>.from(raw as List);

      final sellerIds = <String>{};
      if (!ownSalesOnly) {
        for (final row in rows) {
          final sellerId = row['sold_by'] as String?;
          if (sellerId != null && sellerId.isNotEmpty) sellerIds.add(sellerId);
        }
      }

      final sellerNameById = <String, String>{};
      if (sellerIds.isNotEmpty) {
        final profiles = await Supabase.instance.client
            .from('profiles')
            .select('id, full_name, username')
            .eq('team_id', params.teamId)
            .inFilter('id', sellerIds.toList());
        for (final profile in profiles as List) {
          final row = Map<String, dynamic>.from(profile as Map);
          final id = row['id'] as String?;
          if (id == null || id.isEmpty) continue;
          final fullName = (row['full_name'] as String? ?? '').trim();
          final username = (row['username'] as String? ?? '').trim();
          sellerNameById[id] = fullName.isNotEmpty
              ? fullName
              : (username.isNotEmpty ? username : 'Team member');
        }
      }

      return rows
          .map((row) {
            final items = row['sale_items'];
            final payments = row['payments'];
            final payment = payments is List && payments.isNotEmpty
                ? Map<String, dynamic>.from(payments.first as Map)
                : const <String, dynamic>{};
            final sellerId = row['sold_by'] as String?;
            return RecentSale(
              id: row['id'] as String? ?? '',
              createdAt: DateTime.tryParse(row['created_at'] as String? ?? ''),
              grandTotal: row['grand_total'] as num? ?? 0,
              items: _parseRecentSaleItems(items),
              paymentMethod: payment['method'] as String?,
              referenceNo: payment['reference_no'] as String?,
              sellerName: sellerId == null ? null : sellerNameById[sellerId],
            );
          })
          .where((sale) => sale.id.isNotEmpty)
          .toList();
    });

List<RecentSaleItem> _parseRecentSaleItems(Object? raw) {
  if (raw is! List) return const [];
  return raw.map((itemRaw) {
    final item = Map<String, dynamic>.from(itemRaw as Map);
    final batch = item['medicine_batches'] is Map
        ? Map<String, dynamic>.from(item['medicine_batches'] as Map)
        : const <String, dynamic>{};
    final medicine = batch['medicines'] is Map
        ? Map<String, dynamic>.from(batch['medicines'] as Map)
        : const <String, dynamic>{};
    return RecentSaleItem(
      primaryLabel: medicinePrimaryLabel(medicine),
      brandLabel: medicineSecondaryLabel(medicine),
      qty: item['qty'] as num? ?? 0,
    );
  }).toList();
}
