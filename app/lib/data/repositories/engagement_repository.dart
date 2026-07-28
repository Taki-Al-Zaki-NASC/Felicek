import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import '../models/job.dart';
import '../models/proposal.dart';
import '../models/review.dart';
import '../models/wallet.dart';
import '../services/firestore_refs.dart';

/// The money-and-outcome half of the marketplace: hiring, releasing escrow
/// milestone by milestone, completing an engagement, and reviewing it.
///
/// This is the loop the rest of the product exists to serve, so it is kept in
/// one place rather than smeared across the job and proposal repositories —
/// releasing a milestone touches the job, the proposal, two wallets, the
/// ledger and (on the final milestone) both parties' reputation, and those
/// have to move together.
class EngagementRepository {
  EngagementRepository(this._db);

  final Db _db;

  // ── Hiring ──────────────────────────────────────────────────────────────

  /// Accepts a proposal: marks it hired, declines the rest, and moves the
  /// job's budget from the client's posting balance into escrow.
  ///
  /// Runs as one Firestore transaction so a client cannot hire two people for
  /// the same budget by double-tapping.
  Future<void> hire({
    required Job job,
    required Proposal proposal,
    required String chatId,
  }) async {
    final DocumentReference<Json> clientRef = _db.user(job.ownerId);

    await _db.firestore.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Json> clientSnap = await tx.get(clientRef);
      final int posting =
          (clientSnap.data()?['postingBalanceCents'] as num?)?.toInt() ?? 0;
      if (posting < proposal.bidAmountCents) {
        throw InsufficientPostingBalance(
          'Your posting balance is \$${(posting / 100).toStringAsFixed(2)} — '
          'top it up to \$${(proposal.bidAmountCents / 100).toStringAsFixed(2)} '
          'before hiring.',
        );
      }

      tx.update(clientRef, <String, dynamic>{
        'postingBalanceCents': posting - proposal.bidAmountCents,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(
        _db.proposal(proposal.id),
        <String, dynamic>{
          'status': ProposalStatus.accepted.name,
          'chatId': chatId,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      tx.set(
        _db.job(job.id),
        <String, dynamic>{
          'status': JobStatus.filled.name,
          'hiredProposalId': proposal.id,
          'hiredFreelancerId': proposal.freelancerId,
          'escrowHeldCents': proposal.bidAmountCents,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    await _notify(
      recipientId: proposal.freelancerId,
      kind: NotificationKind.proposalAccepted,
      title: 'You were hired',
      body: '${job.title} — escrow is funded and the first milestone is live.',
      jobId: job.id,
      proposalId: proposal.id,
      actorId: job.ownerId,
    );

    await _system(
      chatId: chatId,
      actorId: job.ownerId,
      text: 'Hired · ${proposal.bidLabel} escrowed for "${job.title}"',
    );
  }

  Future<void> shortlist({required Proposal proposal, required bool on}) async {
    await _db.proposal(proposal.id).set(<String, dynamic>{
      'status':
          (on ? ProposalStatus.shortlisted : ProposalStatus.submitted).name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    try {
      await _db.job(proposal.jobId).update(<String, dynamic>{
        'shortlisted': FieldValue.increment(on ? 1 : -1),
      });
    } on FirebaseException {
      // The counter is cosmetic; never fail the shortlist over it.
    }

    if (on) {
      await _notify(
        recipientId: proposal.freelancerId,
        kind: NotificationKind.proposal,
        title: 'You were shortlisted',
        body: '${proposal.jobTitle} — the client shortlisted your proposal.',
        jobId: proposal.jobId,
        proposalId: proposal.id,
        actorId: proposal.jobOwnerId,
      );
    }
  }

  // ── Escrow release ──────────────────────────────────────────────────────

  /// Releases one milestone's funds to the hired freelancer, net of the flat
  /// platform fee, and writes both ledger lines.
  ///
  /// When it is the last unreleased milestone the engagement completes: the
  /// job closes, the freelancer's job count and success rate move, and — if
  /// this was their first completed job — their trust bond unlocks for
  /// withdrawal. That last bit is the promise the deposit screen makes, so it
  /// happens here rather than being left to a manual step.
  Future<void> releaseMilestone({
    required Job job,
    required Proposal proposal,
    required int milestoneIndex,
    PayoutMethod method = PayoutMethod.bkash,
  }) async {
    final Milestone milestone = job.milestones[milestoneIndex];
    if (milestone.released) return;

    final int amountCents = milestoneCents(milestone, job, proposal);
    final int feeCents = Fees.feeCentsFor(amountCents, method);
    final int netCents = amountCents - feeCents;

    final List<Milestone> updated = <Milestone>[
      for (int i = 0; i < job.milestones.length; i++)
        if (i == milestoneIndex)
          Milestone(
            label: job.milestones[i].label,
            amount: job.milestones[i].amount,
            released: true,
          )
        else
          job.milestones[i],
    ];
    final bool isFinal = updated.every((Milestone m) => m.released);

    final DocumentReference<Json> freelancerRef =
        _db.user(proposal.freelancerId);
    final DocumentReference<Json> creditRef =
        _db.transactions(proposal.freelancerId).doc();
    final DocumentReference<Json> feeRef =
        _db.transactions(proposal.freelancerId).doc();

    await _db.firestore.runTransaction((Transaction tx) async {
      final DocumentSnapshot<Json> snap = await tx.get(freelancerRef);
      final Json data = snap.data() ?? <String, dynamic>{};
      final int balance = (data['walletBalanceCents'] as num?)?.toInt() ?? 0;
      final int earned = (data['totalEarnedCents'] as num?)?.toInt() ?? 0;
      final int jobsDone = (data['jobsDone'] as num?)?.toInt() ?? 0;
      final Map<String, dynamic> kyc =
          Map<String, dynamic>.from(data['kyc'] as Map? ?? <String, dynamic>{});

      final Map<String, dynamic> freelancerUpdate = <String, dynamic>{
        'walletBalanceCents': balance + netCents,
        'totalEarnedCents': earned + amountCents,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (isFinal) {
        freelancerUpdate['jobsDone'] = jobsDone + 1;
        // First completed job unlocks the refundable trust bond.
        if (kyc['depositReleased'] != true) {
          freelancerUpdate['kyc'] = <String, dynamic>{'depositReleased': true};
        }
      }

      tx.set(freelancerRef, freelancerUpdate, SetOptions(merge: true));

      tx.set(creditRef, <String, dynamic>{
        ...WalletTransaction(
          id: creditRef.id,
          label: 'Escrow release — ${milestone.label}',
          amountCents: amountCents,
          kind: TxKind.escrowRelease,
          jobId: job.id,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (feeCents > 0) {
        tx.set(feeRef, <String, dynamic>{
          ...WalletTransaction(
            id: feeRef.id,
            label: 'Platform maintenance fee (${Fees.label(method)})',
            amountCents: -feeCents,
            kind: TxKind.platformFee,
            jobId: job.id,
          ).toMap(),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      tx.set(
        _db.job(job.id),
        <String, dynamic>{
          'milestones': updated.map((Milestone m) => m.toMap()).toList(),
          'escrowHeldCents': FieldValue.increment(-amountCents),
          if (isFinal) 'status': JobStatus.closed.name,
          if (isFinal) 'completedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (isFinal) {
        tx.set(
          _db.proposal(proposal.id),
          <String, dynamic>{
            'status': ProposalStatus.completed.name,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      }
    });

    // Mirror the freelancer's updated counts onto their public profile.
    if (isFinal) {
      try {
        await _db.profile(proposal.freelancerId).set(<String, dynamic>{
          'jobsDone': FieldValue.increment(1),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } on FirebaseException {
        // Cosmetic mirror; the private record is the source of truth.
      }
    }

    await _notify(
      recipientId: proposal.freelancerId,
      kind: NotificationKind.payout,
      title: isFinal ? 'Final milestone released' : 'Milestone released',
      body: '${milestone.label} — \$${(netCents / 100).toStringAsFixed(2)} '
          'is now in your wallet.',
      jobId: job.id,
      proposalId: proposal.id,
      actorId: job.ownerId,
    );

    if (proposal.chatId != null) {
      await _system(
        chatId: proposal.chatId!,
        actorId: job.ownerId,
        text: isFinal
            ? 'Final milestone released · engagement complete'
            : 'Milestone released · ${milestone.label}',
      );
    }
  }

  /// Milestone amounts are free text in the design (`$100`, `TBD`). Parse
  /// what we can; otherwise split the accepted bid evenly so a release never
  /// silently pays zero.
  /// Public so the UI can show a fee breakdown for the *same* number this
  /// class will actually charge. A screen recomputing it independently would
  /// eventually disagree with the ledger, and the person would be told one
  /// figure and paid another.
  static int milestoneCents(Milestone milestone, Job job, Proposal proposal) {
    final RegExpMatch? m =
        RegExp(r'\$\s*([\d,]+(?:\.\d+)?)').firstMatch(milestone.amount);
    if (m != null) {
      final double? value = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (value != null && value > 0) return (value * 100).round();
    }
    final int count = job.milestones.isEmpty ? 1 : job.milestones.length;
    return (proposal.bidAmountCents / count).round();
  }

  // ── Reviews ─────────────────────────────────────────────────────────────

  Stream<List<Review>> watchReviewsFor(String subjectId, {int limit = 20}) =>
      _db.reviews
          .where('subjectId', isEqualTo: subjectId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .snapshots()
          .map((JsonQuerySnap s) =>
              s.docs.map(Review.fromDoc).toList(growable: false));

  Future<Review?> myReviewFor({
    required String jobId,
    required String authorId,
  }) async {
    final DocumentSnapshot<Json> doc =
        await _db.review(Review.idFor(jobId: jobId, authorId: authorId)).get();
    return doc.exists ? Review.fromDoc(doc) : null;
  }

  /// Leaves (or edits) a review, and recomputes the subject's job-success
  /// score from the average rating so the profile number means something.
  Future<void> leaveReview(Review review) async {
    await _db.review(review.id).set(<String, dynamic>{
      ...review.toMap(),
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    try {
      final JsonQuerySnap all = await _db.reviews
          .where('subjectId', isEqualTo: review.subjectId)
          .limit(200)
          .get();
      if (all.docs.isEmpty) return;
      final double avg = all.docs
              .map((QueryDocumentSnapshot<Json> d) =>
                  (d.data()['rating'] as num?)?.toDouble() ?? 5)
              .reduce((double a, double b) => a + b) /
          all.docs.length;
      final int successPercent = ((avg / 5) * 100).round();

      await _db.profile(review.subjectId).set(<String, dynamic>{
        'jobSuccess': successPercent,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException {
      // The review itself is saved; the aggregate can catch up later.
    }

    await _notify(
      recipientId: review.subjectId,
      kind: NotificationKind.system,
      title: 'New review',
      body: '${review.authorName} left you ${review.rating}/5 on '
          '"${review.jobTitle}".',
      jobId: review.jobId,
      actorId: review.authorId,
      actorName: review.authorName,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Future<void> _system({
    required String chatId,
    required String actorId,
    required String text,
  }) async {
    try {
      final String id = _db.messages(chatId).doc().id;
      final WriteBatch batch = _db.firestore.batch();
      batch.set(_db.message(chatId, id), <String, dynamic>{
        'senderId': actorId,
        'senderName': 'Felicek',
        'text': text,
        'type': 'system',
        'sentAt': FieldValue.serverTimestamp(),
        'clientSentAt': Timestamp.now(),
      });
      batch.set(
        _db.chat(chatId),
        <String, dynamic>{
          'lastMessagePreview': text,
          'lastMessageSenderId': actorId,
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastMessageType': 'system',
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await batch.commit();
    } on FirebaseException {
      // An event line is context, never worth failing the action it describes.
    }
  }

  Future<void> _notify({
    required String recipientId,
    required NotificationKind kind,
    required String title,
    required String body,
    String? jobId,
    String? proposalId,
    String? actorId,
    String? actorName,
  }) async {
    try {
      await _db.notifications(recipientId).add(<String, dynamic>{
        ...AppNotification(
          id: '',
          kind: kind,
          title: title,
          body: body,
          jobId: jobId,
          proposalId: proposalId,
          actorId: actorId,
          actorName: actorName,
        ).toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      // Additive only.
    }
  }
}

/// Raised when a client tries to hire beyond their funded posting balance.
class InsufficientPostingBalance implements Exception {
  const InsufficientPostingBalance(this.message);

  final String message;

  @override
  String toString() => message;
}
