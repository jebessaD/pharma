import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../medicine_category_catalog.dart';

/// Hardcoded categories (not loaded from Supabase).
final branchMedicineCategoriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      return medicineCategoryRowsForUi();
    });

final activeBranchMedicineCategoriesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
      return medicineCategoryRowsForUi();
    });
