import 'package:felicek/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pins the startup failure path.
///
/// The first public build hung on Android's system splash forever: Firebase
/// could not initialise, the `FirebaseAuth.instance` getter threw on the very
/// next line, the exception escaped before `runApp`, and an app that never
/// calls `runApp` never draws a frame. There was no crash and no message —
/// just the launcher icon, indefinitely.
///
/// The contract these tests protect is narrow but load-bearing: it must be
/// possible to render the failure screen *without an AppServices*, because in
/// that failure the dependency graph is exactly what could not be built.
void main() {
  testWidgets('the unavailable screen renders with no services at all',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const FelicekApp.unavailable('This build has no Firebase configuration.'),
    );
    await tester.pump();

    expect(find.textContaining('no Firebase configuration'), findsOneWidget);
  });

  testWidgets('the reason survives to the screen rather than being swallowed',
      (WidgetTester tester) async {
    // The underlying exception text is the only diagnostic a sideloaded user
    // can read back, so it has to reach the surface intact.
    await tester.pumpWidget(
      const FelicekApp.unavailable(
        'Felicek could not start.\n\n[core/no-app] No Firebase App',
      ),
    );
    await tester.pump();

    expect(find.textContaining('[core/no-app]'), findsOneWidget);
  });
}
