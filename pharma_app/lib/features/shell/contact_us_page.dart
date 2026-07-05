import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/widgets/pharmacy_page_app_bar.dart';

/// Support contacts (Telegram + email).
const kSupportTelegramUrl = 'https://t.me/dadu_dev';
const kSupportTelegramHandle = '@dadu_dev';
const kPharmaShelfTelegramChannelUrl = 'https://t.me/pharmashelf';
const kPharmaShelfTelegramChannelHandle = '@pharmashelf';
const kPharmaShelfFacebookUrl =
    'https://www.facebook.com/profile.php?id=61589519367537';
const kPharmaShelfFacebookLabel = 'Pharma Shelf on Facebook';
const kSupportEmail = 'dadudevstudio@gmail.com';

class ContactUsPage extends StatelessWidget {
  const ContactUsPage({super.key});

  Future<void> _openExternalLink(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the link. Try it in a browser.'),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.forum_outlined,
                    color: cs.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Find us online',
                        style: t.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Get help from support or follow Pharma Shelf updates.',
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _ContactLinkCard(
            icon: Icons.support_agent_rounded,
            title: 'Contact support',
            description: 'Questions, billing, or technical help.',
            handle: kSupportTelegramHandle,
            url: kSupportTelegramUrl,
            buttonLabel: 'Message support',
            primary: true,
            onPressed: () => _openExternalLink(context, kSupportTelegramUrl),
          ),
          const SizedBox(height: 22),
          Text(
            'Follow Pharma Shelf',
            style: t.textTheme.titleSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 10),
          _ContactLinkCard(
            icon: Icons.campaign_outlined,
            title: 'Telegram channel',
            description: 'Product updates and announcements.',
            handle: kPharmaShelfTelegramChannelHandle,
            url: kPharmaShelfTelegramChannelUrl,
            buttonLabel: 'Join channel',
            onPressed: () =>
                _openExternalLink(context, kPharmaShelfTelegramChannelUrl),
          ),
          const SizedBox(height: 12),
          _ContactLinkCard(
            icon: Icons.facebook_rounded,
            title: 'Facebook page',
            description: 'Updates, posts, and community news.',
            handle: kPharmaShelfFacebookLabel,
            url: kPharmaShelfFacebookUrl,
            buttonLabel: 'Open Facebook',
            onPressed: () =>
                _openExternalLink(context, kPharmaShelfFacebookUrl),
          ),
        ],
      ),
    );
  }
}

class _ContactLinkCard extends StatelessWidget {
  const _ContactLinkCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.handle,
    required this.url,
    required this.buttonLabel,
    required this.onPressed,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final String handle;
  final String url;
  final String buttonLabel;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: primary
            ? cs.primary.withValues(alpha: 0.06)
            : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: primary
              ? cs.primary.withValues(alpha: 0.22)
              : cs.outlineVariant.withValues(alpha: 0.9),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(primary ? 16 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: primary
                        ? cs.primary.withValues(alpha: 0.12)
                        : cs.surfaceContainerHighest.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: cs.primary, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: t.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: t.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    handle,
                    style: t.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    url,
                    style: t.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (primary)
              FilledButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(buttonLabel),
              )
            else
              OutlinedButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(buttonLabel),
              ),
          ],
        ),
      ),
    );
  }
}
