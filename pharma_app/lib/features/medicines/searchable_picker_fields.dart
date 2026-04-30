import 'package:flutter/material.dart';

import '../../core/utils/date_formatters.dart';

typedef RowPicked = void Function(Map<String, dynamic> row);

int _medicineRank(Map<String, dynamic> row, String q) {
  final name = (row['name'] as String? ?? '').toLowerCase();
  final code = (row['manual_code'] as String? ?? '').toLowerCase();
  final barcode = (row['barcode'] as String? ?? '').toLowerCase();
  final generic = (row['generic_name'] as String? ?? '').toLowerCase();

  if (name == q || code == q || barcode == q) return 0;
  if (name.startsWith(q)) return 1;
  if (code.startsWith(q) || barcode.startsWith(q)) return 2;
  if (generic.startsWith(q)) return 3;
  if (name.contains(q)) return 4;
  if (code.contains(q) || barcode.contains(q)) return 5;
  if (generic.contains(q)) return 6;
  return 99;
}

int _batchRank(Map<String, dynamic> row, String q) {
  final batchNo = (row['batch_no'] as String? ?? '').toLowerCase();
  final expiry = (row['expiry_date'] as String? ?? '').toLowerCase();
  if (batchNo == q) return 0;
  if (batchNo.startsWith(q)) return 1;
  if (expiry.startsWith(q)) return 2;
  if (batchNo.contains(q)) return 3;
  if (expiry.contains(q)) return 4;
  return 99;
}

class MedicineAutocompleteField extends StatefulWidget {
  const MedicineAutocompleteField({
    super.key,
    required this.rows,
    required this.label,
    required this.onPicked,
    this.initialMedicineId,
    this.validator,
  });

  final List<Map<String, dynamic>> rows;
  final String label;
  final String? initialMedicineId;
  final RowPicked onPicked;
  final String? Function(String?)? validator;

  @override
  State<MedicineAutocompleteField> createState() =>
      _MedicineAutocompleteFieldState();
}

