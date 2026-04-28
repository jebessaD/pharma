import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<num?> showNumericInputDialog(
  BuildContext context, {
  required String title,
  required num min,
  required num max,
  int decimalPlaces = 2,
  num? initialValue,
}) async {
  return showDialog<num>(
    context: context,
    builder: (ctx) => _NumericInputDialog(
      title: title,
      min: min,
      max: max,
      decimalPlaces: decimalPlaces,
      initialValue: initialValue,
    ),
  );
}

class _NumericInputDialog extends StatefulWidget {
  const _NumericInputDialog({
    required this.title,
    required this.min,
    required this.max,
    required this.decimalPlaces,
    this.initialValue,
  });

  final String title;
  final num min;
  final num max;
  final int decimalPlaces;
  final num? initialValue;

  @override
  State<_NumericInputDialog> createState() => _NumericInputDialogState();
}

class _NumericInputDialogState extends State<_NumericInputDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue == null ? '' : '${widget.initialValue}',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validate(String? value) {
    final parsed = num.tryParse((value ?? '').trim());
    if (parsed == null) return 'Enter a valid number.';
    if (parsed < widget.min) return 'Value must be at least ${widget.min}.';
    if (parsed > widget.max) return 'Value cannot exceed ${widget.max}.';
    final text = (value ?? '').trim();
    final dot = text.indexOf('.');
    if (dot >= 0 && text.length - dot - 1 > widget.decimalPlaces) {
      return 'Use at most ${widget.decimalPlaces} decimal places.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
          decoration: InputDecoration(hintText: 'Min ${widget.min} · Max ${widget.max}'),
          validator: _validate,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            Navigator.pop(context, num.parse(_controller.text.trim()));
          },
          child: const Text('OK'),
        ),
      ],
    );
  }
}
