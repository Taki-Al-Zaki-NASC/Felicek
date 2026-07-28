import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_user.dart';
import '../models/public_profile.dart';
import '../models/user_role.dart';
import '../services/firestore_refs.dart';
import 'user_repository.dart';

/// A failure that already carries a message safe to show a person.
class AuthFailure implements Exception {
  const AuthFailure(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'AuthFailure($code): $message';
}

/// Email + password accounts on Firebase Auth (free tier), with the matching
/// `users/{uid}` profile document created in the same flow.
class AuthRepository {
  AuthRepository({required FirebaseAuth auth, required Db db})
      : _auth = auth,
        _db = db;

  final FirebaseAuth _auth;
  final Db _db;

  User? get currentUser => _auth.currentUser;

  String? get uid => _auth.currentUser?.uid;

  bool get isSignedIn => _auth.currentUser != null;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<User> signUp({
    required String email,
    required String password,
    required String displayName,
    required UserRole role,
  }) async {
    try {
      final UserCredential cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final User user = cred.user!;
      await user.updateDisplayName(displayName.trim());
      await _createProfile(
        user: user,
        displayName: displayName.trim(),
        role: role,
      );
      // If an agency invited this address to a team seat, fill it in now.
      await UserRepository(_db).claimTeamSeat(
        uid: user.uid,
        email: user.email ?? email,
        displayName: displayName.trim(),
      );
      unawaitedVerificationEmail(user);
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e), code: e.code);
    } on FirebaseException catch (e) {
      // The Auth account now exists but its Firestore documents do not — the
      // most confusing state this app can be in, because retrying sign-up
      // reports "email already in use" while sign-in reports a generic
      // failure, and neither hints at the real cause.
      //
      // signIn() heals a missing profile, so say so plainly instead of
      // letting a raw Firestore error stand in for an explanation.
      throw AuthFailure(
        '${describeFirestoreError(e)}\n\n'
        'Your login was created, so sign in with the same email once this is '
        'resolved — your profile will finish setting itself up then.',
        code: e.code,
      );
    }
  }

  Future<User> signIn({required String email, required String password}) async {
    try {
      final UserCredential cred = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final User user = cred.user!;
      // A profile can be missing if the very first write failed; heal it here
      // rather than dropping the person into a broken session.
      final DocumentSnapshot<Json> doc = await _db.user(user.uid).get();
      if (!doc.exists) {
        await _createProfile(
          user: user,
          displayName: user.displayName ?? _nameFromEmail(user.email ?? ''),
          role: UserRole.freelancer,
        );
      } else {
        await _db.profile(user.uid).set(
          <String, dynamic>{
            'lastSeenAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e), code: e.code);
    } on FirebaseException catch (e) {
      // Credentials were accepted; only the profile read/write failed.
      throw AuthFailure(describeFirestoreError(e), code: e.code);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e), code: e.code);
    }
  }

  Future<void> resendVerificationEmail() async {
    final User? user = _auth.currentUser;
    if (user == null || user.emailVerified) return;
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e), code: e.code);
    }
  }

  /// Refreshes the cached token so `emailVerified` reflects reality.
  Future<bool> refreshEmailVerified() async {
    final User? user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  Future<void> signOut() async {
    final String? id = uid;
    if (id != null) {
      // Best effort — never block sign-out on a network write.
      try {
        await _db.profile(id).set(
          <String, dynamic>{
            'lastSeenAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } on FirebaseException {
        // Ignored: signing out matters more than the timestamp.
      }
    }
    await _auth.signOut();
  }

  /// Deleting the account requires a recent login; the UI surfaces that.
  Future<void> deleteAccount({required String password}) async {
    final User? user = _auth.currentUser;
    if (user == null) return;
    try {
      final AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      // Scrub the public mirror first — after `delete()` the client loses the
      // permission to touch either document.
      final WriteBatch batch = _db.firestore.batch();
      const Map<String, dynamic> tombstone = <String, dynamic>{
        'displayName': 'Deleted account',
        'bio': '',
        'title': '',
        'location': '',
        'skills': <String>[],
        'searchTerms': <String>[],
      };
      batch.set(
        _db.profile(user.uid),
        <String, dynamic>{
          ...tombstone,
          'deletedAt': FieldValue.serverTimestamp()
        },
        SetOptions(merge: true),
      );
      batch.set(
        _db.user(user.uid),
        <String, dynamic>{
          ...tombstone,
          'deletedAt': FieldValue.serverTimestamp()
        },
        SetOptions(merge: true),
      );
      await batch.commit();
      await user.delete();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(_message(e), code: e.code);
    }
  }

  Future<void> _createProfile({
    required User user,
    required String displayName,
    required UserRole role,
  }) async {
    final AppUser account = AppUser(
      uid: user.uid,
      email: user.email ?? '',
      displayName: displayName,
      role: role,
    );
    final WriteBatch batch = _db.firestore.batch();
    batch.set(
      _db.user(user.uid),
      <String, dynamic>{
        ...account.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _db.profile(user.uid),
      <String, dynamic>{
        ...PublicProfile.fromUser(account).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Fire-and-forget: a failed verification email must not fail sign-up.
  void unawaitedVerificationEmail(User user) {
    user.sendEmailVerification().ignore();
  }

  static String _nameFromEmail(String email) {
    final String local = email.split('@').first;
    if (local.isEmpty) return 'Felicek user';
    return local[0].toUpperCase() + local.substring(1);
  }

  static String _message(FirebaseAuthException e) => switch (e.code) {
        'invalid-email' => 'That email address is not valid.',
        'user-disabled' => 'This account has been disabled. Contact support.',
        'user-not-found' ||
        'wrong-password' ||
        'invalid-credential' =>
          'Email or password is incorrect.',
        'email-already-in-use' => 'An account already exists for that email.',
        'weak-password' =>
          'Choose a stronger password — at least 8 characters.',
        'too-many-requests' =>
          'Too many attempts. Wait a minute and try again.',
        'requires-recent-login' =>
          'For your security, sign in again before making this change.',
        'network-request-failed' =>
          'No connection. Check your network and try again.',
        'operation-not-allowed' =>
          'Email sign-in is not enabled for this project yet.',
        // Firebase returns this when Authentication has never been turned on
        // for the project at all — a step earlier than enabling a specific
        // sign-in method, and easy to mistake for a network problem because
        // the raw message otherwise leaks straight to the screen.
        'configuration-not-found' =>
          'This app is not connected to a working backend yet '
              '(Authentication has not been set up for this Firebase '
              'project). This is a setup issue, not your connection.',
        // Never `e.message`. Returning the SDK's own sentence is what put
        // "CONFIGURATION_NOT_FOUND" in front of a user as though it were an
        // explanation. The code is enough to search for without being noise.
        _ => 'Could not complete that (${e.code}). Please try again.',
      };
}
