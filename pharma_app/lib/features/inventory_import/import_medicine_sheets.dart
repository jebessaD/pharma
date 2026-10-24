import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/pricing/recommended_sell_price.dart';
import '../../core/medicine_category_catalog.dart';
import '../../core/widgets/app_text_form_field.dart';
import '../../core/widgets/recommended_sell_price_hint.dart';
import '../../core/medicine/medicine_display.dart';
import '../medicines/medicine_search_bar.dart';
import 'import_medicine_matcher.dart';
import 'import_medicine_similarity.dart';
import 'import_review_row.dart';

const _medicineSelect =
    'id,name,generic_name,manual_code,barcode,purchase_price,selling_price,'
    'is_active,subcategory,country,presentation,strength,dosage_form';

/// Searchable picker over the full branch medicine list, with optional AI
/// suggestions shown first when the extractor found candidates.
Future<Map<String, dynamic>?> showSelectMedicineSheet(
  BuildContext context, {
  required String teamId,
  required String branchId,
  List<Map<String, dynamic>> suggestions = const [],
  String? initialSearch,
  String? matchQuery,
}) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    useSafeArea: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      builder: (context, scrollController) => _SelectMedicineSheet(
        teamId: teamId,
        branchId: branchId,
        suggestions: suggestions,
        initialSearch: initialSearch,
        matchQuery: matchQuery ?? initialSearch,
        scrollController: scrollController,
      ),
    ),
  );
}

class _SelectMedicineSheet extends StatefulWidget {
  const _SelectMedicineSheet({
    required this.teamId,
    required this.branchId,
    required this.suggestions,
    required this.scrollController,
    this.initialSearch,
    this.matchQuery,
  });

  final String teamId;
  final String branchId;
  final List<Map<String, dynamic>> suggestions;
  final ScrollController scrollController;
  final String? initialSearch;
  final String? matchQuery;

  @override
  State<_SelectMedicineSheet> createState() => _SelectMedicineSheetState();
}

