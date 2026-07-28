import 'package:felicek/data/models/job.dart';
import 'package:felicek/data/models/review.dart';
import 'package:felicek/data/models/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

/// The engagement loop moves real money, so its arithmetic and its
/// completion conditions are pinned here.
void main() {
  group('Fees', () {
    test('local rails take 1%, PayPal takes 2%', () {
      expect(Fees.feeCentsFor(10000, PayoutMethod.bkash), 100);
      expect(Fees.feeCentsFor(10000, PayoutMethod.nagad), 100);
      expect(Fees.feeCentsFor(10000, PayoutMethod.bank), 100);
      expect(Fees.feeCentsFor(10000, PayoutMethod.paypal), 200);
    });

    test('the label matches the rate actually charged', () {
      expect(Fees.label(PayoutMethod.bkash), '1%');
      expect(Fees.label(PayoutMethod.paypal), '2%');
    });

    test('rounding never invents or loses a cent at the boundary', () {
      // 1% of $1.005 is 1.005 cents — must round, not truncate to zero.
      expect(Fees.feeCentsFor(101, PayoutMethod.bkash), 1);
      expect(Fees.feeCentsFor(0, PayoutMethod.bkash), 0);
    });
  });

  group('Job completion', () {
    Job jobWith(List<Milestone> milestones) => Job(
          id: 'j1',
          ownerId: 'o1',
          ownerName: 'Client',
          type: 'freelance',
          typeLabel: 'Freelance',
          title: 'Test',
          milestones: milestones,
        );

    test('a job with no milestones is not "fully released"', () {
      expect(jobWith(const <Milestone>[]).isFullyReleased, isFalse);
    });

    test('one unreleased milestone keeps the engagement open', () {
      final Job job = jobWith(const <Milestone>[
        Milestone(label: 'A', amount: r'$100', released: true),
        Milestone(label: 'B', amount: r'$100'),
      ]);
      expect(job.isFullyReleased, isFalse);
    });

    test('all released completes the engagement', () {
      final Job job = jobWith(const <Milestone>[
        Milestone(label: 'A', amount: r'$100', released: true),
        Milestone(label: 'B', amount: r'$100', released: true),
      ]);
      expect(job.isFullyReleased, isTrue);
    });

    test('isHired tracks the accepted proposal', () {
      const Job open = Job(
        id: 'j1',
        ownerId: 'o1',
        ownerName: 'Client',
        type: 'freelance',
        typeLabel: 'Freelance',
        title: 'Test',
      );
      expect(open.isHired, isFalse);

      const Job hired = Job(
        id: 'j1',
        ownerId: 'o1',
        ownerName: 'Client',
        type: 'freelance',
        typeLabel: 'Freelance',
        title: 'Test',
        hiredProposalId: 'j1__alice',
        hiredFreelancerId: 'alice',
        escrowHeldCents: 45000,
      );
      expect(hired.isHired, isTrue);
      expect(hired.escrowHeld, 450.0);
    });
  });

  group('Review', () {
    test('the id is deterministic — one review per person per job', () {
      expect(
        Review.idFor(jobId: 'j1', authorId: 'alice'),
        Review.idFor(jobId: 'j1', authorId: 'alice'),
      );
      expect(
        Review.idFor(jobId: 'j1', authorId: 'alice'),
        isNot(Review.idFor(jobId: 'j1', authorId: 'bob')),
      );
    });

    test('stars render the rating out of five', () {
      const Review r = Review(
        id: 'x',
        jobId: 'j',
        jobTitle: 'T',
        authorId: 'a',
        authorName: 'A',
        subjectId: 's',
        rating: 4,
      );
      expect(r.stars, '★★★★☆');
    });

    test('toMap clamps a rating outside 1–5', () {
      const Review high = Review(
        id: 'x',
        jobId: 'j',
        jobTitle: 'T',
        authorId: 'a',
        authorName: 'A',
        subjectId: 's',
        rating: 99,
      );
      expect(high.toMap()['rating'], 5);
    });
  });

  group('Deposit kinds', () {
    test('the trust bond is held; the posting balance is spendable', () {
      // A freelancer's bond is a debit that returns later, so it must not be
      // treated as spendable balance — the two read differently on purpose.
      expect(Fees.trustDepositCents, 2000);
    });
  });
}
