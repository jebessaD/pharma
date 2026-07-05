import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> showStaffCredentialsDialog({
  required BuildContext context,
  required String username,
  required String password,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Staff created'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Share these sign-in details with this person.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            const Text(
              'Username',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SelectableText(username),
            const SizedBox(height: 8),
            const Text(
              'Password',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SelectableText(password),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: '$username\n$password'));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Copied username and password')),
            );
          },
          child: const Text('Copy'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

String generateStaffPassword({int length = 10}) {
  const chars = 'abcdefghjkmnpqrstuvwxyz23456789';
  final now = DateTime.now().microsecondsSinceEpoch;
  final buffer = StringBuffer();
  for (var i = 0; i < length; i++) {
    buffer.write(chars[(now + i * 17) % chars.length]);
  }
  return buffer.toString();
}
