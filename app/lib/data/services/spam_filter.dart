import '../models/job.dart';

/// The "AI spam filter" the design surfaces on the proposal queue, implemented
/// as an on-device heuristic.
///
/// It runs client-side on purpose: no server, no model hosting bill, and the
/// score is written alongside the proposal so the client sees the same verdict
/// the freelancer's device computed. The rules mirror what actually makes a
/// freelance proposal generic — no reference to the listing, boilerplate
/// openers, near-zero specificity, absurd lowballing.
class SpamFilter {
  const SpamFilter._();

  /// Proposals scoring at or above this are flagged rather than delivered.
  static const int flagThreshold = 60;

  static const List<String> _boilerplate = <String>[
    'dear sir/madam',
    'dear sir or madam',
    'i am the best candidate',
    'i can do this job easily',
    'please give me a chance',
    'i will work day and night',
    'kindly award me this project',
    'i am expert in everything',
    'lowest price guaranteed',
    'ready to start immediately sir',
  ];

  /// 0–100. Higher is more likely to be spam.
  static int score({
    required String coverNote,
    required Job job,
    required double bidAmount,
    required bool challengeCompleted,
    required int trustScore,
  }) {
    final String note = coverNote.trim().toLowerCase();
    int points = 0;

    // 1. Length. A two-line pitch for a $12,000 rebuild is not a pitch.
    if (note.isEmpty) {
      points += 45;
    } else if (note.length < 60) {
      points += 30;
    } else if (note.length < 140) {
      points += 12;
    }

    // 2. Boilerplate openers.
    for (final String phrase in _boilerplate) {
      if (note.contains(phrase)) {
        points += 18;
        break;
      }
    }

    // 3. Specificity — does the note reference the listing at all?
    final Set<String> jobWords = _significantWords(
      '${job.title} ${job.summary} ${job.skills.join(' ')}',
    );
    final Set<String> noteWords = _significantWords(note);
    final int overlap = jobWords.intersection(noteWords).length;
    if (jobWords.isNotEmpty) {
      final double ratio = overlap / jobWords.length;
      if (ratio < 0.05) {
        points += 25;
      } else if (ratio < 0.12) {
        points += 12;
      } else if (ratio > 0.3) {
        points -= 10;
      }
    }

    // 4. Skipping a challenge the client explicitly asked for.
    if (job.hasChallenge && !challengeCompleted) points += 20;

    // 5. Extreme lowballing — the classic volume-spam signal.
    final double? budget = job.budgetValue;
    if (budget != null && budget > 0 && bidAmount > 0) {
      final double ratio = bidAmount / budget;
      if (ratio < 0.25) {
        points += 22;
      } else if (ratio < 0.5) {
        points += 8;
      }
    }

    // 6. Link dumping.
    if (RegExp(r'https?://').allMatches(note).length > 3) points += 15;

    // 7. Established trust earns the benefit of the doubt.
    if (trustScore >= 90) {
      points -= 20;
    } else if (trustScore >= 75) {
      points -= 10;
    } else if (trustScore < 50) {
      points += 10;
    }

    return points.clamp(0, 100);
  }

  static bool isSpam({
    required String coverNote,
    required Job job,
    required double bidAmount,
    required bool challengeCompleted,
    required int trustScore,
  }) =>
      score(
        coverNote: coverNote,
        job: job,
        bidAmount: bidAmount,
        challengeCompleted: challengeCompleted,
        trustScore: trustScore,
      ) >=
      flagThreshold;

  /// A short explanation the freelancer sees before they waste a submission.
  static String? advice({
    required String coverNote,
    required Job job,
    required double bidAmount,
    required bool challengeCompleted,
  }) {
    if (coverNote.trim().length < 60) {
      return 'Add more detail — proposals under 60 characters are almost always filtered out.';
    }
    if (job.hasChallenge && !challengeCompleted) {
      return 'Take the skill challenge first — proposals that skip it are ranked last.';
    }
    final double? budget = job.budgetValue;
    if (budget != null && bidAmount > 0 && bidAmount < budget * 0.25) {
      return 'That bid is far below the posted budget, which the spam filter treats as a red flag.';
    }
    final Set<String> jobWords =
        _significantWords('${job.title} ${job.summary}');
    final Set<String> noteWords = _significantWords(coverNote);
    if (jobWords.isNotEmpty &&
        jobWords.intersection(noteWords).length / jobWords.length < 0.05) {
      return 'Mention something specific from the listing so this does not read as a template.';
    }
    return null;
  }

  static const Set<String> _stopWords = <String>{
    'the',
    'and',
    'for',
    'with',
    'you',
    'your',
    'our',
    'that',
    'this',
    'from',
    'have',
    'has',
    'will',
    'can',
    'are',
    'was',
    'were',
    'but',
    'not',
    'all',
    'need',
    'want',
    'work',
    'job',
    'project',
    'looking',
    'must',
    'should',
  };

  static Set<String> _significantWords(String source) => source
      .toLowerCase()
      .split(RegExp(r'[^a-z0-9+#.]+'))
      .where((String w) => w.length > 3 && !_stopWords.contains(w))
      .toSet();
}
