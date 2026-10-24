import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const medicineCatalogAssetPath = 'assets/catalog/medicine_catalog.json';

final medicineCatalogProvider =
    FutureProvider.autoDispose<List<MedicineCatalogEntry>>((ref) async {
      final raw = await rootBundle.loadString(medicineCatalogAssetPath);
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(MedicineCatalogEntry.fromJson)
          .toList(growable: false);
    });

class MedicineCatalogEntry {
  const MedicineCatalogEntry({
    required this.name,
    this.genericName,
    this.country,
    this.presentation,
    this.strength,
    this.dosageForm,
    this.subcategory,
  });

  final String name;
  final String? genericName;
  final String? country;
  final String? presentation;
  final String? strength;
  final String? dosageForm;
  final String? subcategory;

  factory MedicineCatalogEntry.fromJson(Map<String, dynamic> json) {
    return MedicineCatalogEntry(
      name: _text(json['NAME']) ?? '',
      genericName: _text(json['GENERIC_NAME']),
      country: _text(json['COUNTRY']),
      presentation: _text(json['PRESENTATION']),
      strength: _text(json['STRENGTH']),
      dosageForm: _text(json['DOSAGE_FORM']),
      subcategory: _text(json['subcategory']),
    );
  }
}

List<MedicineCatalogEntry> searchMedicineCatalog(
  List<MedicineCatalogEntry> entries,
  String query, {
  int limit = 20,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final matched = entries.where((entry) => _catalogRank(entry, q) < 99).toList()
    ..sort((a, b) {
      final ar = _catalogRank(a, q);
      final br = _catalogRank(b, q);
      if (ar != br) return ar.compareTo(br);
      final ga = a.genericName ?? a.name;
      final gb = b.genericName ?? b.name;
      return ga.compareTo(gb);
    });
  return matched.take(limit).toList(growable: false);
}

int _catalogRank(MedicineCatalogEntry entry, String q) {
  final name = entry.name.toLowerCase();
  final generic = (entry.genericName ?? '').toLowerCase();
  final details = [
    entry.presentation,
    entry.strength,
    entry.dosageForm,
    entry.subcategory,
  ].whereType<String>().join(' ').toLowerCase();

  if (name == q || generic == q) return 0;
  if (generic.startsWith(q)) return 1;
  if (name.startsWith(q)) return 2;
  if (generic.contains(q)) return 3;
  if (name.contains(q)) return 4;
  if (details.startsWith(q)) return 5;
  if (details.contains(q)) return 6;
  return 99;
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}
