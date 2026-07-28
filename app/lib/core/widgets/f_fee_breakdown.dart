import 'package:flutter/material.dart';

import '../../data/models/wallet.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../utils/formatters.dart';

/// Shows exactly where the money goes, itemised.
///
/// Two separate fees, never blended: the payment gateway's charge is a cost
/// passed through from a third party, and the 1% is what Felicek takes.
/// Collapsing them into one number is how a platform that says it charges 1%
/// ends up charging four, so this widget refuses to do it.
class FFeeBreakdown extends StatelessWidget {
  const FFeeBreakdown({
    super.key,
    required this.breakdown,
    this.mode = FeeDisplayMode.deducted,
    this.compact = false,
  });

  final FeeBreakdown breakdown;

  /// Whether the fees come off the amount (a payout) or go on top of it
  /// (a deposit). Same arithmetic, opposite direction, and getting it
  /// backwards misstates the number that matters.
  final FeeDisplayMode mode;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool deducted = mode == FeeDisplayMode.deducted;

    return Container(
      padding: EdgeInsets.all(compact ? 12 : 14),
      decoration: BoxDecoration(
        color: FColors.surface,
        borderRadius: FRadius.fieldR,
        border: Border.all(color: FColors.border),
      ),
      child: Column(
        children: <Widget>[
          _Line(
            label: deducted ? 'Milestone amount' : 'Deposit',
            value: Fmt.moneyExact(breakdown.gross),
          ),
          const SizedBox(height: FSpace.md),
          _Line(
            label: '${breakdown.schedule.label} processing '
                '(${breakdown.schedule.rateLabel})',
            value: '${deducted ? '−' : '+'} '
                '${Fmt.moneyExact(breakdown.gatewayFee)}',
            muted: true,
          ),
          const SizedBox(height: FSpace.sm),
          _Line(
            label: 'Felicek fee (1%)',
            value: '${deducted ? '−' : '+'} '
                '${Fmt.moneyExact(breakdown.platformFee)}',
            muted: true,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Divider(height: 1, color: FColors.borderFaint),
          ),
          _Line(
            label: deducted ? 'You receive' : 'Total charged',
            value: Fmt.moneyExact(
              deducted ? breakdown.net : breakdown.grossPlusFeesCents / 100,
            ),
            emphasised: true,
          ),
          // On a small transfer the gateway's flat charge can swallow the
          // whole amount. Saying so beats rendering a confident "$0.00".
          if (deducted && breakdown.feesExceedAmount) ...<Widget>[
            const SizedBox(height: FSpace.md),
            Text(
              'Fees come to more than this amount — the flat processing charge '
              'does not scale down. Release a larger milestone, or fewer, '
              'bigger ones.',
              style: FType.captionSm.copyWith(color: FColors.danger),
            ),
          ],
        ],
      ),
    );
  }
}

enum FeeDisplayMode {
  /// Fees come out of the amount (milestone release, payout).
  deducted,

  /// Fees are added on top (deposit, checkout).
  added,
}

class _Line extends StatelessWidget {
  const _Line({
    required this.label,
    required this.value,
    this.muted = false,
    this.emphasised = false,
  });

  final String label;
  final String value;
  final bool muted;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final TextStyle labelStyle = emphasised
        ? FType.bodyXs.copyWith(fontWeight: FontWeight.w600)
        : FType.captionSm.copyWith(
            fontSize: 11.5,
            color: muted ? FColors.inkMuted : FColors.ink,
          );
    final TextStyle valueStyle = emphasised
        ? FType.titleXs.copyWith(fontWeight: FontWeight.w700)
        : FType.captionSm.copyWith(
            fontSize: 11.5,
            color: muted ? FColors.inkMuted : FColors.ink,
          );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Flexible(child: Text(label, style: labelStyle)),
        const SizedBox(width: FSpace.lg),
        Text(value, style: valueStyle),
      ],
    );
  }
}
