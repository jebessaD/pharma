import 'package:flutter/material.dart';

class AuthStepIndicator extends StatelessWidget {
  const AuthStepIndicator({
    super.key,
    required this.labels,
    required this.currentIndex,
  });

  final List<String> labels;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.only(bottom: 18),
                color: i <= currentIndex
                    ? cs.primary
                    : cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          Column(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: i <= currentIndex
                    ? cs.primary
                    : cs.surfaceContainerHighest,
                child: Text(
                  '${i + 1}',
                  style: t.labelMedium?.copyWith(
                    color: i <= currentIndex
                        ? cs.onPrimary
                        : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                labels[i],
                style: t.labelSmall?.copyWith(
                  color: i == currentIndex
                      ? cs.primary
                      : cs.onSurfaceVariant,
                  fontWeight: i == currentIndex ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
