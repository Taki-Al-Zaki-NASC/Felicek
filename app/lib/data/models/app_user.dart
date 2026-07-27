import 'package:cloud_firestore/cloud_firestore.dart';

import 'user_role.dart';

/// Where a user is in the identity-verification flow.
enum KycStage { none, idSubmitted, verified }

/// Verification + mandatory-deposit state.
///
/// Documents themselves are never stored as images — only a reference number
/// — which is both a privacy win and what keeps the project off a paid
/// storage plan. The one exception is the mandatory freelancer profile photo,
/// which is small, downsized, and stored as base64 on the public profile
/// (see [AppUser.profilePhotoBase64]).
///
/// No account is usable until [isVerified] is true — the app enforces this at
/// the routing level ([SessionController]), not just in the UI: identity
/// document on file *and* the role's mandatory deposit paid.
class KycState {
  const KycState({
    this.idSubmitted = false,
    this.idDocumentType,
    this.idReference,
    this.birthCertSubmitted = false,
    this.birthCertReference,
    this.depositPaid = false,
    this.depositMethod,
    this.depositAmountCents = 0,
    this.depositReleased = false,
    this.paymentRef,
    this.stage = KycStage.none,
    this.submittedAt,
    this.verifiedAt,
  });

  factory KycState.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const KycState();
    return KycState(
      idSubmitted:
          map['idSubmitted'] as bool? ?? map['nidSubmitted'] as bool? ?? false,
      idDocumentType: map['idDocumentType'] == null
          ? null
          : IdDocumentType.fromKey(map['idDocumentType'] as String?),
      idReference:
          map['idReference'] as String? ?? map['nidReference'] as String?,
      birthCertSubmitted: map['birthCertSubmitted'] as bool? ?? false,
      birthCertReference: map['birthCertReference'] as String?,
      depositPaid: map['depositPaid'] as bool? ?? false,
      depositMethod: map['depositMethod'] as String?,
      depositAmountCents: (map['depositAmountCents'] as num?)?.toInt() ?? 0,
      depositReleased: map['depositReleased'] as bool? ?? false,
      paymentRef: map['paymentRef'] as String?,
      stage: KycStage.values.firstWhere(
        (KycStage s) => s.name == map['stage'],
        orElse: () => KycStage.none,
      ),
      submittedAt: (map['submittedAt'] as Timestamp?)?.toDate(),
      verifiedAt: (map['verifiedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// True once a primary identity document (NID, passport, licence, or other
  /// government ID) has been submitted.
  final bool idSubmitted;
  final IdDocumentType? idDocumentType;
  final String? idReference;
  final bool birthCertSubmitted;
  final String? birthCertReference;

  /// True once the mandatory deposit has cleared through the external
  /// payment gateway — never set from a client-only write; see
  /// [PaymentGatewayService].
  final bool depositPaid;
  final String? depositMethod;
  final int depositAmountCents;
  final bool depositReleased;

  /// The payment-gateway transaction/session reference used to reconcile the
  /// checkout, so "Verify payment" can re-check the real outcome instead of
  /// trusting a client-side tap.
  final String? paymentRef;
  final KycStage stage;
  final DateTime? submittedAt;
  final DateTime? verifiedAt;

  /// The account is usable once identity is on file *and* the deposit has
  /// cleared — the two are equally mandatory, for every role.
  bool get isVerified => stage == KycStage.verified && depositPaid;

  /// The design's progress bar: 20% → 60% (ID in) → 100% (deposit paid).
  double get progress {
    if (depositPaid) return 1.0;
    if (idSubmitted) return 0.6;
    return 0.2;
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'idSubmitted': idSubmitted,
        'idDocumentType': idDocumentType?.key,
        'idReference': idReference,
        'birthCertSubmitted': birthCertSubmitted,
        'birthCertReference': birthCertReference,
        'depositPaid': depositPaid,
        'depositMethod': depositMethod,
        'depositAmountCents': depositAmountCents,
        'depositReleased': depositReleased,
        'paymentRef': paymentRef,
        'stage': stage.name,
        if (submittedAt != null)
          'submittedAt': Timestamp.fromDate(submittedAt!),
        if (verifiedAt != null) 'verifiedAt': Timestamp.fromDate(verifiedAt!),
      };

  KycState copyWith({
    bool? idSubmitted,
    IdDocumentType? idDocumentType,
    String? idReference,
    bool? birthCertSubmitted,
    String? birthCertReference,
    bool? depositPaid,
    String? depositMethod,
    int? depositAmountCents,
    bool? depositReleased,
    String? paymentRef,
    KycStage? stage,
    DateTime? submittedAt,
    DateTime? verifiedAt,
  }) =>
      KycState(
        idSubmitted: idSubmitted ?? this.idSubmitted,
        idDocumentType: idDocumentType ?? this.idDocumentType,
        idReference: idReference ?? this.idReference,
        birthCertSubmitted: birthCertSubmitted ?? this.birthCertSubmitted,
        birthCertReference: birthCertReference ?? this.birthCertReference,
        depositPaid: depositPaid ?? this.depositPaid,
        depositMethod: depositMethod ?? this.depositMethod,
        depositAmountCents: depositAmountCents ?? this.depositAmountCents,
        depositReleased: depositReleased ?? this.depositReleased,
        paymentRef: paymentRef ?? this.paymentRef,
        stage: stage ?? this.stage,
        submittedAt: submittedAt ?? this.submittedAt,
        verifiedAt: verifiedAt ?? this.verifiedAt,
      );
}

/// Notification preferences (the "Notification preferences" settings row).
class NotificationPrefs {
  const NotificationPrefs({
    this.newMessages = true,
    this.proposalUpdates = true,
    this.jobMatches = true,
    this.payouts = true,
    this.calls = true,
    this.productNews = false,
  });

  factory NotificationPrefs.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const NotificationPrefs();
    return NotificationPrefs(
      newMessages: map['newMessages'] as bool? ?? true,
      proposalUpdates: map['proposalUpdates'] as bool? ?? true,
      jobMatches: map['jobMatches'] as bool? ?? true,
      payouts: map['payouts'] as bool? ?? true,
      calls: map['calls'] as bool? ?? true,
      productNews: map['productNews'] as bool? ?? false,
    );
  }

  final bool newMessages;
  final bool proposalUpdates;
  final bool jobMatches;
  final bool payouts;
  final bool calls;
  final bool productNews;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'newMessages': newMessages,
        'proposalUpdates': proposalUpdates,
        'jobMatches': jobMatches,
        'payouts': payouts,
        'calls': calls,
        'productNews': productNews,
      };

  NotificationPrefs copyWith({
    bool? newMessages,
    bool? proposalUpdates,
    bool? jobMatches,
    bool? payouts,
    bool? calls,
    bool? productNews,
  }) =>
      NotificationPrefs(
        newMessages: newMessages ?? this.newMessages,
        proposalUpdates: proposalUpdates ?? this.proposalUpdates,
        jobMatches: jobMatches ?? this.jobMatches,
        payouts: payouts ?? this.payouts,
        calls: calls ?? this.calls,
        productNews: productNews ?? this.productNews,
      );
}

/// A Felicek account. Stored at `users/{uid}`.
class AppUser {
  const AppUser({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    this.title = '',
    this.bio = '',
    this.location = '',
    this.skills = const <String>[],
    this.hourlyRate,
    this.teamSize,
    this.profilePhotoBase64,
    this.kyc = const KycState(),
    this.notificationPrefs = const NotificationPrefs(),
    this.trustScore = 60,
    this.jobSuccess = 0,
    this.jobsDone = 0,
    this.totalEarnedCents = 0,
    this.walletBalanceCents = 0,
    this.postingBalanceCents = 0,
    this.profileComplete = false,
    this.onboarded = false,
    this.lastSeenAt,
    this.createdAt,
    this.updatedAt,
    this.blockedUserIds = const <String>[],
    this.searchTerms = const <String>[],
  });

