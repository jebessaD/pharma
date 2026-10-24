import 'package:flutter/material.dart';

import '../pricing/recommended_sell_price.dart';

/// Checkbox to bulk-fill empty sell prices from purchase cost (25% + round up).
class ApplyProfitRoundupCheckbox extends StatelessWidget {
  const ApplyProfitRoundupCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.contentPadding = EdgeInsets.zero,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final EdgeInsetsGeometry contentPadding;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      contentPadding: contentPadding,
      controlAffinity: ListTileControlAffinity.leading,
      dense: true,
      title: const Text('Apply 25% profit + round up'),
      subtitle: const Text('Fills empty sell prices from unit cost'),
    );
  }
}

/// Sets sell from purchase only where sell is still empty.
void applyRecommendedSellPricesWhereEmpty(
  Iterable<({TextEditingController purchase, TextEditingController sell})> lines,
) {
  for (final line in lines) {
    if (line.sell.text.trim().isNotEmpty) continue;
    final recommended = recommendedSellPriceFromText(line.purchase.text);
    if (recommended == null) continue;
    line.sell.text = priceText(recommended);
  }
}
