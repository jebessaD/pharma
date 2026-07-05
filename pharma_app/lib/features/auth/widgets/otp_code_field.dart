import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpCodeField extends StatelessWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    this.onSubmitted,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback? onSubmitted;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      maxLength: 6,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: const InputDecoration(
        labelText: 'Verification code',
        hintText: '6-digit code',
        counterText: '',
        prefixIcon: Icon(Icons.sms_outlined),
      ),
      validator: (value) {
        final code = value?.trim() ?? '';
        if (code.length != 6) {
          return 'Enter the 6-digit code';
        }
        return null;
      },
      onFieldSubmitted: (_) => onSubmitted?.call(),
    );
  }
}
