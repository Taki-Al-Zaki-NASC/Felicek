import 'package:felicek/data/models/job.dart';
import 'package:felicek/data/services/spam_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// The spam filter decides whether a real freelancer's proposal reaches a
/// client at all, so false positives matter as much as false negatives.
void main() {
  const Job job = Job(
    id: 'j1',
    ownerId: 'o1',
    ownerName: 'FinNova',
    type: 'freelance',
    typeLabel: 'Freelance',
    title: 'Design a Flutter Onboarding Flow',
    summary:
        'Need 5 polished onboarding screens for a fintech app, Material 3.',
    budget: r'$450',
    budgetValue: 450,
    skills: <String>['Flutter', 'UI/UX', 'Figma'],
    challenge: SkillChallenge(
      enabled: true,
      prompt: 'Recreate this bottom-sheet spec.',
    ),
  );

  const String goodNote =
      'I have shipped several Flutter onboarding flows for fintech products. '
      'I would deliver the five screens in Material 3 with Figma sources and '
      'exported assets, matching the dark theme spec you described.';

  test('a specific, challenge-completed proposal passes', () {
    final int score = SpamFilter.score(
      coverNote: goodNote,
      job: job,
      bidAmount: 430,
      challengeCompleted: true,
      trustScore: 98,
    );
    expect(score, lessThan(SpamFilter.flagThreshold));
  });

  test('an empty proposal is flagged', () {
    expect(
      SpamFilter.isSpam(
        coverNote: '',
        job: job,
        bidAmount: 400,
        challengeCompleted: false,
        trustScore: 50,
      ),
      isTrue,
    );
  });

  test('boilerplate plus an absurd lowball is flagged', () {
    expect(
      SpamFilter.isSpam(
        coverNote:
            'Dear Sir/Madam, I am the best candidate. Please give me a chance.',
        job: job,
        bidAmount: 50,
        challengeCompleted: false,
        trustScore: 40,
      ),
      isTrue,
    );
  });

  test('a high trust score buys benefit of the doubt over a borderline note',
      () {
    // A note thin enough to accrue penalties, so the trust adjustment is
    // visible rather than clamped away at the 0 floor.
    const String borderline =
        'Can do this onboarding work, have Flutter experience.';
    final int trusted = SpamFilter.score(
      coverNote: borderline,
      job: job,
      bidAmount: 430,
      challengeCompleted: false,
      trustScore: 95,
    );
    final int untrusted = SpamFilter.score(
      coverNote: borderline,
      job: job,
      bidAmount: 430,
      challengeCompleted: false,
      trustScore: 30,
    );
    expect(trusted, lessThan(untrusted));
  });

  test('scores stay inside 0–100', () {
    final int worst = SpamFilter.score(
      coverNote: '',
      job: job,
      bidAmount: 1,
      challengeCompleted: false,
      trustScore: 0,
    );
    final int best = SpamFilter.score(
      coverNote: goodNote,
      job: job,
      bidAmount: 450,
      challengeCompleted: true,
      trustScore: 100,
    );
    expect(worst, inInclusiveRange(0, 100));
    expect(best, inInclusiveRange(0, 100));
  });

  group('advice', () {
    test('calls out a too-short note first', () {
      expect(
        SpamFilter.advice(
          coverNote: 'hi',
          job: job,
          bidAmount: 400,
          challengeCompleted: true,
        ),
        contains('60 characters'),
      );
    });

    test('nudges toward the challenge when it was skipped', () {
      expect(
        SpamFilter.advice(
          coverNote: goodNote,
          job: job,
          bidAmount: 430,
          challengeCompleted: false,
        ),
        contains('skill challenge'),
      );
    });

    test('says nothing when the proposal is solid', () {
      expect(
        SpamFilter.advice(
          coverNote: goodNote,
          job: job,
          bidAmount: 430,
          challengeCompleted: true,
        ),
        isNull,
      );
    });
  });
}