class _SelectMedicineSheetState extends State<_SelectMedicineSheet> {
  late final TextEditingController _search;
  List<Map<String, dynamic>> _all = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: widget.initialSearch ?? '');
    _search.addListener(() => setState(() {}));
    _loadMedicines();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadMedicines() async {
    try {
      final rows = await Supabase.instance.client
          .from('medicines')
          .select(_medicineSelect)
          .eq('team_id', widget.teamId)
          .eq('branch_id', widget.branchId)
          .eq('is_active', true)
          .order('name');
      if (!mounted) return;
      setState(() {
        _all = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load medicine list. Try again.';
      });
    }
  }

  List<Map<String, dynamic>> get _rankedSuggestions {
    final q = widget.matchQuery?.trim() ?? '';
    if (q.isEmpty || widget.suggestions.isEmpty) {
      return widget.suggestions;
    }
    final ids = widget.suggestions
        .map((m) => m['id'] as String?)
        .whereType<String>()
        .toSet();
    final fromCatalog = _all.where((m) => ids.contains(m['id'])).toList();
    final pool = fromCatalog.isEmpty ? widget.suggestions : fromCatalog;
    return rankMedicinesBySimilarity(pool, q, minScore: 0, limit: 8);
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.text.trim();
    final suggestionIds = _rankedSuggestions
        .map((m) => m['id'] as String?)
        .whereType<String>()
        .toSet();
    final base = _all.where((m) => !suggestionIds.contains(m['id'])).toList();
    if (q.isEmpty) return base;
    final similar = rankMedicinesBySimilarity(base, q, minScore: 200, limit: 40);
    if (similar.isNotEmpty) return similar;
    return rankMedicines(base, q);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final suggestions = _rankedSuggestions;
    final filtered = _filtered;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 8, 16 + bottomInset),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Select medicine',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          TextField(
            controller: _search,
            autofocus: widget.initialSearch?.isNotEmpty == true,
            decoration: const InputDecoration(
              labelText: 'Search',
              prefixIcon: Icon(Icons.search),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Expanded(
              child: Center(
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            )
          else
            Expanded(
              child: ListView(
                controller: widget.scrollController,
                children: [
                  if (suggestions.isNotEmpty) ...[
                    Text(
                      'Best matches for your scan',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    ...suggestions.map(
                      (m) => _MedicinePickTile(
                        medicine: m,
                        onTap: () => Navigator.of(context).pop(m),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _search.text.trim().isEmpty
                          ? 'All medicines'
                          : 'Search results',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                  ],
                  if (filtered.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        _search.text.trim().isEmpty
                            ? 'No medicines in this branch yet.'
                            : 'No medicines match your search.',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ...filtered.map(
                      (m) => _MedicinePickTile(
                        medicine: m,
                        onTap: () => Navigator.of(context).pop(m),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MedicinePickTile extends StatelessWidget {
  const _MedicinePickTile({required this.medicine, required this.onTap});

  final Map<String, dynamic> medicine;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reason = (medicine['_match_reason'] as String? ?? '').trim();
    final score = medicine['_match_score'] as int?;
    final scoreText = score != null ? '${(score / 10).round()}% match' : null;
    final leading = reason.isNotEmpty ? reason : scoreText;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(medicinePrimaryLabel(medicine)),
      subtitle: medicineSearchSubtitle(
        context,
        medicine,
        leadingMessage: leading != null && leading.isNotEmpty ? leading : null,
        leadingStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// Lets the user pick one of several candidate medicines for a row.
@Deprecated('Use showSelectMedicineSheet which includes suggestions plus full list')
Future<Map<String, dynamic>?> showChooseMedicineSheet(
  BuildContext context,
  List<Map<String, dynamic>> candidates,
) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose the matching medicine',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: candidates.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final m = candidates[i];
                    final code = (m['manual_code'] as String? ?? '').trim();
                    final barcode = (m['barcode'] as String? ?? '').trim();
                    final reason = (m['_match_reason'] as String? ?? '').trim();
                    final sub = [
                      if (reason.isNotEmpty) reason,
                      if (code.isNotEmpty) code,
                      if (barcode.isNotEmpty) barcode,
                      if ((m['strength'] as String? ?? '').isNotEmpty)
                        m['strength'] as String,
                    ].join(' - ');
                    return ListTile(
                      dense: true,
                      title: Text(medicinePrimaryLabel(m)),
                      subtitle: sub.isEmpty ? null : Text(sub),
                      onTap: () => Navigator.of(ctx).pop(m),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Details captured when creating a new medicine for a row.
class NewMedicineDraft {
  const NewMedicineDraft({
    required this.name,
    this.genericName,
    this.manualCode,
    this.barcode,
    required this.categoryKey,
    this.purchasePrice = 0,
    this.sellingPrice = 0,
  });

  final String name;
  final String? genericName;
  final String? manualCode;
  final String? barcode;
  final String categoryKey;
  final num purchasePrice;
  final num sellingPrice;
}

/// Collects fields for a new medicine, prefilled from the review row.
Future<NewMedicineDraft?> showCreateMedicineSheet(
  BuildContext context,
  ImportReviewRow row,
) {
  return showModalBottomSheet<NewMedicineDraft>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _CreateMedicineForm(row: row),
  );
}

class _CreateMedicineForm extends StatefulWidget {
  const _CreateMedicineForm({required this.row});

  final ImportReviewRow row;

  @override
  State<_CreateMedicineForm> createState() => _CreateMedicineFormState();
}

class _CreateMedicineFormState extends State<_CreateMedicineForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _code;
  late final TextEditingController _barcode;
  late final TextEditingController _buy;
  late final TextEditingController _sell;
  late String _categoryKey;

  @override
  void initState() {
    super.initState();
    final r = widget.row;
    _name = TextEditingController(text: r.name.text.trim());
    _code = TextEditingController(text: r.source.resolvedManualCode ?? '');
    _barcode = TextEditingController(text: r.source.barcode ?? '');
    _buy = TextEditingController(text: r.unitCost.text.trim());
    final recommended = recommendedSellPriceFromText(_buy.text);
    _sell = TextEditingController(
      text: r.sellPrice.text.trim().isNotEmpty
          ? r.sellPrice.text.trim()
          : (recommended == null ? '' : priceText(recommended)),
    );
    _categoryKey = r.newCategoryKey;
  }

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _barcode.dispose();
    _buy.dispose();
    _sell.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    String? clean(String v) => v.trim().isEmpty ? null : v.trim();
    Navigator.of(context).pop(
      NewMedicineDraft(
        name: _name.text.trim(),
        manualCode: clean(_code.text),
        barcode: clean(_barcode.text),
        categoryKey: _categoryKey,
        purchasePrice: num.tryParse(_buy.text.trim()) ?? 0,
        sellingPrice: num.tryParse(_sell.text.trim()) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final priceFilter = FilteringTextInputFormatter.allow(
      RegExp(r'^\d*\.?\d{0,2}$'),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create new medicine',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              AppTextFormField(
                controller: _name,
                label: 'Name *',
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 10),
              AppTextFormField(controller: _code, label: 'Manual code'),
              const SizedBox(height: 10),
              AppTextFormField(controller: _barcode, label: 'Barcode'),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _categoryKey,
                decoration: const InputDecoration(labelText: 'Category'),
                items: medicineCategoryCatalog
                    .map(
                      (c) =>
                          DropdownMenuItem(value: c.key, child: Text(c.label)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _categoryKey = v);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: AppTextFormField(
                      controller: _buy,
                      label: 'Buy price',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [priceFilter],
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppTextFormField(
                      controller: _sell,
                      label: 'Sell price',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [priceFilter],
                    ),
                  ),
                ],
              ),
              RecommendedSellPriceHint(
                purchaseText: _buy.text,
                onUse: (value) => setState(() {
                  _sell.text = priceText(value);
                }),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _submit,
                child: const Text('Use this medicine'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Convenience: linkable status label for a match outcome.
String matchOutcomeLabel(MatchOutcome outcome) => switch (outcome) {
  MatchOutcome.single => 'Matched',
  MatchOutcome.multiple => 'Choose',
  MatchOutcome.none => 'New',
};
