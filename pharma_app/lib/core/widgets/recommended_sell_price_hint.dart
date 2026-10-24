import 'package:flutter/material.dart';

import '../pricing/recommended_sell_price.dart';

class RecommendedSellPriceHint extends StatelessWidget {
  const RecommendedSellPriceHint({
    super.key,
    required this.purchaseText,
    required this.onUse,
  });

  final String purchaseText;
  final ValueChanged<num> onUse;

  @override
  Widget build(BuildContext context) {
    final recommended = recommendedSellPriceFromText(purchaseText);
    if (recommended == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => onUse(recommended),
        icon: const Icon(Icons.auto_awesome_outlined, size: 16),
        label: Text('Recommended sell: ${priceText(recommended)}'),
        style: TextButton.styleFrom(
          foregroundColor: cs.primary,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}
