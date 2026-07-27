import 'package:felicek/data/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// The updater decides whether to replace the app on someone's phone, so its
/// validation and force-update logic is worth pinning down.
void main() {
  final String validSha = 'a' * 64;

  UpdateManifest manifest({
    int versionCode = 2,
    String apkUrl = 'https://felicek.app/felicek.apk',
    String? sha256,
    bool mandatory = false,
    int minSupported = 0,
  }) =>
      UpdateManifest(
        versionCode: versionCode,
        versionName: '1.1.0',
        apkUrl: apkUrl,
        sha256: sha256 ?? validSha,
        sizeBytes: 1024,
        mandatory: mandatory,
        minSupportedVersionCode: minSupported,
      );

  group('UpdateManifest.isValid', () {
    test('accepts a well-formed manifest', () {
      expect(manifest().isValid, isTrue);
    });

    test('rejects a plain-HTTP download URL', () {
      expect(manifest(apkUrl: 'http://felicek.app/a.apk').isValid, isFalse);
    });

    test('rejects a missing or malformed checksum', () {
      expect(manifest(sha256: '').isValid, isFalse);
      expect(manifest(sha256: 'abc123').isValid, isFalse);
      expect(manifest(sha256: 'Z' * 64).isValid, isFalse);
    });

    test('rejects a zero version code', () {
      expect(manifest(versionCode: 0).isValid, isFalse);
    });

    test('parses from JSON and lowercases the checksum', () {
      final UpdateManifest m = UpdateManifest.fromJson(<String, dynamic>{
        'versionCode': 5,
        'versionName': '1.2.0',
        'apkUrl': 'https://felicek.app/a.apk',
        'sha256': ('A' * 64),
        'sizeBytes': 42,
        'rolloutPercent': 25,
      });
      expect(m.sha256, 'a' * 64);
      expect(m.rolloutPercent, 25);
      expect(m.isValid, isTrue);
    });

    test('defaults a missing rollout to a full rollout', () {
      final UpdateManifest m = UpdateManifest.fromJson(<String, dynamic>{
        'versionCode': 3,
        'apkUrl': 'https://felicek.app/a.apk',
        'sha256': 'b' * 64,
      });
      expect(m.rolloutPercent, 100);
      expect(m.mandatory, isFalse);
    });
  });

  group('UpdateState', () {
    test('reports an update only when the manifest is newer', () {
      final UpdateState older = UpdateState(
        manifest: manifest(versionCode: 1),
        installedVersionCode: 3,
      );
      expect(older.hasUpdate, isFalse);

      final UpdateState newer = UpdateState(
        manifest: manifest(versionCode: 4),
        installedVersionCode: 3,
      );
      expect(newer.hasUpdate, isTrue);
    });

    test('an explicitly mandatory build cannot be skipped', () {
      final UpdateState s = UpdateState(
        manifest: manifest(versionCode: 4, mandatory: true),
        installedVersionCode: 3,
      );
      expect(s.isMandatory, isTrue);
    });

    test('a build at or below minSupportedVersionCode is forced', () {
      final UpdateState s = UpdateState(
        manifest: manifest(versionCode: 9, minSupported: 3),
        installedVersionCode: 3,
      );
      expect(s.isMandatory, isTrue);
    });

    test('a supported build is optional', () {
      final UpdateState s = UpdateState(
        manifest: manifest(versionCode: 9, minSupported: 3),
        installedVersionCode: 4,
      );
      expect(s.isMandatory, isFalse);
    });

    test('busy covers every phase that must not be interrupted', () {
      for (final UpdatePhase phase in <UpdatePhase>[
        UpdatePhase.downloading,
        UpdatePhase.verifying,
        UpdatePhase.installing,
      ]) {
        expect(UpdateState(phase: phase).isBusy, isTrue, reason: '$phase');
      }
      expect(const UpdateState(phase: UpdatePhase.available).isBusy, isFalse);
    });

    test('clearError wipes the message rather than carrying it forward', () {
      const UpdateState failed = UpdateState(
        phase: UpdatePhase.failed,
        error: 'boom',
      );
      expect(failed.copyWith(clearError: true).error, isNull);
    });
  });
}
