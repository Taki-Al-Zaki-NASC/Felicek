import 'package:firebase_core/firebase_core.dart';

/// Firebase project wiring.
///
/// There are two supported ways to point this app at a Firebase project, and
/// the app picks whichever is present:
///
/// 1. **`android/app/google-services.json`** (what `flutterfire configure` or
///    the Firebase console gives you). Drop the file in, and
///    `Firebase.initializeApp()` finds it with no Dart changes. This is the
///    normal path — see `docs/SETUP.md`.
///
/// 2. **`--dart-define`**, for CI that would rather inject values than commit
///    a JSON file:
///
///    ```
///    flutter build apk --release \
///      --dart-define=FIREBASE_API_KEY=... \
///      --dart-define=FIREBASE_APP_ID=... \
///      --dart-define=FIREBASE_SENDER_ID=... \
///      --dart-define=FIREBASE_PROJECT_ID=... \
///      --dart-define=FIREBASE_STORAGE_BUCKET=...
///    ```
class DefaultFirebaseOptions {
  const DefaultFirebaseOptions._();

  static const String _apiKey = String.fromEnvironment('FIREBASE_API_KEY');
  static const String _appId = String.fromEnvironment('FIREBASE_APP_ID');
  static const String _senderId = String.fromEnvironment('FIREBASE_SENDER_ID');
  static const String _projectId =
      String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const String _storageBucket =
      String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

  /// True when every required value was supplied at build time.
  static bool get isConfiguredViaDefines =>
      _apiKey.isNotEmpty &&
      _appId.isNotEmpty &&
      _senderId.isNotEmpty &&
      _projectId.isNotEmpty;

  /// Non-null only when [isConfiguredViaDefines]; otherwise the platform
  /// config file is used.
  static FirebaseOptions? get androidOrNull => isConfiguredViaDefines
      ? FirebaseOptions(
          apiKey: _apiKey,
          appId: _appId,
          messagingSenderId: _senderId,
          projectId: _projectId,
          storageBucket: _storageBucket.isEmpty ? null : _storageBucket,
        )
      : null;
}
