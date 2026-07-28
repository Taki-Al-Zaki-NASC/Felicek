import 'package:felicek/data/models/wallet.dart';
import 'package:flutter_test/flutter_test.dart';

/// These numbers are shown to people about their own money, so the arithmetic
/// is pinned rather than trusted.
void main() {
  group('Gateway charge', () {
    test('card is a percentage plus a flat charge', () {
      // $100.00 → 2.9% ($2.90) + $0.30 = $3.20
      expect(GatewaySchedule.card.chargeCentsFor(10000), 320);
    });

    test('local rails have no flat charge', () {
      expect(GatewaySchedule.local.chargeCentsFor(10000), 200);
    });

    test('a zero amount is charged nothing, not the flat fee', () {
      // Otherwise an empty cart would show a 30c charge.
      expect(GatewaySchedule.card.chargeCentsFor(0), 0);
      expect(GatewaySchedule.card.chargeCentsFor(-500), 0);
    });

    test('the rate label reads the way the schedule actually charges', () {
      expect(GatewaySchedule.card.rateLabel, '2.9% + \$0.30');
      expect(GatewaySchedule.local.rateLabel, '2%');
    });
  });

  group('Breakdown', () {
    test('gateway and platform fees stay separate', () {
      final FeeBreakdown b = FeeBreakdown.of(10000, GatewaySchedule.card);
      expect(b.gatewayCents, 320);
      expect(b.platformCents, 100); // 1% of $100
      expect(b.totalFeeCents, 420);
      // The whole point: these must never be collapsed into one number.
      expect(b.gatewayCents, isNot(b.totalFeeCents));
    });

    test('a payout deducts the fees', () {
      final FeeBreakdown b = FeeBreakdown.of(10000, GatewaySchedule.local);
      expect(b.netCents, 10000 - 200 - 100);
    });

    test('a deposit adds the fees on top', () {
      final FeeBreakdown b = FeeBreakdown.of(5000, GatewaySchedule.card);
      // $50 deposit: 2.9% ($1.45) + $0.30 + 1% ($0.50) = $2.25 → $52.25
      expect(b.gatewayCents, 175);
      expect(b.platformCents, 50);
      expect(b.grossPlusFeesCents, 5225);
    });

    test('net never goes negative when the flat fee exceeds the amount', () {
      // 20c transfer: the 30c flat charge alone is larger than the payment.
      final FeeBreakdown b = FeeBreakdown.of(20, GatewaySchedule.card);
      expect(b.totalFeeCents, greaterThan(b.grossCents));
      expect(b.netCents, 0);
      expect(b.feesExceedAmount, isTrue);
    });

    test('a normal transfer does not trip the fees-exceed warning', () {
      expect(
        FeeBreakdown.of(10000, GatewaySchedule.card).feesExceedAmount,
        isFalse,
      );
    });

    test('zero is not flagged as fee-swamped', () {
      // Nothing has been entered yet; warning about it would be noise.
      expect(FeeBreakdown.of(0, GatewaySchedule.card).feesExceedAmount, isFalse);
    });

    test('PayPal maps to card rates, local methods to local', () {
      expect(Fees.breakdown(10000, PayoutMethod.paypal).gatewayCents, 320);
      expect(Fees.breakdown(10000, PayoutMethod.bkash).gatewayCents, 200);
    });

    test('the Felicek fee is 1% regardless of gateway', () {
      for (final GatewaySchedule s in GatewaySchedule.all) {
        expect(FeeBreakdown.of(10000, s).platformCents, 100);
      }
    });
  });
}
