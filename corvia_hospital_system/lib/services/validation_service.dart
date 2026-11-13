/// Single source of truth for the form validators shared across the app's
/// screens. Client-side only: it is there to give fast feedback, not to enforce
/// anything. Supabase remains the authority.
class ValidationService {
  /// Accepts any TLD of two or more characters. The registration form used to
  /// cap the TLD at four, which rejected valid addresses such as .health.
  static final RegExp _emailRegex = RegExp(r'^[\w.-]+@[\w.-]+\.\w{2,}$');

  /// Matches the minimum the registration form has always enforced. Raising it
  /// tightens the policy for new sign-ups, so it is a deliberate change.
  static const int minPasswordLength = 6;

  static String? validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(email)) {
      return 'Enter a valid email address (e.g. name@example.co.za).';
    }
    return null;
  }

  static String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Password is required';
    if (value.length < minPasswordLength) {
      return 'Password must be at least $minPasswordLength characters';
    }
    return null;
  }

  /// Digits, spaces, hyphens, brackets, dots and a single leading +. The shape
  /// is checked separately from the digit count so that "08212345AB" is told it
  /// contains letters rather than that it is too short.
  static final RegExp _phoneShape = RegExp(r'^\+?[0-9\s\-().]+$');

  /// The bounds the app already applied in two places before this was shared:
  /// seven digits covers the shortest local number, fifteen is the E.164 limit.
  static const int minPhoneDigits = 7;
  static const int maxPhoneDigits = 15;

  /// [required] is what actually differs between the screens: an emergency
  /// contact is useless without a number, while a patient may not have one.
  static String? validatePhone(String? value, {bool required = false}) {
    final phone = value?.trim() ?? '';
    if (phone.isEmpty) return required ? 'Phone number is required' : null;

    if (!_phoneShape.hasMatch(phone)) {
      return 'Phone number can only contain digits, spaces, hyphens, and a leading +';
    }

    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < minPhoneDigits) return 'Phone number is too short';
    if (digits.length > maxPhoneDigits) return 'Phone number is too long';
    return null;
  }

  /// South African cellphone or landline: 10 digits starting with 0, or an
  /// international number written with a leading +. A 9-digit local number
  /// cannot be dialled or formatted, so it is rejected here.
  static String? validateSouthAfricanPhone(
    String? value, {
    bool required = false,
  }) {
    final basic = validatePhone(value, required: required);
    if (basic != null) return basic;

    final phone = value?.trim() ?? '';
    if (phone.isEmpty || phone.startsWith('+')) return null;

    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (!digits.startsWith('0') || digits.length != 10) {
      return 'Enter a 10-digit number starting with 0, e.g. 082 123 4567';
    }
    return null;
  }

  // There is deliberately no address validator here.
  //
  // Every rule this could carry would be a number picked out of the air. The
  // phone bounds are in the codebase twice and agree, so they describe a policy;
  // nothing states what an address may look like, no migration constrains the
  // column, and addresses vary far too much to guess at. Earlier versions capped
  // the length at 200 and required at least 5 characters, both inherited from a
  // branch that was rejected for exactly this kind of invention.
  //
  // The minimum was also incoherent on its own terms: this form saves an empty
  // address happily, so refusing "abc" - which says strictly more than nothing -
  // could not be justified, and it locked whoever already had a short one out of
  // saving their phone number.
  //
  // Supabase is the authority on what this column accepts, and a rejection comes
  // back as a message the user can read.
}