  factory AppUser.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return AppUser(
      uid: doc.id,
      email: d['email'] as String? ?? '',
      displayName: d['displayName'] as String? ?? '',
      role: UserRole.fromKey(d['role'] as String?),
      title: d['title'] as String? ?? '',
      bio: d['bio'] as String? ?? '',
      location: d['location'] as String? ?? '',
      skills: (d['skills'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(growable: false),
      hourlyRate: (d['hourlyRate'] as num?)?.toDouble(),
      teamSize: d['teamSize'] as String?,
      profilePhotoBase64: d['profilePhotoBase64'] as String?,
      kyc: KycState.fromMap(d['kyc'] as Map<String, dynamic>?),
      notificationPrefs: NotificationPrefs.fromMap(
          d['notificationPrefs'] as Map<String, dynamic>?),
      trustScore: (d['trustScore'] as num?)?.toInt() ?? 60,
      jobSuccess: (d['jobSuccess'] as num?)?.toInt() ?? 0,
      jobsDone: (d['jobsDone'] as num?)?.toInt() ?? 0,
      totalEarnedCents: (d['totalEarnedCents'] as num?)?.toInt() ?? 0,
      walletBalanceCents: (d['walletBalanceCents'] as num?)?.toInt() ?? 0,
      postingBalanceCents: (d['postingBalanceCents'] as num?)?.toInt() ?? 0,
      profileComplete: d['profileComplete'] as bool? ?? false,
      onboarded: d['onboarded'] as bool? ?? false,
      lastSeenAt: (d['lastSeenAt'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (d['updatedAt'] as Timestamp?)?.toDate(),
      blockedUserIds: (d['blockedUserIds'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(growable: false),
      searchTerms: (d['searchTerms'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic e) => e.toString())
          .toList(growable: false),
    );
  }

  final String uid;
  final String email;
  final String displayName;
  final UserRole role;
  final String title;
  final String bio;
  final String location;
  final List<String> skills;
  final double? hourlyRate;
  final String? teamSize;

  /// A small (≤512px, JPEG-compressed) profile photo, base64-encoded. Kept
  /// under ~60 KB so it fits comfortably inside a Firestore document without
  /// a paid Storage plan. Mandatory for individual freelancers.
  final String? profilePhotoBase64;
  final KycState kyc;
  final NotificationPrefs notificationPrefs;
  final int trustScore;
  final int jobSuccess;
  final int jobsDone;
  final int totalEarnedCents;

  /// Earnings a freelancer can withdraw.
  final int walletBalanceCents;

  /// A client/agency/startup's funded balance — spent into escrow when they
  /// hire, refundable to their payout method if they never do.
  final int postingBalanceCents;
  final bool profileComplete;
  final bool onboarded;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<String> blockedUserIds;

  /// Lowercase tokens of the display name + skills, so search works without a
  /// paid search backend.
  final List<String> searchTerms;

  double get walletBalance => walletBalanceCents / 100;
  double get totalEarned => totalEarnedCents / 100;
  double get postingBalance => postingBalanceCents / 100;

  bool get hasProfilePhoto =>
      profilePhotoBase64 != null && profilePhotoBase64!.isNotEmpty;

  /// No account is fully set up without both the mandatory photo (where the
  /// role requires one) and the deposit.
  bool get meetsMandatoryRequirements =>
      (!role.requiresProfilePhoto || hasProfilePhoto) && kyc.isVerified;

  /// Freelancers must clear ID + deposit + (if individual) a profile photo
  /// before the app unlocks bidding.
  bool get canBid => role != UserRole.freelancer || meetsMandatoryRequirements;

  /// Clients/agencies/startups must clear verification + posting balance
  /// before they can publish a listing.
  bool get canPostJob =>
      role == UserRole.freelancer || meetsMandatoryRequirements;

  bool get vaultLocked => !kyc.depositReleased;

  /// A public snapshot embedded in chats and proposals so lists render without
  /// a second read per row (free-tier read budget matters).
  Map<String, dynamic> get publicSnapshot => <String, dynamic>{
        'uid': uid,
        'displayName': displayName,
        'role': role.key,
        'title': title,
        'trustScore': trustScore,
        'verified': kyc.isVerified,
        'profilePhotoBase64': profilePhotoBase64,
      };

  Map<String, dynamic> toMap() => <String, dynamic>{
        'email': email,
        'displayName': displayName,
        'role': role.key,
        'title': title,
        'bio': bio,
        'location': location,
        'skills': skills,
        'hourlyRate': hourlyRate,
        'teamSize': teamSize,
        'profilePhotoBase64': profilePhotoBase64,
        'kyc': kyc.toMap(),
        'notificationPrefs': notificationPrefs.toMap(),
        'trustScore': trustScore,
        'jobSuccess': jobSuccess,
        'jobsDone': jobsDone,
        'totalEarnedCents': totalEarnedCents,
        'walletBalanceCents': walletBalanceCents,
        'postingBalanceCents': postingBalanceCents,
        'profileComplete': profileComplete,
        'onboarded': onboarded,
        'blockedUserIds': blockedUserIds,
        'searchTerms': buildSearchTerms(displayName, skills, title),
      };

  static List<String> buildSearchTerms(
    String name,
    List<String> skills,
    String title,
  ) {
    final Set<String> terms = <String>{};
    for (final String source in <String>[name, title, ...skills]) {
      for (final String word
          in source.toLowerCase().split(RegExp(r'[^a-z0-9+#.]+'))) {
        if (word.length < 2) continue;
        terms.add(word);
        // Prefixes let "flu" match "flutter" with a simple array-contains.
        for (int i = 2; i <= word.length && i <= 8; i++) {
          terms.add(word.substring(0, i));
        }
      }
    }
    return terms.take(120).toList(growable: false);
  }

  AppUser copyWith({
    String? displayName,
    UserRole? role,
    String? title,
    String? bio,
    String? location,
    List<String>? skills,
    double? hourlyRate,
    String? teamSize,
    String? profilePhotoBase64,
    KycState? kyc,
    NotificationPrefs? notificationPrefs,
    int? trustScore,
    int? jobSuccess,
    int? jobsDone,
    int? totalEarnedCents,
    int? walletBalanceCents,
    int? postingBalanceCents,
    bool? profileComplete,
    bool? onboarded,
    List<String>? blockedUserIds,
  }) =>
      AppUser(
        uid: uid,
        email: email,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        title: title ?? this.title,
        bio: bio ?? this.bio,
        location: location ?? this.location,
        skills: skills ?? this.skills,
        hourlyRate: hourlyRate ?? this.hourlyRate,
        teamSize: teamSize ?? this.teamSize,
        profilePhotoBase64: profilePhotoBase64 ?? this.profilePhotoBase64,
        kyc: kyc ?? this.kyc,
        notificationPrefs: notificationPrefs ?? this.notificationPrefs,
        trustScore: trustScore ?? this.trustScore,
        jobSuccess: jobSuccess ?? this.jobSuccess,
        jobsDone: jobsDone ?? this.jobsDone,
        totalEarnedCents: totalEarnedCents ?? this.totalEarnedCents,
        walletBalanceCents: walletBalanceCents ?? this.walletBalanceCents,
        postingBalanceCents: postingBalanceCents ?? this.postingBalanceCents,
        profileComplete: profileComplete ?? this.profileComplete,
        onboarded: onboarded ?? this.onboarded,
        lastSeenAt: lastSeenAt,
        createdAt: createdAt,
        updatedAt: updatedAt,
        blockedUserIds: blockedUserIds ?? this.blockedUserIds,
        searchTerms: searchTerms,
      );
}
