import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { breakdown, CARD, LOCAL, gatewayCharge, rateLabel } from '../fees.ts';

/**
 * These assertions are copied from app/test/fee_breakdown_test.dart on
 * purpose. The two stacks compute fees independently, so the only thing
 * stopping them drifting is that both are pinned to the same numbers.
 */

test('card is a percentage plus a flat charge', () => {
  assert.equal(gatewayCharge(CARD, 10000), 320); // 2.9% + $0.30
});

test('local rails have no flat charge', () => {
  assert.equal(gatewayCharge(LOCAL, 10000), 200);
});

test('a zero amount is charged nothing, not the flat fee', () => {
  assert.equal(gatewayCharge(CARD, 0), 0);
  assert.equal(gatewayCharge(CARD, -500), 0);
});

test('rate labels read the way the schedule charges', () => {
  assert.equal(rateLabel(CARD), '2.9% + $0.30');
  assert.equal(rateLabel(LOCAL), '2%');
});

test('gateway and platform fees stay separate', () => {
  const b = breakdown(10000, CARD);
  assert.equal(b.gatewayCents, 320);
  assert.equal(b.platformCents, 100);
  assert.equal(b.totalFeeCents, 420);
  assert.notEqual(b.gatewayCents, b.totalFeeCents);
});

test('a payout deducts the fees', () => {
  assert.equal(breakdown(10000, LOCAL).netCents, 10000 - 200 - 100);
});

test('a deposit adds the fees on top', () => {
  const b = breakdown(5000, CARD);
  assert.equal(b.gatewayCents, 175);
  assert.equal(b.platformCents, 50);
  assert.equal(b.grossPlusFeesCents, 5225);
});

test('net never goes negative when the flat fee exceeds the amount', () => {
  const b = breakdown(20, CARD);
  assert.ok(b.totalFeeCents > b.grossCents);
  assert.equal(b.netCents, 0);
  assert.equal(b.feesExceedAmount, true);
});

test('zero is not flagged as fee-swamped', () => {
  assert.equal(breakdown(0, CARD).feesExceedAmount, false);
});

test('the Felicek fee is 1% regardless of gateway', () => {
  for (const s of [CARD, LOCAL]) {
    assert.equal(breakdown(10000, s).platformCents, 100);
  }
});
