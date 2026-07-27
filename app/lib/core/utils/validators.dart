/// Input validation shared by the auth, profile and job-posting forms.
///
/// Every rule here is mirrored in `firebase/firestore.rules`, so a client that
/// skips validation still cannot write malformed data.
class Validate {
  const Validate._();

  static final RegExp _email = RegExp(
    r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9]"
    r'(?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
  );

  static String? email(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter your email address.';
    if (!_email.hasMatch(v)) return 'That email address does not look right.';
    return null;
  }

  /// Play-Store-grade minimum: 8+ chars with at least one letter and one digit.
  static String? password(String? value) {
    final String v = value ?? '';
    if (v.isEmpty) return 'Enter a password.';
    if (v.length < 8) return 'Use at least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(v)) return 'Include at least one letter.';
    if (!RegExp(r'\d').hasMatch(v)) return 'Include at least one number.';
    return null;
  }

  static String? confirmPassword(String? value, String original) {
    if ((value ?? '').isEmpty) return 'Re-enter your password.';
    if (value != original) return 'Passwords do not match.';
    return null;
  }

  static String? required(String? value, {String field = 'This field'}) {
    if ((value ?? '').trim().isEmpty) return '$field is required.';
    return null;
  }

  static String? name(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter your name.';
    if (v.length < 2) return 'Name is too short.';
    if (v.length > 60) return 'Name is too long.';
    return null;
  }

  static String? jobTitle(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Give the job a title.';
    if (v.length < 8) return 'Add a bit more detail — at least 8 characters.';
    if (v.length > 120) return 'Keep the title under 120 characters.';
    return null;
  }

  static String? jobScope(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) {
      return 'Describe the work so freelancers can bid accurately.';
    }
    if (v.length < 40) return 'Add more detail — at least 40 characters.';
    if (v.length > 4000) return 'Keep the scope under 4000 characters.';
    return null;
  }

  static String? budget(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Enter a budget.';
    if (v.length > 60) return 'Keep the budget line short.';
    return null;
  }

  /// A bid must be a positive number the platform can escrow.
  static String? bid(String? value) {
    final String v = (value ?? '').trim().replaceAll(RegExp(r'[$,\s]'), '');
    if (v.isEmpty) return 'Enter your bid.';
    final double? n = double.tryParse(v);
    if (n == null) return 'Enter a number, for example 450.';
    if (n <= 0) return 'Your bid must be more than zero.';
    if (n > 1000000) return 'That bid is unrealistically high.';
    return null;
  }

  static String? message(String? value) {
    final String v = (value ?? '').trim();
    if (v.isEmpty) return 'Write a message first.';
    if (v.length > 4000) return 'Messages are limited to 4000 characters.';
    return null;
  }
}