class _MedicineAutocompleteFieldState extends State<MedicineAutocompleteField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _nameFor(widget.initialMedicineId),
    );
  }

  @override
  void didUpdateWidget(covariant MedicineAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMedicineId != widget.initialMedicineId) {
      final nextText = _nameFor(widget.initialMedicineId);
      if (_controller.text != nextText) _controller.text = nextText;
    }
  }

  String _nameFor(String? id) {
    if (id == null) return '';
    Map<String, dynamic>? row;
    for (final item in widget.rows) {
      if (item['id'] == id) {
        row = item;
        break;
      }
    }
    if (row == null) return '';
    final code = row['manual_code'] as String? ?? '';
    final barcode = row['barcode'] as String? ?? '';
    final name = row['name'] as String? ?? '';
    final parts = <String>[];
    if (code.isNotEmpty) parts.add(code);
    if (barcode.isNotEmpty) parts.add(barcode);
    if (parts.isEmpty) return name;
    return '$name (${parts.join(' / ')})';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Map<String, dynamic>>(
      displayStringForOption: (row) {
        final code = row['manual_code'] as String? ?? '';
        final barcode = row['barcode'] as String? ?? '';
        final name = row['name'] as String? ?? '';
        final parts = <String>[];
        if (code.isNotEmpty) parts.add(code);
        if (barcode.isNotEmpty) parts.add(barcode);
        if (parts.isEmpty) return name;
        return '$name (${parts.join(' / ')})';
      },
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return widget.rows.take(15);
        final matched = widget.rows
            .where((row) {
              final s =
                  '${row['name'] ?? ''} ${row['manual_code'] ?? ''} ${row['barcode'] ?? ''} ${row['generic_name'] ?? ''}'
                      .toLowerCase();
              return s.contains(q);
            })
            .toList()
          ..sort((a, b) {
            final ar = _medicineRank(a, q);
            final br = _medicineRank(b, q);
            if (ar != br) return ar.compareTo(br);
            return (a['name'] as String? ?? '').compareTo(
              b['name'] as String? ?? '',
            );
          });
        return matched.take(20);
      },
      onSelected: (row) {
        _controller.text = _nameFor(row['id'] as String?);
        widget.onPicked(row);
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        if (!focusNode.hasFocus && textController.text != _controller.text) {
          textController.value = _controller.value;
        }
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: 'Search by name, code, generic name',
          ),
          onChanged: (_) {
            // Keep internal display state in sync with user input so rebuilds
            // (scroll/keyboard close) do not wipe typed text.
            if (_controller.text != textController.text) {
              _controller.value = textController.value;
            }
          },
          validator: widget.validator,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final items = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, minWidth: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final row = items[index];
                  final code = row['manual_code'] as String? ?? '';
                  final barcode = row['barcode'] as String? ?? '';
                  final name = row['name'] as String? ?? '';
                  return ListTile(
                    dense: true,
                    title: Text(name),
                    subtitle: Text(
                      [code, barcode].where((e) => e.isNotEmpty).join(' · '),
                    ),
                    onTap: () => onSelected(row),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class BatchAutocompleteField extends StatefulWidget {
  const BatchAutocompleteField({
    super.key,
    required this.rows,
    required this.label,
    required this.onPicked,
    this.initialBatchId,
    this.validator,
  });

  final List<Map<String, dynamic>> rows;
  final String label;
  final String? initialBatchId;
  final RowPicked onPicked;
  final String? Function(String?)? validator;

  @override
  State<BatchAutocompleteField> createState() => _BatchAutocompleteFieldState();
}

class _BatchAutocompleteFieldState extends State<BatchAutocompleteField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _labelFor(widget.initialBatchId));
  }

  @override
  void didUpdateWidget(covariant BatchAutocompleteField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialBatchId != widget.initialBatchId) {
      final nextText = _labelFor(widget.initialBatchId);
      if (_controller.text != nextText) _controller.text = nextText;
    }
  }

  String _labelFor(String? id) {
    if (id == null) return '';
    Map<String, dynamic>? row;
    for (final item in widget.rows) {
      if (item['id'] == id) {
        row = item;
        break;
      }
    }
    if (row == null) return '';
    final batchNo = row['batch_no'] as String? ?? 'Batch';
    final expiry = formatDdMmYyyy(row['expiry_date']);
    return '$batchNo · exp $expiry';
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Map<String, dynamic>>(
      displayStringForOption: (row) {
        final batchNo = row['batch_no'] as String? ?? 'Batch';
        final expiry = formatDdMmYyyy(row['expiry_date']);
        final qty = row['qty_on_hand'];
        return '$batchNo · exp $expiry · on hand $qty';
      },
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return widget.rows.take(20);
        final matched = widget.rows
            .where((row) {
              final s = '${row['batch_no'] ?? ''} ${row['expiry_date'] ?? ''}'
                  .toLowerCase();
              return s.contains(q);
            })
            .toList()
          ..sort((a, b) {
            final ar = _batchRank(a, q);
            final br = _batchRank(b, q);
            if (ar != br) return ar.compareTo(br);
            return (a['batch_no'] as String? ?? '').compareTo(
              b['batch_no'] as String? ?? '',
            );
          });
        return matched.take(20);
      },
      onSelected: (row) {
        _controller.text = _labelFor(row['id'] as String?);
        widget.onPicked(row);
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        if (!focusNode.hasFocus && textController.text != _controller.text) {
          textController.value = _controller.value;
        }
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: 'Search batch number or expiry date',
          ),
          onChanged: (_) {
            if (_controller.text != textController.text) {
              _controller.value = textController.value;
            }
          },
          validator: widget.validator,
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final items = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, minWidth: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final row = items[index];
                  final batchNo = row['batch_no'] as String? ?? '';
                  final expiry = formatDdMmYyyy(row['expiry_date']);
                  final qty = row['qty_on_hand'];
                  return ListTile(
                    dense: true,
                    title: Text(batchNo),
                    subtitle: Text('Exp $expiry · on hand $qty'),
                    onTap: () => onSelected(row),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
