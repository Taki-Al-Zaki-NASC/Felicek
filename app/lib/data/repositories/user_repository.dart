import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/public_profile.dart';
import '../models/team_seat.dart';
import '../models/user_role.dart';
import '../services/firestore_refs.dart';

/// Reads and writes the account pair: the private `users/{uid}` record and its
/// public `profiles/{uid}` mirror. Every mutation that touches a field which
/// appears in both writes them in one batch so they can never drift.
class UserRepository {
  UserRepository(this._db);

  final Db _db;

  /// Sentinel distinguishing "photo not part of this save" from "photo
  /// explicitly cleared" in [saveProfile].
  static const Object _unset = Object();

  Stream<AppUser?> watch(String uid) => _db.user(uid).snapshots().map(
        (DocumentSnapshot<Json> doc) =>
            doc.exists ? AppUser.fromDoc(doc) : null,
      );

  Future<AppUser?> fetch(String uid) async {
    final DocumentSnapshot<Json> doc = await _db.user(uid).get();
    return doc.exists ? AppUser.fromDoc(doc) : null;
  }

  Stream<PublicProfile?> watchProfile(String uid) =>
      _db.profile(uid).snapshots().map(
            (DocumentSnapshot<Json> doc) =>
                doc.exists ? PublicProfile.fromDoc(doc) : null,
          );

  Future<PublicProfile?> fetchProfile(String uid) async {
    final DocumentSnapshot<Json> doc = await _db.profile(uid).get();
    return doc.exists ? PublicProfile.fromDoc(doc) : null;
  }

  /// Batch-fetches public profiles, chunked to Firestore's 30-item `whereIn`
  /// limit. Used by the inbox and applicant lists.
  Future<Map<String, PublicProfile>> fetchProfiles(
      Iterable<String> uids) async {
    final List<String> ids = uids.toSet().toList(growable: false);
    final Map<String, PublicProfile> out = <String, PublicProfile>{};
    for (int i = 0; i < ids.length; i += 30) {
      final List<String> chunk = ids.sublist(i, (i + 30).clamp(0, ids.length));
      if (chunk.isEmpty) continue;
      final QuerySnapshot<Json> snap =
          await _db.profiles.where(FieldPath.documentId, whereIn: chunk).get();
      for (final QueryDocumentSnapshot<Json> doc in snap.docs) {
        out[doc.id] = PublicProfile.fromDoc(doc);
      }
    }
    return out;
  }

