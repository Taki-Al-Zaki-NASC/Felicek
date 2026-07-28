import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
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

      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        _report(details.exception, details.stack);
      };

      // Cosmetic, and therefore never allowed to be the reason the app fails
      // to start.
      try {
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
      } on Object catch (e, s) {
        _report(e, s);
      }

      runApp(await _buildApp());
    },
    _report,
  );
}

/// Decides what to run, and **must not throw**.
///
/// If an exception escapes on the way to `runApp`, `runApp` is never called; an
/// app that never calls `runApp` never draws a frame; and Android then sits on
/// its system splash — which on Android 12+ is the launcher icon — indefinitely,
/// with no error and no way out. It is indistinguishable from a hang.
///
/// That shipped once. `Firebase.initializeApp` was guarded, but the
/// `FirebaseAuth.instance` and `FirebaseFirestore.instance` getters immediately
/// after it were not, and those throw when no default app exists — so the
/// failure screen written for "Firebase is not configured" was unreachable in
/// exactly the case it was built for. Hence the second catch: every path out of
/// this function returns a widget.
Future<Widget> _buildApp() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.androidOrNull);
  } on Object catch (e, s) {
    _report(e, s);
    return FelicekApp.unavailable(
      'This build has no Firebase configuration, so there is no backend to '
      'sign in against.\n\n'
      'Add android/app/google-services.json and rebuild, or pass the '
      'FIREBASE_* --dart-define values. See docs/SETUP.md.\n\n$e',
    );
  }

  try {
    // Safe only now that a default app exists — these getters throw otherwise.
    final FirebaseAuth auth = FirebaseAuth.instance;
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    // Crash reporting. Only reachable once Firebase is up, which is also the
    // only point at which it could work — and it is off in debug so local
    // stack traces stay in the console rather than being uploaded.
    _crashlytics = FirebaseCrashlytics.instance;
    await _crashlytics!.setCrashlyticsCollectionEnabled(!kDebugMode);
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      _report(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (Object e, StackTrace s) {
      _report(e, s);
      return true;
    };

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

    return FelicekApp(
      services: AppServices(
        auth: auth,
        firestore: firestore,
        updateService: UpdateService(manifestUrl: AppConfig.updateManifestUrl),
      ),
    );
  } on Object catch (e, s) {
    _report(e, s);
    return FelicekApp.unavailable('Felicek could not start.\n\n$e');
  }
}

/// Null until Firebase is up. Everything before that point has nowhere to
/// report to, which is exactly why the startup path prints instead.
FirebaseCrashlytics? _crashlytics;

void _report(Object error, StackTrace? stack) {
  if (kDebugMode) {
    debugPrint('Unhandled error: $error');
    if (stack != null) debugPrint(stack.toString());
    return;
  }
  // Reporting must never itself throw: an exception here would be raised from
  // inside the handler for another exception, and take the app down with it.
  try {
    _crashlytics?.recordError(error, stack, fatal: false);
  } on Object {
    // Nothing useful left to do — the reporter is the thing that failed.
  }
}
