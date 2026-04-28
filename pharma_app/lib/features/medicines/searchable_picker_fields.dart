import 'package:flutter/material.dart';

typedef RowPicked = void Function(Map<String, dynamic> row);

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
  State<MedicineAutocompleteField> createState() => _MedicineAutocompleteFieldState();
}

class _MedicineAutocompleteFieldState extends State<MedicineAutocompleteField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _nameFor(widget.initialMedicineId));
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
    final name = row['name'] as String? ?? '';
    if (code.isEmpty) return name;
    return '$name ($code)';
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
        final name = row['name'] as String? ?? '';
        if (code.isEmpty) return name;
        return '$name ($code)';
      },
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return widget.rows.take(15);
        return widget.rows.where((row) {
          final s = '${row['name'] ?? ''} ${row['manual_code'] ?? ''} ${row['generic_name'] ?? ''}'
              .toLowerCase();
          return s.contains(q);
        }).take(20);
      },
      onSelected: (row) {
        _controller.text = _nameFor(row['id'] as String?);
        widget.onPicked(row);
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        if (textController.text != _controller.text) {
          textController.value = _controller.value;
        }
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: 'Search by name, code, generic name',
          ),
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
                  final name = row['name'] as String? ?? '';
                  return ListTile(
                    dense: true,
                    title: Text(name),
                    subtitle: Text(code),
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
    final expiry = row['expiry_date'] as String? ?? '';
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
        final expiry = row['expiry_date'] as String? ?? '';
        final qty = row['qty_on_hand'];
        return '$batchNo · exp $expiry · on hand $qty';
      },
      optionsBuilder: (value) {
        final q = value.text.trim().toLowerCase();
        if (q.isEmpty) return widget.rows.take(20);
        return widget.rows.where((row) {
          final s = '${row['batch_no'] ?? ''} ${row['expiry_date'] ?? ''}'.toLowerCase();
          return s.contains(q);
        }).take(20);
      },
      onSelected: (row) {
        _controller.text = _labelFor(row['id'] as String?);
        widget.onPicked(row);
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        if (textController.text != _controller.text) {
          textController.value = _controller.value;
        }
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: 'Search batch number or expiry date',
          ),
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
                  final expiry = row['expiry_date'] as String? ?? '';
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
