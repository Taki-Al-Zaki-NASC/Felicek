import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/app_config.dart';
import 'app/services.dart';
import 'data/services/update_service.dart';
import 'firebase_options.dart';

Future<void> main() async {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
      );

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        _report(details.exception, details.stack);
      };

      final FirebaseSetup setup = await _initFirebase();
      final AppServices services = AppServices(
        auth: setup.auth,
        firestore: setup.firestore,
        updateService: UpdateService(manifestUrl: AppConfig.updateManifestUrl),
      );

      runApp(FelicekApp(services: services, startupError: setup.error));
    },
    (Object error, StackTrace stack) => _report(error, stack),
  );
}

/// Result of bringing Firebase up — carries a message instead of throwing so
/// the app can still render a readable failure screen on a misconfigured build.
class FirebaseSetup {
  const FirebaseSetup(
      {required this.auth, required this.firestore, this.error});

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final String? error;
}

Future<FirebaseSetup> _initFirebase() async {
  String? error;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.androidOrNull);
  } on Object catch (e) {
    error = 'Firebase is not configured for this build.\n\n'
        'Add android/app/google-services.json (see docs/SETUP.md) or pass the '
        'FIREBASE_* --dart-define values.\n\n$e';
  }

  final FirebaseAuth auth = FirebaseAuth.instance;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  if (error == null) {
    // Offline persistence is what makes the messaging UI feel instant: a sent
    // message renders from the local cache before the network round-trip.
    firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 40 * 1024 * 1024,
    );

    if (AppConfig.useEmulators) {
      firestore.useFirestoreEmulator(
        AppConfig.emulatorHost,
        AppConfig.firestoreEmulatorPort,
      );
      await auth.useAuthEmulator(
        AppConfig.emulatorHost,
        AppConfig.authEmulatorPort,
      );
    }
  }

  return FirebaseSetup(auth: auth, firestore: firestore, error: error);
}

void _report(Object error, StackTrace? stack) {
  // Crash reporting would go here. Crashlytics needs no billing upgrade, but
  // it is deliberately not wired in yet: shipping an analytics SDK before the
  // privacy policy exists is how apps fail Play review.
  if (kDebugMode) {
    debugPrint('Unhandled error: $error');
    if (stack != null) debugPrint(stack.toString());
  }
}
