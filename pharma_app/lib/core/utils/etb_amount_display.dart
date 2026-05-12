/// Whole birr when the value is an exact amount to the cent; otherwise minimal
/// decimal digits (no trailing zeros), e.g. 50 → "50", 12.5 → "12.5".
/// Prefer for editable fields and default list prices (no `.00` padding).
String formatEtbAmount(num n) {
  final cents = (n.toDouble() * 100).round();
  if (cents % 100 == 0) return (cents ~/ 100).toString();
  return (cents / 100).toString();
}

/// Cart/receipt summaries: always two decimal places (e.g. `50.00`).
String formatEtbAmountFixed2(num n) {
  final v = (n.toDouble() * 100).round() / 100;
  return v.toStringAsFixed(2);
}
