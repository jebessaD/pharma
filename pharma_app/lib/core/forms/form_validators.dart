class FormValidators {
  static String? requiredText(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required.';
    }
    return null;
  }

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required.';
    final regex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    if (!regex.hasMatch(v)) return 'Enter a valid email address.';
    return null;
  }

  /// Staff handle: lowercase letters, digits, underscore; 3–32 chars (matches admin-create-user).
  static String? staffUsername(String? value) {
    final v = value?.trim().toLowerCase() ?? '';
    if (v.isEmpty) return 'Username is required.';
    if (v.length < 3) return 'Username must be at least 3 characters.';
    if (v.length > 32) return 'Username must be at most 32 characters.';
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(v)) {
      return 'Use only lowercase letters, numbers, and underscores.';
    }
    return null;
  }

  static String? passwordMinLength(String? value, {int min = 8}) {
    if ((value ?? '').length < min) return 'Password must be at least $min characters.';
    return null;
  }

  static String? nonNegativeNumber(String? value, {String label = 'Value'}) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = num.tryParse(value.trim());
    if (parsed == null) return '$label must be a valid number.';
    if (parsed < 0) return '$label cannot be negative.';
    return null;
  }

  static String? positiveNumber(String? value, {String label = 'Value'}) {
    final parsed = num.tryParse((value ?? '').trim());
    if (parsed == null || parsed <= 0) return '$label must be greater than 0.';
    return null;
  }
}
