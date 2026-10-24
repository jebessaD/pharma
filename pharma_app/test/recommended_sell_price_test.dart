import 'package:flutter_test/flutter_test.dart';
import 'package:pharma_app/core/pricing/recommended_sell_price.dart';

void main() {
  test('adds 25 percent then smart rounds up', () {
    expect(recommendedSellPrice(100), 130); // 125 → nearest 10 up
    expect(recommendedSellPrice(135), 170); // 168.75 → 170
    expect(recommendedSellPrice(238), 300); // 297.5 → 300
    expect(recommendedSellPrice(228), 290); // 285 → 290
    expect(recommendedSellPrice(2388), 3000); // 2985 → 3000
    expect(recommendedSellPrice(9936), 12500); // 12420 → 12500
    expect(recommendedSellPrice(10.1), 13);
  });

  test('smartRoundUpRetail tiers', () {
    expect(smartRoundUpRetail(99.1), 100);
    expect(smartRoundUpRetail(169), 170);
    expect(smartRoundUpRetail(292), 300);
    expect(smartRoundUpRetail(2985), 3000);
    expect(smartRoundUpRetail(12420), 12500);
  });

  test('ignores empty, invalid, and non-positive values', () {
    expect(recommendedSellPriceFromText(''), isNull);
    expect(recommendedSellPriceFromText('abc'), isNull);
    expect(recommendedSellPriceFromText('0'), isNull);
    expect(recommendedSellPriceFromText('-3'), isNull);
  });
}
