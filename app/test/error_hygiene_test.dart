import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Source-level guards against the defect class that has bitten this app
/// repeatedly: an error that either reaches the user as raw SDK text, or never
/// reaches them at all.
///
/// These are lint rules in test form. `flutter analyze` cannot express them,
/// and every instance so far was found by a human reading code — which does
/// not scale and did not catch them before release.
void main() {
  final List<File> sources = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((File f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  test('there is source to check at all', () {
    expect(sources.length, greaterThan(50));
  });

  test('no error path returns the SDK its own message verbatim', () {
    // `e.message ?? '...'` is exactly how CONFIGURATION_NOT_FOUND reached a
    // user's screen as though it were an explanation.
    final RegExp offender = RegExp(r'\be\.message\s*\?\?');
    final List<String> hits = <String>[];
    for (final File f in sources) {
      if (offender.hasMatch(f.readAsStringSync())) hits.add(f.path);
    }
    expect(
      hits,
      isEmpty,
      reason: 'Map the error code to a sentence instead — see '
          'describeFirestoreError in lib/data/services/firestore_refs.dart.',
    );
  });

  test('failures are not blamed on the network without evidence', () {
    // A denied read is a rules problem. Telling someone to check their
    // connection sends them to fix a network that is working fine.
    final List<String> hits = <String>[];
    for (final File f in sources) {
      if (f.readAsStringSync().contains('Check your connection.')) {
        hits.add(f.path);
      }
    }
    expect(
      hits,
      isEmpty,
      reason: 'Use describeFirestoreError, which distinguishes offline from '
          'permission-denied.',
    );
  });

  test('every StreamBuilder handles its error state', () {
    // Without a hasError branch, `if (!snap.hasData) return Loading()` renders
    // a spinner forever — twice this shipped as an entire unusable tab.
    //
    // Two badges degrade to 0 on purpose; they have nowhere to show a message
    // and the screen each one opens reports the failure properly.
    const Set<String> allowed = <String>{
      'lib/features/shell/app_shell.dart',
      'lib/features/notifications/notifications_screen.dart',
    };

    final List<String> offenders = <String>[];
    for (final File f in sources) {
      final String src = f.readAsStringSync();
      for (final Match m in RegExp('StreamBuilder<').allMatches(src)) {
        final String segment = src.substring(
          m.start,
          (m.start + 1400).clamp(0, src.length),
        );
        if (!segment.contains('builder:')) continue;
        final String body = segment.substring(segment.indexOf('builder:'));
        final String head = body.substring(0, body.length.clamp(0, 900));
        if (head.contains('hasError')) continue;

        final String path = f.path.replaceAll(r'\', '/');
        if (allowed.contains(path)) continue;
        offenders.add('$path:${'\n'.allMatches(src.substring(0, m.start)).length + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Add `if (snap.hasError) return FErrorState(message: '
          'describeFirestoreError(snap.error!));`',
    );
  });
}
