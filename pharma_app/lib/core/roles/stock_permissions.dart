bool canAddStockInForRole(String? role) {
  final normalized = role?.trim().toLowerCase();
  return normalized == 'owner' || normalized == 'admin';
}
