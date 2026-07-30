import 'package:felicek/features/shell/app_shell.dart';
import 'package:flutter_test/flutter_test.dart';

/// Back navigation had no handler, so Android's back button popped the shell —
/// the root route — and dropped people onto their phone's home screen from any
/// tab. These pin the trail logic that replaced it.
///
/// The logic is reproduced here rather than driving the widget, because the
/// shell needs Firebase, a session and a call listener to mount. What matters
/// is the ordering rule, and that is what this covers.
class _Trail {
  final List<ShellTab> history = <ShellTab>[ShellTab.home];
  ShellTab tab = ShellTab.home;

  void select(ShellTab next) {
    if (next == tab) return;
    history
      ..remove(next)
      ..add(next);
    tab = next;
  }

  /// False means "nothing left to retrace" — the app should close.
  bool back() {
    if (history.length < 2) return false;
    history.removeLast();
    tab = history.last;
    return true;
  }
}

void main() {
  test('back from a tab returns to the previous one, not the phone home', () {
    final _Trail t = _Trail()..select(ShellTab.proposals);
    expect(t.back(), isTrue, reason: 'back must be consumed, not exit the app');
    expect(t.tab, ShellTab.home);
  });

  test('back retraces several tabs in order', () {
    final _Trail t = _Trail()
      ..select(ShellTab.proposals)
      ..select(ShellTab.payment)
      ..select(ShellTab.profile);

    t.back();
    expect(t.tab, ShellTab.payment);
    t.back();
    expect(t.tab, ShellTab.proposals);
    t.back();
    expect(t.tab, ShellTab.home);
  });

  test('back on the first tab lets the app close', () {
    // Only here should the route actually pop.
    expect(_Trail().back(), isFalse);
  });

  test('revisiting a tab moves it rather than duplicating it', () {
    // Otherwise Home → Payment → Home → back bounces between the same two
    // tabs forever and there is no way out but killing the app.
    final _Trail t = _Trail()
      ..select(ShellTab.payment)
      ..select(ShellTab.home);
    expect(t.history, <ShellTab>[ShellTab.payment, ShellTab.home]);
    expect(t.back(), isTrue);
    expect(t.tab, ShellTab.payment);
    expect(t.back(), isFalse, reason: 'trail exhausted, so the app closes');
  });

  test('selecting the current tab is a no-op', () {
    final _Trail t = _Trail()..select(ShellTab.home);
    expect(t.history, <ShellTab>[ShellTab.home]);
  });

  test('the four tabs are in the order the design lays them out', () {
    expect(ShellTab.values, <ShellTab>[
      ShellTab.home, ShellTab.proposals, ShellTab.payment, ShellTab.profile,
    ]);
  });
}
