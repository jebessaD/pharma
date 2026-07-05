import 'package:flutter/material.dart';

/// Email vs phone toggle for auth screens — card-style, clearer than [SegmentedButton].
class AuthMethodSelector extends StatelessWidget {
  const AuthMethodSelector({
    super.key,
    required this.usePhone,
    required this.onChanged,
    this.enabled = true,
  });

  final bool usePhone;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _AuthMethodCard(
            selected: !usePhone,
            enabled: enabled,
            icon: Icons.email_outlined,
            title: 'Email',
            subtitle: 'Work email signup',
            onTap: () => onChanged(false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _AuthMethodCard(
            selected: usePhone,
            enabled: enabled,
            icon: Icons.phone_android_outlined,
            title: 'Phone',
            subtitle: 'Ethiopian mobile',
            onTap: () => onChanged(true),
          ),
        ),
      ],
    );
  }
}

class _AuthMethodCard extends StatelessWidget {
  const _AuthMethodCard({
    required this.selected,
    required this.enabled,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final bool enabled;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final borderColor = selected ? cs.primary : cs.outlineVariant;
    final bg = selected ? cs.primaryContainer.withValues(alpha: 0.35) : cs.surface;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: borderColor.withValues(alpha: selected ? 1 : 0.55),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 22,
                color: selected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: t.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: selected ? cs.primary : cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
