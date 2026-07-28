import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';
import '../core/theme/typography.dart';
import '../data/services/call_service.dart';
import '../data/services/update_service.dart';
import '../features/auth/auth_screen.dart';
import '../features/kyc/kyc_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile_setup/profile_setup_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/splash/splash_screen.dart';
import 'app_config.dart';
import 'services.dart';
import 'session_controller.dart';

/// Root widget: providers, theme, and the one place that decides which shell
/// the person is looking at.
class FelicekApp extends StatelessWidget {
  const FelicekApp({super.key, required AppServices services})
      : _services = services,
        _startupError = null;

  /// The app could not be brought up — render the reason instead.
  ///
  /// Deliberately takes no [AppServices]: the situations that land here are the
  /// ones where the dependency graph could not be constructed at all, so there
  /// is nothing to pass.
  const FelicekApp.unavailable(String message, {super.key})
      : _services = null,
        _startupError = message;

  final AppServices? _services;
  final String? _startupError;

  @override
  Widget build(BuildContext context) {
    final String? error = _startupError;
    if (error != null) {
      return MaterialApp(
        title: 'Felicek',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        home: _StartupErrorScreen(message: error),
      );
    }

    final AppServices services = _services!;
    return MultiProvider(
      providers: <SingleChildWidget>[
        Provider<AppServices>.value(value: services),
        ChangeNotifierProvider<SessionController>(
          create: (_) => SessionController(
            authRepository: services.authRepository,
            userRepository: services.userRepository,
          ),
        ),
        ChangeNotifierProvider<UpdateServiceNotifier>(
          create: (_) => UpdateServiceNotifier(services),
        ),
        ChangeNotifierProvider<CallService>.value(value: services.callService),
      ],
      child: MaterialApp(
        title: 'Felicek',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(),
        themeMode: ThemeMode.light,
        home: const _SessionGate(),
        builder: (BuildContext context, Widget? child) {
          // Lock text scaling to a sane band: the design is dense, and an
          // unbounded scale factor turns every card into an overflow.
          final MediaQueryData mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler:
                  mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3),
            ),
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}

/// Wraps [UpdateService] so it can sit in the provider tree and kick off its
/// first check once the app is on screen.
class UpdateServiceNotifier extends ChangeNotifier {
  UpdateServiceNotifier(this._services) {
    _services.updateService.addListener(notifyListeners);
    if (AppConfig.selfUpdateEnabled) {
      // Never block first paint on a network call.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _services.updateService.loadInstalledVersion();
        await _services.updateService.check();
      });
    }
  }

  final AppServices _services;

  UpdateService get service => _services.updateService;

  @override
  void dispose() {
    _services.updateService.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Routes on [SessionStage]. Nothing else in the app decides what to show at
/// the root, which keeps "signed out but halfway through KYC" impossible.
class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    final SessionStage stage = context.select<SessionController, SessionStage>(
      (SessionController s) => s.stage,
    );
    final bool stalled = context.select<SessionController, bool>(
      (SessionController s) => s.stalled,
    );

    final Widget child = switch (stage) {
      SessionStage.booting when stalled => const _SessionStalledScreen(),
      SessionStage.booting => const SplashScreen(),
      SessionStage.signedOut => const AuthScreen(),
      SessionStage.onboarding => const OnboardingScreen(),
      SessionStage.profileSetup => const ProfileSetupScreen(),
      SessionStage.verification => const KycScreen(),
      SessionStage.ready => const AppShell(),
    };

    return AnimatedSwitcher(
      duration: FMotion.base,
      switchInCurve: FMotion.curve,
      child: KeyedSubtree(key: ValueKey<SessionStage>(stage), child: child),
    );
  }
}

/// Signed in, but the profile never arrived.
///
/// The point of this screen is that it is *escapable*: an indefinite splash
/// leaves someone with a dead app and no information, and signing out is often
/// the fix (a half-created account, or rules that have since been deployed).
class _SessionStalledScreen extends StatelessWidget {
  const _SessionStalledScreen();

  @override
  Widget build(BuildContext context) {
    final SessionController session = context.watch<SessionController>();

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text('Still loading your account',
                    style: FType.displayMd),
                const SizedBox(height: FSpace.lg),
                Text(
                  session.error ??
                      'Your profile is taking longer than usual to load.',
                  style: FType.supportSm,
                ),
                const SizedBox(height: FSpace.x3),
                Row(
                  children: <Widget>[
                    TextButton(
                      onPressed: session.retry,
                      child: Text('Try again',
                          style: FType.buttonSm.copyWith(color: FColors.teal)),
                    ),
                    const SizedBox(width: FSpace.lg),
                    TextButton(
                      onPressed: session.signOut,
                      child: Text('Sign out',
                          style: FType.buttonSm
                              .copyWith(color: FColors.inkMuted)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FColors.canvas,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: FColors.dangerTint,
                    borderRadius: BorderRadius.circular(FRadius.card),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    color: FColors.danger,
                    size: 24,
                  ),
                ),
                const SizedBox(height: FSpace.x3),
                const Text('Felicek could not start', style: FType.displayMd),
                const SizedBox(height: FSpace.lg),
                Text(message, style: FType.supportSm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