  Future<void> setRole(String uid, UserRole role) async {
    final WriteBatch batch = _db.firestore.batch();
    batch.set(
      _db.user(uid),
      <String, dynamic>{
        'role': role.key,
        'updatedAt': FieldValue.serverTimestamp()
      },
      SetOptions(merge: true),
    );
    batch.set(
      _db.profile(uid),
      <String, dynamic>{
        'role': role.key,
        'updatedAt': FieldValue.serverTimestamp()
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  /// Saves the answers collected by "Build Your Profile" / "Edit Profile".
  Future<void> saveProfile({
    required String uid,
    required String displayName,
    required String title,
    required String bio,
    required String location,
    List<String> skills = const <String>[],
    double? hourlyRate,
    String? teamSize,
    // Omitted (not passed) leaves the existing photo untouched — only an
    // explicit non-null value (including an empty string, meaning "removed")
    // updates it, so an edit that doesn't touch the photo can't wipe it.
    Object? profilePhotoBase64 = _unset,
  }) async {
    final String name = displayName.trim();
    final Map<String, dynamic> shared = <String, dynamic>{
      'displayName': name,
      'title': title.trim(),
      'bio': bio.trim(),
      'location': location.trim(),
      'skills': skills,
      'hourlyRate': hourlyRate,
      'searchTerms': AppUser.buildSearchTerms(name, skills, title),
      'updatedAt': FieldValue.serverTimestamp(),
      if (!identical(profilePhotoBase64, _unset))
        'profilePhotoBase64': profilePhotoBase64,
    };

    final WriteBatch batch = _db.firestore.batch();
    batch.set(
      _db.user(uid),
      <String, dynamic>{
        ...shared,
        'teamSize': teamSize,
        'profileComplete': true
      },
      SetOptions(merge: true),
    );
    batch.set(_db.profile(uid), shared, SetOptions(merge: true));
    await batch.commit();
  }

  Future<void> markOnboarded(String uid) => _db.user(uid).set(
        <String, dynamic>{
          'onboarded': true,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  // ── Verification ────────────────────────────────────────────────────────

  /// Records that a primary identity document (NID, passport, driving
  /// licence or another government ID) was submitted. Only a reference number
  /// is stored — the document image never leaves the device, which is both a
  /// privacy win and what keeps the project off a paid storage plan.
  Future<void> submitIdentityDocument({
    required String uid,
    required IdDocumentType type,
    required String reference,
  }) async {
    await _db.user(uid).set(
      <String, dynamic>{
        'kyc': <String, dynamic>{
          'idSubmitted': true,
          'idDocumentType': type.key,
          'idReference': reference,
          'stage': KycStage.idSubmitted.name,
          'submittedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> clearIdentityDocument(String uid) => _db.user(uid).set(
        <String, dynamic>{
          'kyc': <String, dynamic>{
            'idSubmitted': false,
            'idDocumentType': null,
            'idReference': null,
            'stage': KycStage.none.name,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  Future<void> submitBirthCertificate({
    required String uid,
    required String reference,
  }) =>
      _db.user(uid).set(
        <String, dynamic>{
          'kyc': <String, dynamic>{
            'birthCertSubmitted': true,
            'birthCertReference': reference,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  Future<void> clearBirthCertificate(String uid) => _db.user(uid).set(
        <String, dynamic>{
          'kyc': <String, dynamic>{
            'birthCertSubmitted': false,
            'birthCertReference': null,
          },
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  /// Records the mandatory deposit as cleared and marks the account verified.
  ///
  /// This must only be called once [PaymentGatewayService] has reconciled the
  /// external checkout against [paymentRef] — never from a bare client tap,
  /// since that would let anyone grant themselves a verified account for
  /// free. See `PaymentGatewayService.confirmAndRecord`.
  Future<void> recordDeposit({
    required String uid,
    required String method,
    required int amountCents,
    required String paymentRef,
  }) async {
    final WriteBatch batch = _db.firestore.batch();
    batch.set(
      _db.user(uid),
      <String, dynamic>{
        'kyc': <String, dynamic>{
          'depositPaid': true,
          'depositMethod': method,
          'depositAmountCents': amountCents,
          'paymentRef': paymentRef,
          'stage': KycStage.verified.name,
          'verifiedAt': FieldValue.serverTimestamp(),
        },
        'trustScore': 85,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    batch.set(
      _db.profile(uid),
      <String, dynamic>{
        'verified': true,
        'trustScore': 85,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  // ── Preferences & safety ────────────────────────────────────────────────

  Future<void> saveNotificationPrefs(String uid, NotificationPrefs prefs) =>
      _db.user(uid).set(
        <String, dynamic>{
          'notificationPrefs': prefs.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  Future<void> blockUser(String uid, String blockedUid) => _db.user(uid).set(
        <String, dynamic>{
          'blockedUserIds': FieldValue.arrayUnion(<String>[blockedUid]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  Future<void> unblockUser(String uid, String blockedUid) => _db.user(uid).set(
        <String, dynamic>{
          'blockedUserIds': FieldValue.arrayRemove(<String>[blockedUid]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

  /// Presence, written to the public mirror so the "Active now" pill works.
  Future<void> touchLastSeen(String uid) async {
    try {
      await _db.profile(uid).set(
        <String, dynamic>{
          'lastSeenAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } on FirebaseException {
      // Presence is best-effort — never surface a failure here.
    }
  }

  // ── Agency team seats ───────────────────────────────────────────────────

  Stream<List<TeamSeat>> watchTeamSeats(String agencyUid) => _db
      .seats(agencyUid)
      .orderBy('invitedAt', descending: false)
      .snapshots()
      .map((JsonQuerySnap s) =>
          s.docs.map(TeamSeat.fromDoc).toList(growable: false));

  /// Records an invite. The seat id is the lowercased email, so inviting the
  /// same person twice updates one seat rather than creating a duplicate.
  Future<void> inviteTeamSeat({
    required String agencyUid,
    required String email,
    required String role,
  }) async {
    final String key = email.toLowerCase().trim();
    await _db.seats(agencyUid).doc(key).set(<String, dynamic>{
      ...TeamSeat(id: key, email: key, role: role).toMap(),
      'invitedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> removeTeamSeat({
    required String agencyUid,
    required String seatId,
  }) =>
      _db.seats(agencyUid).doc(seatId).delete();

  /// Called after sign-up: if this address was invited to an agency, fill the
  /// seat in so the roster stops saying "Invited".
  Future<void> claimTeamSeat({
    required String uid,
    required String email,
    required String displayName,
  }) async {
    final String key = email.toLowerCase().trim();
    try {
      final JsonQuerySnap matches = await _db.firestore
          .collectionGroup(Db.seatsPath)
          .where('email', isEqualTo: key)
          .where('accepted', isEqualTo: false)
          .limit(5)
          .get();
      for (final QueryDocumentSnapshot<Json> doc in matches.docs) {
        await doc.reference.set(<String, dynamic>{
          'memberUid': uid,
          'displayName': displayName,
          'accepted': true,
          'acceptedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    } on FirebaseException {
      // An unclaimed seat is harmless — it simply stays "Invited".
    }
  }

  /// Prefix search over the denormalised `searchTerms` array — no paid search
  /// service required.
  Future<List<PublicProfile>> search(String query, {int limit = 20}) async {
    final String q = query.trim().toLowerCase();
    if (q.length < 2) return const <PublicProfile>[];
    final QuerySnapshot<Json> snap = await _db.profiles
        .where('searchTerms', arrayContains: q)
        .limit(limit)
        .get();
    return snap.docs.map(PublicProfile.fromDoc).toList(growable: false);
  }
}
