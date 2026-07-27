/// Build-time configuration.
///
/// Everything here is overridable with `--dart-define` so the same source tree
/// produces a staging build and a production build without a code change:
///
/// ```
/// flutter build apk --release \
///   --dart-define=FELICEK_UPDATE_MANIFEST=https://felicek.app/update.json \
///   --dart-define=FELICEK_SITE=https://felicek.app
/// ```
class AppConfig {
  const AppConfig._();

  /// Where the distribution site publishes the current release descriptor.
  /// The in-app updater polls this; see `website/update.json`.
  static const String updateManifestUrl = String.fromEnvironment(
    'FELICEK_UPDATE_MANIFEST',
    defaultValue: 'https://felicek.app/update.json',
  );

  /// The public site — used for the download page, privacy policy and terms.
  static const String siteUrl = String.fromEnvironment(
    'FELICEK_SITE',
    defaultValue: 'https://felicek.app',
  );

  static const String privacyUrl = '$siteUrl/privacy';
  static const String termsUrl = '$siteUrl/terms';
  static const String supportEmail = String.fromEnvironment(
    'FELICEK_SUPPORT_EMAIL',
    defaultValue: 'support@felicek.app',
  );

  /// The dedicated external payment gateway checkout page. Money for the
  /// mandatory verification deposit, job-posting balances and wallet top-ups
  /// is handled entirely by this gateway — never simulated in-app. See
  /// `docs/PAYMENTS.md` for what the gateway-side webhook must do.
  static const String paymentCheckoutUrl = String.fromEnvironment(
    'FELICEK_PAYMENT_CHECKOUT_URL',
    defaultValue: 'https://pay.felicek.app/checkout',
  );

  /// Custom URL scheme the gateway redirects back to after checkout.
  static const String deepLinkScheme = String.fromEnvironment(
    'FELICEK_DEEPLINK_SCHEME',
    defaultValue: 'felicek',
  );

  /// Turns off the in-app updater entirely — set this for a Play Store build,
  /// where self-updating is a policy violation.
  static const bool selfUpdateEnabled = bool.fromEnvironment(
    'FELICEK_SELF_UPDATE',
    defaultValue: true,
  );

  /// Points the app at the local Firebase emulator suite.
  static const bool useEmulators = bool.fromEnvironment('FELICEK_EMULATORS');

  static const String emulatorHost = String.fromEnvironment(
    'FELICEK_EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );

  static const int firestoreEmulatorPort = 8080;
  static const int authEmulatorPort = 9099;
}
