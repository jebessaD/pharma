import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Ranks medicines: exact [manual_code] (case-insensitive), then name prefix, then generic contains.
List<Map<String, dynamic>> rankMedicines(
  List<Map<String, dynamic>> rows,
  String q,
) {
  final t = q.trim().toLowerCase();
  if (t.isEmpty) return rows;
  int score(Map<String, dynamic> m) {
    final code = (m['manual_code'] as String? ?? '').toLowerCase();
    final name = (m['name'] as String? ?? '').toLowerCase();
    final gen = (m['generic_name'] as String? ?? '').toLowerCase();
    if (code == t) return 0;
    if (code.startsWith(t)) return 1;
    if (name.startsWith(t)) return 2;
    if (name.contains(t)) return 3;
    if (gen.contains(t)) return 4;
    return 99;
  }

  final copy = [...rows]..sort((a, b) {
      final sa = score(a);
      final sb = score(b);
      if (sa != sb) return sa.compareTo(sb);
      return (a['name'] as String? ?? '').compareTo(b['name'] as String? ?? '');
    });
  return copy.where((m) => score(m) < 99).toList();
}

typedef MedicinePicked = void Function(Map<String, dynamic> medicine);

/// Search field that loads team medicines and applies [rankMedicines].
class MedicineSearchBar extends StatefulWidget {
  const MedicineSearchBar({
    super.key,
    required this.teamId,
    required this.onMedicineSelected,
  });

  final String teamId;
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
          '${m['manual_code']} ${m['name']} ${m['generic_name']}'.toLowerCase();
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
            hintText: 'Code, name, or generic',
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
            elevation: 2,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _shown.length,
                itemBuilder: (context, i) {
                  final m = _shown[i];
                  return ListTile(
                    dense: true,
                    title: Text(m['name'] as String? ?? ''),
                    subtitle: Text(m['manual_code'] as String? ?? ''),
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
