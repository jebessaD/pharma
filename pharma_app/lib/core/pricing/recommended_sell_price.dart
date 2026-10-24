/// Rounds a markup amount up to a retail-friendly price tier.
num smartRoundUpRetail(num markup) {
  if (markup <= 0) return 0;
  if (markup < 100) return markup.ceil();
  if (markup < 1000) {
    final step = 10;
    return ((markup / step).ceil()) * step;
  }
  if (markup < 10000) {
    final step = 100;
    return ((markup / step).ceil()) * step;
  }
  final step = 500;
  return ((markup / step).ceil()) * step;
}

/// Recommends a retail sell price from a purchase/unit cost.
///
/// The business rule is: add 25% markup, then smart round-up.
num recommendedSellPrice(num purchasePrice) {
  if (purchasePrice <= 0) return 0;
  return smartRoundUpRetail(purchasePrice * 1.25);
}

num? recommendedSellPriceFromText(String text) {
  final value = num.tryParse(text.trim());
  if (value == null || value <= 0) return null;
  return recommendedSellPrice(value);
}

String priceText(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();
