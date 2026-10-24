import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/medicine/medicine_display.dart';

export '../../core/medicine/medicine_display.dart'
    show medicineDetailParts, medicineText;

/// Ranks medicines with generic-first matching for typing flows.
List<Map<String, dynamic>> rankMedicines(
  List<Map<String, dynamic>> rows,
  String q,
) {
  final t = q.trim().toLowerCase();
  if (t.isEmpty) return rows;
  int score(Map<String, dynamic> m) {
    final code = (m['manual_code'] as String? ?? '').toLowerCase();
    final barcode = (m['barcode'] as String? ?? '').toLowerCase();
    final name = (m['name'] as String? ?? '').toLowerCase();
    final gen = (m['generic_name'] as String? ?? '').toLowerCase();
    final details = medicineDetailParts(m).join(' ').toLowerCase();
    if (barcode == t) return 0;
    if (code == t) return 0;
    if (gen.startsWith(t)) return 1;
    if (gen.contains(t)) return 2;
    if (name.startsWith(t)) return 3;
    if (name.contains(t)) return 4;
    if (barcode.startsWith(t)) return 5;
    if (code.startsWith(t)) return 5;
    if (barcode.contains(t)) return 6;
    if (code.contains(t)) return 6;
    if (details.startsWith(t)) return 7;
    if (details.contains(t)) return 8;
    return 99;
  }

  final copy = [...rows]
    ..sort((a, b) {
      final sa = score(a);
      final sb = score(b);
      if (sa != sb) return sa.compareTo(sb);
      final ga = medicinePrimaryLabel(a);
      final gb = medicinePrimaryLabel(b);
      return ga.compareTo(gb);
    });
  return copy.where((m) => score(m) < 99).toList();
}

Widget? medicineSearchSubtitle(
  BuildContext context,
  Map<String, dynamic> row, {
  String? leadingMessage,
  TextStyle? leadingStyle,
}) {
  final brand = medicineSecondaryLabel(row);
  final details = medicineDetailParts(row);
  if (leadingMessage == null && brand == null && details.isEmpty) {
    return null;
  }
  final textTheme = Theme.of(context).textTheme;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (leadingMessage != null)
        Text(
          leadingMessage,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: leadingStyle,
        ),
      if (brand != null)
        Text(
          brand,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyMedium,
        ),
      if (details.isNotEmpty)
        Text(
          details.join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodySmall,
        ),
    ],
  );
}

class MedicineSearchResultTile extends StatelessWidget {
  const MedicineSearchResultTile({
    super.key,
    required this.row,
    required this.onTap,
    this.leadingMessage,
    this.leadingStyle,
  });

  final Map<String, dynamic> row;
  final VoidCallback onTap;
  final String? leadingMessage;
  final TextStyle? leadingStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final primary = medicinePrimaryLabel(row);
    final brand = medicineSecondaryLabel(row);
    final country = medicineText(row, 'country');
    final code = medicineText(row, 'manual_code');
    final barcode = medicineText(row, 'barcode');
    final meta = [
      if (country.isNotEmpty) country,
      if (code.isNotEmpty) 'Code $code',
      if (barcode.isNotEmpty) 'Barcode $barcode',
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              primary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1.15,
              ),
            ),
            if (brand != null) ...[
              const SizedBox(height: 2),
              Text(
                brand,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  height: 1.15,
                ),
              ),
            ],
            if (leadingMessage != null || meta.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                [?leadingMessage, if (meta.isNotEmpty) meta].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    (leadingMessage != null ? leadingStyle : null) ??
                    theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.82),
                      height: 1.1,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

typedef MedicinePicked = void Function(Map<String, dynamic> medicine);

/// Search field that loads team medicines and applies [rankMedicines].
class MedicineSearchBar extends StatefulWidget {
  const MedicineSearchBar({
    super.key,
    required this.teamId,
    required this.branchId,
    required this.onMedicineSelected,
  });

  final String teamId;
  final String branchId;
  final MedicinePicked onMedicineSelected;

  @override
  State<MedicineSearchBar> createState() => _MedicineSearchBarState();
}

class _MedicineSearchBarState extends State<MedicineSearchBar> {
  final _controller = TextEditingController();
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _shown = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
    _controller.addListener(_filter);
  }

  @override
  void dispose() {
    _controller.removeListener(_filter);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await Supabase.instance.client
          .from('medicines')
          .select()
          .eq('team_id', widget.teamId)
          .eq('branch_id', widget.branchId)
          .eq('is_active', true)
          .limit(500);
      _all = List<Map<String, dynamic>>.from(data as List);
      _filter();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _controller.text;
    if (q.trim().isEmpty) {
      setState(() => _shown = _all.take(20).toList());
      return;
    }
    final broad = _all.where((m) {
      final s =
          '${m['manual_code']} ${m['barcode']} ${m['name']} ${m['generic_name']} ${medicineDetailParts(m).join(' ')}'
              .toLowerCase();
      return s.contains(q.trim().toLowerCase());
    }).toList();
    setState(() => _shown = rankMedicines(broad, q).take(24).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'Search medicine',
            hintText: 'Generic, brand, code, or barcode',
            suffixIcon: _loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      _filter();
                    },
                  ),
          ),
        ),
        if (_shown.isNotEmpty)
          Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                itemCount: _shown.length,
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  indent: 12,
                  endIndent: 12,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                itemBuilder: (context, i) {
                  final m = _shown[i];
                  return MedicineSearchResultTile(
                    row: m,
                    onTap: () => widget.onMedicineSelected(m),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
