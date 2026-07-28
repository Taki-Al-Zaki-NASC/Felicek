import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../data/models/app_user.dart';
import '../data/models/public_profile.dart';
import '../data/models/user_role.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/user_repository.dart';

/// Which shell the app should be showing.
enum SessionStage {
  /// Firebase is still restoring the session.
  booting,

  /// No account — show sign in / sign up.
  signedOut,

  /// Signed in, but the account has not picked a role yet.
  onboarding,

  /// Role picked, profile questions (and, for individual freelancers, the
  /// mandatory photo) unanswered.
  profileSetup,

  /// Profile done, but identity and/or the mandatory deposit are not both
  /// cleared yet. This stage cannot be skipped — no account is usable, and no
  /// job can be posted or bid on, until it is.
  verification,

  /// Every mandatory requirement is met.
  ready,
}

/// Owns "who is signed in and what should they see".
///
/// Every screen reads the session from here rather than touching
/// `FirebaseAuth` directly, so the routing rules live in exactly one place.
///
/// The gate is intentionally strict: [SessionStage.ready] is reachable only
/// once [AppUser.meetsMandatoryRequirements] is true — identity document on
/// file, the role's mandatory deposit cleared through the external payment
/// gateway, and (for individual freelancers) a profile photo. There is no
/// "skip for now" path; that was a deliberate product decision, not an
/// oversight — an unverified, undeposited account is not allowed to exist in
/// a usable state.
class SessionController extends ChangeNotifier {
  SessionController({
    required AuthRepository authRepository,
    required UserRepository userRepository,
  })  : _auth = authRepository,
        _users = userRepository {
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
  }

  final AuthRepository _auth;
  final UserRepository _users;

  /// How long the profile document may take to arrive before the splash stops
  /// pretending progress is being made.
  ///
  /// [SessionStage.booting] must be a state the app can leave. Firestore's
  /// stream stays silent — it does not error — when rules deny a read or the
  /// database has not been provisioned, so without this the app waits on the
  /// splash forever with nothing on screen to explain why.
  static const Duration profileTimeout = Duration(seconds: 12);

  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUser?>? _userSub;
  Timer? _profileWatchdog;

  SessionStage _stage = SessionStage.booting;
  AppUser? _user;
  String? _error;
  bool _stalled = false;

  SessionStage get stage => _stage;
  AppUser? get user => _user;
  String? get error => _error;

  /// Signed in, but the profile never loaded — the session cannot progress
  /// without the person doing something (retry, or sign out).
  bool get stalled => _stalled;
  String? get uid => _user?.uid ?? _auth.uid;
  bool get isSignedIn => _auth.isSignedIn;
  UserRole get role => _user?.role ?? UserRole.freelancer;

  PublicProfile? get publicProfile =>
      _user == null ? null : PublicProfile.fromUser(_user!);

  /// True once identity + deposit + (if required) photo are all cleared.
  bool get isVerified => _user?.meetsMandatoryRequirements ?? false;

  bool get needsVerificationBanner => _user != null && !isVerified;

  void _onAuthChanged(User? firebaseUser) {
    _userSub?.cancel();
    _userSub = null;
    _profileWatchdog?.cancel();
    _error = null;
    _stalled = false;

    if (firebaseUser == null) {
      _user = null;
      _setStage(SessionStage.signedOut);
      return;
    }

    _profileWatchdog = Timer(profileTimeout, () {
      if (_user != null) return;
      _stalled = true;
      _error ??= 'Signed in, but your profile did not load.\n\n'
          'This usually means the Firestore security rules have not been '
          'deployed to this project yet, or the device is offline.';
      notifyListeners();
    });

    _userSub = _users.watch(firebaseUser.uid).listen(
      (AppUser? profile) {
        _user = profile;
        if (profile != null) {
          _profileWatchdog?.cancel();
          _stalled = false;
          _error = null;
          // Presence powers the "Active now" pill other people see.
          _users.touchLastSeen(profile.uid);
        }
        _recomputeStage();
      },
      onError: (Object e) {
        // A denied read surfaces here; a missing database usually does not,
        // which is why the watchdog above exists as well.
        _profileWatchdog?.cancel();
        _error = e.toString();
        _stalled = true;
        notifyListeners();
      },
    );
  }

  /// Re-subscribe after a stall — used by the retry affordance.
  void retry() {
    _stalled = false;
    _error = null;
    notifyListeners();
    _onAuthChanged(_auth.currentUser);
  }

  void _recomputeStage() {
    final AppUser? u = _user;
    if (u == null) {
      // Auth exists but the profile document has not arrived yet.
      _setStage(SessionStage.booting);
      return;
    }
    if (!u.onboarded) {
      _setStage(SessionStage.onboarding);
    } else if (!u.profileComplete) {
      _setStage(SessionStage.profileSetup);
    } else if (!u.meetsMandatoryRequirements) {
      _setStage(SessionStage.verification);
    } else {
      _setStage(SessionStage.ready);
    }
  }

  void _setStage(SessionStage next) {
    if (_stage == next) return;
    _stage = next;
    notifyListeners();
  }

  // ── Flow transitions ────────────────────────────────────────────────────

  /// "Continue to Verification" on the role picker.
  Future<void> chooseRole(UserRole role) async {
    final String? id = uid;
    if (id == null) return;
    await _users.setRole(id, role);
    await _users.markOnboarded(id);
  }

  /// Switching account type from the profile screen. Changing role can
  /// introduce a *new* mandatory requirement (e.g. client → freelancer adds
  /// the photo requirement), so this drops the account back to whichever
  /// stage now applies rather than assuming "ready" still holds.
  Future<void> switchRole(UserRole role) async {
    final String? id = uid;
    if (id == null || role == _user?.role) return;
    await _users.setRole(id, role);
  }

  Future<void> completeProfile({
    required String displayName,
    required String title,
    required String bio,
    required String location,
    List<String> skills = const <String>[],
    double? hourlyRate,
    String? teamSize,
    String? profilePhotoBase64,
  }) async {
    final String? id = uid;
    if (id == null) return;
    await _users.saveProfile(
      uid: id,
      displayName: displayName,
      title: title,
      bio: bio,
      location: location,
      skills: skills,
      hourlyRate: hourlyRate,
      teamSize: teamSize,
      profilePhotoBase64: profilePhotoBase64,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _userSub?.cancel();
    _profileWatchdog?.cancel();
    super.dispose();
  }
}
