import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { PER_BUYER, PER_ORIGIN, assess, assessAll } from '../throttle.ts';

const NOW = 1_800_000_000_000;
const MIN = 60_000;

test('a clean record is allowed with the full budget', () => {
  const a = assess([], NOW, PER_BUYER);
  assert.equal(a.allowed, true);
  assert.equal(a.remaining, PER_BUYER.max);
  assert.equal(a.retryAfterMs, 0);
  assert.equal(a.message, null);
});

test('the budget is spent one failure at a time', () => {
  const a = assess([NOW - MIN, NOW - 2 * MIN], NOW, PER_BUYER);
  assert.equal(a.allowed, true);
  assert.equal(a.remaining, PER_BUYER.max - 2);
});

test('a burst of failures closes the door', () => {
  const failures = Array.from({ length: PER_BUYER.max }, (_, i) => NOW - i * 1000);
  const a = assess(failures, NOW, PER_BUYER);
  assert.equal(a.allowed, false);
  assert.equal(a.remaining, 0);
  assert.ok(a.message);
});

test('the door reopens as the oldest failure ages out', () => {
  const oldest = NOW - 9 * MIN;
  const failures = [oldest, ...Array.from({ length: PER_BUYER.max - 1 }, () => NOW - MIN)];
  const a = assess(failures, NOW, PER_BUYER);
  assert.equal(a.allowed, false);
  assert.equal(a.retryAfterMs, oldest + PER_BUYER.windowMs - NOW);
  assert.equal(a.retryAfterMs, 1 * MIN);
});

test('failures outside the window do not count', () => {
  // A caller that over-reads from the database is still correct.
  const stale = Array.from({ length: 50 }, (_, i) => NOW - (60 + i) * MIN);
  assert.equal(assess(stale, NOW, PER_BUYER).allowed, true);
});

test('the message tells the buyer their money is not at risk', () => {
  const failures = Array.from({ length: PER_BUYER.max }, () => NOW - MIN);
  const a = assess(failures, NOW, PER_BUYER);
  assert.match(a.message ?? '', /minutes/);
  assert.match(a.message ?? '', /safe/);
});

test('the tightest rule decides, and the first blocking one is reported', () => {
  const buyerFailures = Array.from({ length: PER_BUYER.max }, () => NOW - MIN);
  const blocked = assessAll([
    { failures: [], rule: PER_ORIGIN },
    { failures: buyerFailures, rule: PER_BUYER },
  ], NOW);
  assert.equal(blocked.allowed, false);
  assert.match(blocked.message ?? '', /this number/);
});

test('when everything passes, the smallest remaining budget is reported', () => {
  const a = assessAll([
    { failures: [NOW], rule: PER_ORIGIN },
    { failures: [NOW, NOW, NOW], rule: PER_BUYER },
  ], NOW);
  assert.equal(a.allowed, true);
  assert.equal(a.remaining, PER_BUYER.max - 3);
});

test('the origin rule is looser than the buyer rule, since one origin is many buyers', () => {
  assert.ok(PER_ORIGIN.max > PER_BUYER.max);
});
