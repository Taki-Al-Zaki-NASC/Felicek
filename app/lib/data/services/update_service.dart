import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One release, as published in `update.json` on the distribution site.
@immutable
class UpdateManifest {
  const UpdateManifest({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    required this.sha256,
    required this.sizeBytes,
    this.releaseNotes = '',
    this.mandatory = false,
    this.minSupportedVersionCode = 0,
    this.rolloutPercent = 100,
    this.publishedAt,
  });

  factory UpdateManifest.fromJson(Map<String, dynamic> json) => UpdateManifest(
        versionCode: (json['versionCode'] as num?)?.toInt() ?? 0,
        versionName: json['versionName'] as String? ?? '',
        apkUrl: json['apkUrl'] as String? ?? '',
        sha256: (json['sha256'] as String? ?? '').toLowerCase().trim(),
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        releaseNotes: json['releaseNotes'] as String? ?? '',
        mandatory: json['mandatory'] as bool? ?? false,
        minSupportedVersionCode:
            (json['minSupportedVersionCode'] as num?)?.toInt() ?? 0,
        rolloutPercent: (json['rolloutPercent'] as num?)?.toInt() ?? 100,
        publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
      );

  /// Android `versionCode` — the only thing compared. Names are for people.
  final int versionCode;
  final String versionName;
  final String apkUrl;

  /// Lowercase hex SHA-256 of the APK. A download that does not match is
  /// deleted rather than installed.
  final String sha256;
  final int sizeBytes;
  final String releaseNotes;

  /// Blocks the app until installed — for security fixes and breaking
  /// schema changes.
  final bool mandatory;

  /// Anything at or below this is forced to update.
  final int minSupportedVersionCode;

  /// Staged rollout: only this percentage of installs are offered the build.
  final int rolloutPercent;
  final DateTime? publishedAt;

  bool get isValid =>
      versionCode > 0 &&
      apkUrl.startsWith('https://') &&
      RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256);
}

/// Where the updater currently is.
enum UpdatePhase {
  idle,
  checking,
  available,
  downloading,
  verifying,
  readyToInstall,
  installing,
  upToDate,
  failed
}

@immutable
class UpdateState {
  const UpdateState({
    this.phase = UpdatePhase.idle,
    this.manifest,
    this.progress = 0,
    this.downloadedBytes = 0,
    this.error,
    this.installedVersionCode = 0,
    this.installedVersionName = '',
    this.apkPath,
  });

  final UpdatePhase phase;
  final UpdateManifest? manifest;

  /// 0…1 while downloading.
  final double progress;
  final int downloadedBytes;
  final String? error;
  final int installedVersionCode;
  final String installedVersionName;
  final String? apkPath;

  bool get hasUpdate =>
      manifest != null && manifest!.versionCode > installedVersionCode;

  /// True when the user cannot dismiss the prompt.
  bool get isMandatory =>
      manifest != null &&
      (manifest!.mandatory ||
          installedVersionCode <= manifest!.minSupportedVersionCode);

  bool get isBusy =>
      phase == UpdatePhase.downloading ||
      phase == UpdatePhase.verifying ||
      phase == UpdatePhase.installing;

  UpdateState copyWith({
    UpdatePhase? phase,
    UpdateManifest? manifest,
    double? progress,
    int? downloadedBytes,
    String? error,
    int? installedVersionCode,
    String? installedVersionName,
    String? apkPath,
    bool clearError = false,
  }) =>
      UpdateState(
        phase: phase ?? this.phase,
        manifest: manifest ?? this.manifest,
        progress: progress ?? this.progress,
        downloadedBytes: downloadedBytes ?? this.downloadedBytes,
        error: clearError ? null : (error ?? this.error),
        installedVersionCode: installedVersionCode ?? this.installedVersionCode,
        installedVersionName: installedVersionName ?? this.installedVersionName,
        apkPath: apkPath ?? this.apkPath,
      );
}

/// Self-hosted over-the-air updates for an APK distributed from a website.
///
/// The flow, end to end:
///
/// 1. Fetch `update.json` from the distribution site (cache-busted).
/// 2. Compare its `versionCode` with the running build's.
/// 3. Honour the staged rollout using a stable per-install bucket, so a bad
///    build reaches 10% of people rather than everyone.
/// 4. Download the APK into app-private storage with live progress.
/// 5. Verify SHA-256 before the file is ever handed to the package installer —
///    a truncated or tampered download is deleted, not installed.
/// 6. Hand the file to Android's package installer through a `FileProvider`
///    URI, which is what makes an out-of-store update possible at all.
///
/// Auto-install still shows Android's system confirmation dialog: an app can
/// never silently replace itself outside of a device-owner deployment, and
/// pretending otherwise would just be a bug waiting to happen.
class UpdateService extends ChangeNotifier {
  UpdateService({
    required this.manifestUrl,
    http.Client? httpClient,
    MethodChannel? installerChannel,
  })  : _http = httpClient ?? http.Client(),
        _installer =
            installerChannel ?? const MethodChannel(installerChannelName);

