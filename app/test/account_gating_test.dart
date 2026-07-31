import 'package:felicek/data/models/app_user.dart';
import 'package:felicek/data/models/chat.dart';
import 'package:felicek/data/models/user_role.dart';
import 'package:flutter_test/flutter_test.dart';

/// "No account without verification and a cleared payment" is the product's
/// central promise, so it gets its own tests. The Firestore rules enforce the
/// same predicate server-side — these cover the client half.
void main() {
  AppUser build({
    required UserRole role,
    bool idSubmitted = false,
    bool depositPaid = false,
    KycStage stage = KycStage.none,
    String? photo,
  }) =>
      AppUser(
        uid: 'u1',
        email: 'a@b.com',
        displayName: 'Test',
        role: role,
        profilePhotoBase64: photo,
        kyc: KycState(
          idSubmitted: idSubmitted,
          depositPaid: depositPaid,
          stage: stage,
        ),
      );

  group('Deposit policy', () {
    test('freelancers post a refundable trust bond', () {
      expect(UserRole.freelancer.depositCents, 2000);
      expect(UserRole.freelancer.depositKind, DepositKind.trustBond);
    });

    test('individual clients fund a posting balance', () {
      expect(UserRole.client.depositCents, 5000);
      expect(UserRole.client.depositKind, DepositKind.postingBalance);
    });

    test('agencies and startups post the same balance as clients', () {
      expect(UserRole.agency.depositCents, 5000);
      expect(UserRole.startup.depositCents, 5000);
    });

    test('every role requires a deposit — none is zero', () {
      for (final UserRole role in UserRole.values) {
        expect(role.depositCents, greaterThan(0),
            reason: '${role.key} must pay');
      }
    });

    test('only individual freelancers must show a photo', () {
      expect(UserRole.freelancer.requiresProfilePhoto, isTrue);
      expect(UserRole.client.requiresProfilePhoto, isFalse);
      expect(UserRole.agency.requiresProfilePhoto, isFalse);
      expect(UserRole.startup.requiresProfilePhoto, isFalse);
    });
  });

  group('KycState.isVerified', () {
    test('identity alone is not enough', () {
      final AppUser u = build(
        role: UserRole.client,
        idSubmitted: true,
        stage: KycStage.idSubmitted,
      );
      expect(u.kyc.isVerified, isFalse);
    });

    test('a deposit without the verified stage is not enough', () {
      final AppUser u = build(
        role: UserRole.client,
        idSubmitted: true,
        depositPaid: true,
        stage: KycStage.idSubmitted,
      );
      expect(u.kyc.isVerified, isFalse);
    });

    test('identity plus a cleared deposit verifies the account', () {
      final AppUser u = build(
        role: UserRole.client,
        idSubmitted: true,
        depositPaid: true,
        stage: KycStage.verified,
      );
      expect(u.kyc.isVerified, isTrue);
    });
  });

  group('meetsMandatoryRequirements', () {
    test('a verified freelancer without a photo is still incomplete', () {
      final AppUser u = build(
        role: UserRole.freelancer,
        idSubmitted: true,
        depositPaid: true,
        stage: KycStage.verified,
      );
      expect(u.kyc.isVerified, isTrue);
      expect(u.meetsMandatoryRequirements, isFalse);
      expect(u.canBid, isFalse);
    });

    test('a verified freelancer with a photo is complete', () {
      final AppUser u = build(
        role: UserRole.freelancer,
        idSubmitted: true,
        depositPaid: true,
        stage: KycStage.verified,
        photo: 'ZmFrZS1qcGVn',
      );
      expect(u.meetsMandatoryRequirements, isTrue);
      expect(u.canBid, isTrue);
    });

    test('an empty photo string does not satisfy the requirement', () {
      final AppUser u = build(
        role: UserRole.freelancer,
        idSubmitted: true,
        depositPaid: true,
        stage: KycStage.verified,
        photo: '',
      );
      expect(u.hasProfilePhoto, isFalse);
      expect(u.meetsMandatoryRequirements, isFalse);
    });

    test('an unverified client cannot post a job', () {
      final AppUser u = build(role: UserRole.client, idSubmitted: true);
      expect(u.canPostJob, isFalse);
    });

    test('a verified client can post a job without a photo', () {
      final AppUser u = build(
        role: UserRole.client,
        idSubmitted: true,
        depositPaid: true,
        stage: KycStage.verified,
      );
      expect(u.canPostJob, isTrue);
    });
  });

  group('Verification matches the security rules', () {
    // isAccountVerified() in firestore.rules checks idSubmitted, depositPaid
    // and stage together. The client checked only the last two, so an account
    // that paid before submitting documents read as verified here and
    // unverified there — the app unlocked posting and bidding and the write
    // was refused at the end. These pin all three.
    test('a cleared deposit alone is not verified', () {
      const KycState paidOnly = KycState(
        depositPaid: true,
        stage: KycStage.verified,
      );
      expect(paidOnly.isVerified, isFalse,
          reason: 'recordDeposit sets these two without touching idSubmitted');
    });

    test('documents alone are not verified', () {
      const KycState idOnly =
          KycState(idSubmitted: true, stage: KycStage.idSubmitted);
      expect(idOnly.isVerified, isFalse);
    });

    test('documents and deposit still need the verified stage', () {
      const KycState pending = KycState(idSubmitted: true, depositPaid: true);
      expect(pending.isVerified, isFalse);
    });

    test('all three together are verified', () {
      const KycState full = KycState(
        idSubmitted: true,
        depositPaid: true,
        stage: KycStage.verified,
      );
      expect(full.isVerified, isTrue);
    });

    test('posting and bidding follow the same predicate', () {
      final AppUser paidNoId = build(
        role: UserRole.client,
        depositPaid: true,
        stage: KycStage.verified,
      );
      expect(paidNoId.canPostJob, isFalse,
          reason: 'the rules would refuse the job write');

      final AppUser ready = build(
        role: UserRole.client,
        idSubmitted: true,
        depositPaid: true,
        stage: KycStage.verified,
      );
      expect(ready.canPostJob, isTrue);
    });
  });

  group('KYC progress', () {
    test('steps 20% → 60% → 100%', () {
      expect(const KycState().progress, 0.2);
      expect(const KycState(idSubmitted: true).progress, 0.6);
      expect(
        const KycState(idSubmitted: true, depositPaid: true).progress,
        1.0,
      );
    });

    test('a deposit without documents is not a full bar', () {
      expect(const KycState(depositPaid: true).progress, 0.2);
    });
  });

  group('Identity documents', () {
    test('passport and other government IDs are accepted as primary', () {
      expect(IdDocumentType.primary, contains(IdDocumentType.passport));
      expect(IdDocumentType.primary, contains(IdDocumentType.governmentId));
      expect(IdDocumentType.primary, contains(IdDocumentType.drivingLicence));
      expect(IdDocumentType.primary, contains(IdDocumentType.nationalId));
    });

    test('the birth certificate is secondary, not primary', () {
      expect(IdDocumentType.primary,
          isNot(contains(IdDocumentType.birthCertificate)));
    });
  });

  group('ChatThread.idFor', () {
    test('is stable regardless of argument order', () {
      expect(ChatThread.idFor('b', 'a'), ChatThread.idFor('a', 'b'));
    });

    test('scopes by job so the same pair can have separate threads', () {
      expect(
        ChatThread.idFor('a', 'b', jobId: 'job1'),
        isNot(ChatThread.idFor('a', 'b', jobId: 'job2')),
      );
      expect(ChatThread.idFor('a', 'b', jobId: ''), ChatThread.idFor('a', 'b'));
    });
  });
}
