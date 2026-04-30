import 'package:flutter/material.dart';

class ScanEntryWidget extends StatelessWidget {
  const ScanEntryWidget({
    super.key,
    required this.controller,
    required this.onScanTap,
    required this.onSubmitted,
    this.hintText = 'Search or scan medicine',
  });

  final TextEditingController controller;
  final Future<void> Function() onScanTap;
  final ValueChanged<String> onSubmitted;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
        prefixIcon: const Icon(Icons.search),
        suffixIconConstraints: const BoxConstraints(
          minHeight: 40,
          minWidth: 40,
        ),
        suffixIcon: IconButton(
          tooltip: 'Scan',
          onPressed: onScanTap,
          icon: const Icon(Icons.qr_code_scanner),
        ),
      ),
      onSubmitted: onSubmitted,
    );
  }
}
