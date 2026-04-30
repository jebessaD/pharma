import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/pharmacy_page_app_bar.dart';

/// Support contact (Telegram).
const kSupportTelegramUrl = 'https://t.me/dadu_dev';
const kSupportTelegramHandle = '@dadu_dev';

class ContactUsPage extends StatelessWidget {
  const ContactUsPage({super.key});

  Future<void> _openTelegram(BuildContext context) async {
    final uri = Uri.parse(kSupportTelegramUrl);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open Telegram. Try the link in a browser.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return Scaffold(
      appBar: pharmacyHubAppBar(context, title: 'Contact us'),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 56,
            color: cs.primary,
          ),
          const SizedBox(height: 20),
          Text(
            'We are on Telegram',
            style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Questions, billing, or technical help — message us and we will get back to you.',
            style: t.textTheme.bodyLarge?.copyWith(
              color: cs.onSurfaceVariant,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          SelectableText(
            kSupportTelegramHandle,
            style: t.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          SelectableText(
            kSupportTelegramUrl,
            style: t.textTheme.bodySmall?.copyWith(
              color: cs.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () => _openTelegram(context),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open in Telegram'),
          ),
        ],
      ),
    );
  }
}