  /// Matches `InstallerPlugin.CHANNEL` on the Android side.
  static const String installerChannelName = 'app.felicek/installer';

  static const String _prefsRolloutBucket = 'update_rollout_bucket';
  static const String _prefsSkippedVersion = 'update_skipped_version';
  static const String _prefsLastCheck = 'update_last_check_ms';

  /// Don't hit the network more than this often on resume.
  static const Duration checkInterval = Duration(hours: 6);

  final String manifestUrl;
  final http.Client _http;
  final MethodChannel _installer;

  UpdateState _state = const UpdateState();
  UpdateState get state => _state;

  http.Client get httpClient => _http;

  void _emit(UpdateState next) {
    _state = next;
    notifyListeners();
  }

  /// Reads the running build's version so the comparison is against reality
  /// rather than a constant someone forgot to bump.
  Future<void> loadInstalledVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      _emit(
        _state.copyWith(
          installedVersionCode: int.tryParse(info.buildNumber) ?? 0,
          installedVersionName: info.version,
        ),
      );
    } on Exception {
      // Leave the defaults; a check will simply find nothing newer.
    }
  }

  /// Returns true when an update is available *and* offered to this install.
  ///
  /// [force] skips both the interval throttle and a previously skipped
  /// version — used by the "Check for updates" row in settings.
  Future<bool> check({bool force = false}) async {
    if (_state.isBusy) return _state.hasUpdate;
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    if (!force) {
      final int last = prefs.getInt(_prefsLastCheck) ?? 0;
      final DateTime lastCheck = DateTime.fromMillisecondsSinceEpoch(last);
      if (DateTime.now().difference(lastCheck) < checkInterval) {
        return _state.hasUpdate;
      }
    }

    _emit(_state.copyWith(phase: UpdatePhase.checking, clearError: true));
    if (_state.installedVersionCode == 0) await loadInstalledVersion();

    try {
      final Uri uri = Uri.parse(manifestUrl).replace(
        queryParameters: <String, String>{
          'v': DateTime.now().millisecondsSinceEpoch.toString(),
        },
      );
      final http.Response res =
          await _http.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        throw HttpException('Update manifest returned ${res.statusCode}');
      }

      final UpdateManifest manifest = UpdateManifest.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>,
      );
      await prefs.setInt(
          _prefsLastCheck, DateTime.now().millisecondsSinceEpoch);

      if (!manifest.isValid) {
        throw const FormatException('Update manifest is malformed');
      }
      if (manifest.versionCode <= _state.installedVersionCode) {
        _emit(_state.copyWith(phase: UpdatePhase.upToDate, manifest: manifest));
        return false;
      }

      final bool forced = manifest.mandatory ||
          _state.installedVersionCode <= manifest.minSupportedVersionCode;

      if (!forced && !await _inRollout(prefs, manifest.rolloutPercent)) {
        _emit(_state.copyWith(phase: UpdatePhase.upToDate));
        return false;
      }
      if (!force &&
          !forced &&
          prefs.getInt(_prefsSkippedVersion) == manifest.versionCode) {
        _emit(_state.copyWith(phase: UpdatePhase.upToDate, manifest: manifest));
        return false;
      }

      _emit(_state.copyWith(phase: UpdatePhase.available, manifest: manifest));
      return true;
    } on Object catch (e) {
      _emit(
        _state.copyWith(
          phase: UpdatePhase.failed,
          error: _describe(e, 'Could not check for updates.'),
        ),
      );
      return false;
    }
  }

  /// Stable per-install bucket in 0–99, so a staged rollout keeps offering the
  /// build to the same devices instead of flip-flopping on every check.
  Future<bool> _inRollout(SharedPreferences prefs, int percent) async {
    if (percent >= 100) return true;
    if (percent <= 0) return false;
    int? bucket = prefs.getInt(_prefsRolloutBucket);
    if (bucket == null) {
      bucket = DateTime.now().microsecondsSinceEpoch % 100;
      await prefs.setInt(_prefsRolloutBucket, bucket);
    }
    return bucket < percent;
  }

  /// Remembers that this version was dismissed. Mandatory builds ignore it.
  Future<void> skipVersion() async {
    final UpdateManifest? m = _state.manifest;
    if (m == null || _state.isMandatory) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsSkippedVersion, m.versionCode);
    _emit(_state.copyWith(phase: UpdatePhase.upToDate));
  }

  /// Downloads, verifies, and hands the APK to the system installer.
  Future<void> downloadAndInstall() async {
    final UpdateManifest? manifest = _state.manifest;
    if (manifest == null || _state.isBusy) return;

    try {
      _emit(
        _state.copyWith(
          phase: UpdatePhase.downloading,
          progress: 0,
          downloadedBytes: 0,
          clearError: true,
        ),
      );

      final Directory dir = await getApplicationSupportDirectory();
      final Directory updates = Directory('${dir.path}/updates');
      if (!updates.existsSync()) updates.createSync(recursive: true);
      // Only ever keep the build being installed.
      for (final FileSystemEntity stale in updates.listSync()) {
        try {
          stale.deleteSync();
        } on FileSystemException {
          // A locked file is not worth aborting the update for.
        }
      }
      final File file =
          File('${updates.path}/felicek-${manifest.versionCode}.apk');

      final http.Request request =
          http.Request('GET', Uri.parse(manifest.apkUrl));
      final http.StreamedResponse response =
          await _http.send(request).timeout(const Duration(seconds: 45));
      if (response.statusCode != 200) {
        throw HttpException('Download failed (${response.statusCode})');
      }

      final int total = response.contentLength ?? manifest.sizeBytes;
      final IOSink sink = file.openWrite();
      int received = 0;
      DateTime lastTick = DateTime.now();

      try {
        await for (final List<int> chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          // Throttle rebuilds — a 40 MB download would otherwise notify
          // thousands of times.
          final DateTime now = DateTime.now();
          if (now.difference(lastTick) > const Duration(milliseconds: 120)) {
            lastTick = now;
            _emit(
              _state.copyWith(
                progress: total > 0 ? received / total : 0,
                downloadedBytes: received,
              ),
            );
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
      }

      _emit(
        _state.copyWith(
          phase: UpdatePhase.verifying,
          progress: 1,
          downloadedBytes: received,
        ),
      );

      final Digest digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != manifest.sha256) {
        await file.delete();
        throw const FormatException(
          'The downloaded file did not match its published checksum.',
        );
      }

      _emit(
        _state.copyWith(phase: UpdatePhase.readyToInstall, apkPath: file.path),
      );
      await install();
    } on Object catch (e) {
      _emit(
        _state.copyWith(
          phase: UpdatePhase.failed,
          error: _describe(e, 'The update could not be downloaded.'),
        ),
      );
    }
  }

  /// Launches Android's package installer for the verified APK.
  Future<void> install() async {
    final String? path = _state.apkPath;
    if (path == null) return;
    try {
      _emit(_state.copyWith(phase: UpdatePhase.installing));
      final bool? started = await _installer.invokeMethod<bool>(
        'installApk',
        <String, dynamic>{'path': path},
      );
      if (started != true) {
        _emit(
          _state.copyWith(
            phase: UpdatePhase.readyToInstall,
            error:
                'Allow "Install unknown apps" for Felicek, then tap Install again.',
          ),
        );
      }
    } on PlatformException catch (e) {
      _emit(
        _state.copyWith(
          phase: UpdatePhase.readyToInstall,
          // Not e.message: PlatformException messages are developer-facing
          // and land on a screen where the only useful next step is retrying
          // or installing by hand.
          error: 'Android could not start the installer (${e.code}). '
              'The download is saved — try again, or install the APK from '
              'your Downloads folder.',
        ),
      );
    }
  }

  /// Whether Android will let this app install packages. Used to explain the
  /// permission before sending the user to Settings.
  Future<bool> canInstallPackages() async {
    try {
      return await _installer.invokeMethod<bool>('canRequestInstalls') ?? false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> openInstallPermissionSettings() async {
    try {
      await _installer.invokeMethod<void>('openInstallPermissionSettings');
    } on PlatformException {
      // Nothing else to do — the dialog in `install()` already explains it.
    }
  }

  void dismissError() => _emit(_state.copyWith(clearError: true));

  static String _describe(Object error, String fallback) {
    if (error is SocketException || error is TimeoutException) {
      return 'No connection. Try again when you are back online.';
    }
    if (error is FormatException) return error.message;
    if (error is HttpException) return error.message;
    return fallback;
  }

  @override
  void dispose() {
    _http.close();
    super.dispose();
  }
}
