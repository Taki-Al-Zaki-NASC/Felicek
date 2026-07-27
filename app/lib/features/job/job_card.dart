import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/f_pill.dart';
import '../../core/widgets/f_surface.dart';
import '../../data/models/job.dart';

/// The listing card from the browse feed and "Your Listings" — a `FCard`
/// with the type tag, budget, title, summary, skill tags and trust pills.
class JobCard extends StatelessWidget {
  const JobCard(
      {super.key,
      required this.job,
      required this.onTap,
      this.compact = false});

  final Job job;
  final VoidCallback onTap;

  /// Owner's own listing view — drops the summary/skills, adds a proposal
  /// count pill instead of a trust pill.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FCard(
      radius: FRadius.cardLg,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              FPill.violet(job.typeLabel, fontSize: 10),
              Text(job.budget, style: FType.money),
            ],
          ),
          const SizedBox(height: FSpace.md),
          Text(job.title, style: FType.displayXs),
          if (!compact) ...<Widget>[
            const SizedBox(height: FSpace.md),
            Text(
              job.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: FType.supportSm,
            ),
            if (job.skills.isNotEmpty) ...<Widget>[
              const SizedBox(height: FSpace.lg),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final String skill in job.skills.take(4)) FTag(skill),
                ],
              ),
            ],
          ],
          const SizedBox(height: FSpace.lg),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (compact)
                FPill.blue('${job.proposalsCount} proposals')
              else
                FPill.teal('${job.trustScore}% Verified'),
              if (job.escrowFunded) FPill.blue('Escrow Funded'),
              if (job.hasChallenge) FPill.violet('Skill Test'),
            ],
          ),
        ],
      ),
    );
  }
}
