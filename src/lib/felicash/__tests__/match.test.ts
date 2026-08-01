import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { matchClaim, DEFAULT_POLICY, type MatchInput } from '../match.ts';
import { fromDhaka } from '../dhaka.ts';
import type { LedgerEntry } from '../schema.ts';

const NOW = fromDhaka(2026, 7, 31, 15, 0);
const ASKING = 250_000; // ৳2,500

const entry = (over: Partial<LedgerEntry> = {}): LedgerEntry => ({
  id: 'seller1__bkash__ABC1234567',
  sellerId: 'seller1',
  wallet: 'bkash',
  trxId: 'ABC1234567',
  kind: 'received',
  credit: true,
  senderMsisdn: '01712345678',
  accountMsisdn: '01812345678',
  amountPaisa: ASKING,
  feePaisa: 0,
  balancePaisa: 900_000,
  occurredAt: NOW - 60_000,
  receivedAt: NOW - 50_000,
  source: 'device',
  deviceId: 'device1',
  claimedByOrderId: null,
  claimedAt: null,
  simSlot: 1,
  ...over,
});

const input = (over: Partial<MatchInput> = {}): MatchInput => ({
  claim: { trxId: 'ABC1234567', senderMsisdn: '01712345678' },
  expected: { askingPaisa: ASKING, wallet: 'bkash', toMsisdn: '01812345678' },
  entries: [entry()],
  lastSyncAt: NOW - 30_000,
  now: NOW,
  ...over,
});

/* ------------------------------------------------------------- the happy path */

test('the right amount from the right number settles', () => {
  const r = matchClaim(input());
  assert.equal(r.status, 'settled');
  if (r.status !== 'settled') return;
  assert.equal(r.paidPaisa, ASKING);
  assert.deepEqual(r.warnings, []);
  assert.equal(r.entry.trxId, 'ABC1234567');
});

test('a sloppily copied transaction ID still settles', () => {
  const r = matchClaim(input({
    claim: { trxId: ' abc-123 4567 ', senderMsisdn: '+8801712345678' },
  }));
  assert.equal(r.status, 'settled');
});

/* ------------------------------------------------ not found, and the fork in it */

test('an unknown ID with a live feed is a rejection the buyer can retry', () => {
  const r = matchClaim(input({ entries: [] }));
  assert.equal(r.status, 'rejected');
  if (r.status !== 'rejected') return;
  assert.equal(r.reason, 'unknown_trxid');
  assert.equal(r.retryable, true);
  assert.match(r.message, /ABC1234567/, 'quotes the ID back so a typo is visible');
});

test('an unknown ID with a silent feed is "not yet", not "not real"', () => {
  // This is the fork the whole design turns on. Telling a buyer who genuinely
  // paid that their payment does not exist is what costs the seller the sale.
  const r = matchClaim(input({ entries: [], lastSyncAt: NOW - 20 * 60_000 }));
  assert.equal(r.status, 'rejected');
  if (r.status !== 'rejected') return;
  assert.equal(r.reason, 'not_yet_synced');
  assert.equal(r.retryable, true);
  assert.match(r.message, /money is safe/i);
});

test('a feed that has never reported is treated as silent, not as empty', () => {
  const r = matchClaim(input({ entries: [], lastSyncAt: null }));
  assert.equal(r.status === 'rejected' && r.reason, 'not_yet_synced');
});

test('something that is not a transaction ID is rejected before any lookup', () => {
  const r = matchClaim(input({ claim: { trxId: '12', senderMsisdn: '01712345678' } }));
  assert.equal(r.status, 'rejected');
  if (r.status !== 'rejected') return;
  assert.equal(r.reason, 'malformed_trxid');
  assert.equal(r.retryable, false, 'retrying the same nonsense will not help');
});

/* ----------------------------------------------------------------- the refusals */

test('a transaction ID can only be spent once', () => {
  const r = matchClaim(input({ entries: [entry({ claimedByOrderId: 'order9' })] }));
  assert.equal(r.status, 'rejected');
  if (r.status !== 'rejected') return;
  assert.equal(r.reason, 'already_claimed');
  assert.equal(r.retryable, false);
});

test('a debit row cannot settle an order', () => {
  const r = matchClaim(input({ entries: [entry({ credit: false, kind: 'debit' })] }));
  assert.equal(r.status === 'rejected' && r.reason, 'not_a_credit');
});

test('paying on the other wallet does not settle', () => {
  const r = matchClaim(input({ entries: [entry({ wallet: 'nagad' })] }));
  assert.equal(r.status, 'rejected');
  if (r.status !== 'rejected') return;
  assert.equal(r.reason, 'wrong_wallet');
  assert.match(r.message, /Nagad/);
  assert.match(r.message, /bKash/);
});

/* ------------------------------------------------------------------- the amount */

test('an underpayment says how much is missing', () => {
  // ৳50 short. "Payment not found" would send this buyer to Messenger; a
  // number they can act on sends them back to the bKash app.
  const r = matchClaim(input({ entries: [entry({ amountPaisa: ASKING - 5_000 })] }));
  assert.equal(r.status, 'rejected');
  if (r.status !== 'rejected') return;
  assert.equal(r.reason, 'amount_short');
  assert.equal(r.retryable, true);
  assert.match(r.message, /৳50\b/);
});

test('a small overpayment settles and is flagged rather than blocked', () => {
  const r = matchClaim(input({ entries: [entry({ amountPaisa: ASKING + 10_000 })] }));
  assert.equal(r.status, 'settled');
  if (r.status !== 'settled') return;
  assert.deepEqual(r.warnings, ['overpaid']);
  assert.equal(r.paidPaisa, ASKING + 10_000, 'the record keeps what was actually sent');
});

test('a large overpayment goes to a human', () => {
  const r = matchClaim(input({ entries: [entry({ amountPaisa: ASKING + 100_000 })] }));
  assert.equal(r.status, 'review');
  if (r.status !== 'review') return;
  assert.equal(r.reason, 'amount_over');
});

test('an underpayment inside an explicit tolerance settles with a flag', () => {
  const r = matchClaim(input({
    entries: [entry({ amountPaisa: ASKING - 100 })],
    policy: { underpayTolerancePaisa: 500 },
  }));
  assert.equal(r.status, 'settled');
  if (r.status !== 'settled') return;
  assert.deepEqual(r.warnings, ['underpaid_within_tolerance']);
});

/* ------------------------------------------------------------------- the payer */

test('money from a number the buyer did not declare is refused by default', () => {
  const r = matchClaim(input({
    claim: { trxId: 'ABC1234567', senderMsisdn: '01912345678' },
  }));
  assert.equal(r.status, 'rejected');
  if (r.status !== 'rejected') return;
  assert.equal(r.reason, 'sender_mismatch');
  assert.match(r.message, /017\*\*\*\*5678/, 'shows enough to recognise, not to harvest');
});

test('a seller can allow a friend or relative to pay on the buyer\'s behalf', () => {
  // Extremely common here: the buyer has no bKash balance, an older sibling
  // sends it. Refusing outright is technically correct and commercially wrong.
  const r = matchClaim(input({
    claim: { trxId: 'ABC1234567', senderMsisdn: '01912345678' },
    policy: { requireSenderMatch: false },
  }));
  assert.equal(r.status, 'settled');
  if (r.status !== 'settled') return;
  assert.deepEqual(r.warnings, ['third_party_payer']);
});

test('the amount is checked before the payer', () => {
  // A buyer who paid the wrong amount from the right phone should be told
  // about the amount, not sent down a payer-mismatch path they cannot fix.
  const r = matchClaim(input({
    claim: { trxId: 'ABC1234567', senderMsisdn: '01912345678' },
    entries: [entry({ amountPaisa: ASKING - 5_000 })],
  }));
  assert.equal(r.status === 'rejected' && r.reason, 'amount_short');
});

/* ------------------------------------------------------------------ the account */

test('money that landed on another of the seller\'s numbers goes to review', () => {
  const r = matchClaim(input({ entries: [entry({ accountMsisdn: '01911111111' })] }));
  assert.equal(r.status, 'review');
  if (r.status !== 'review') return;
  assert.equal(r.reason, 'wrong_account');
});

test('a forwarder that cannot say which SIM took the SMS does not block the sale', () => {
  const r = matchClaim(input({ entries: [entry({ accountMsisdn: null })] }));
  assert.equal(r.status, 'settled');
});

test('a payment older than the order goes to review rather than settling', () => {
  const r = matchClaim(input({
    entries: [entry({ occurredAt: NOW - 8 * 24 * 3600_000 })],
  }));
  assert.equal(r.status === 'review' && r.reason, 'stale_entry');
});

/* -------------------------------------------------------------------- policy */

test('the shipped policy is the strict one', () => {
  assert.equal(DEFAULT_POLICY.underpayTolerancePaisa, 0);
  assert.equal(DEFAULT_POLICY.requireSenderMatch, true);
  assert.ok(DEFAULT_POLICY.syncGraceMs >= 5 * 60_000,
    'generous enough that SMS latency does not read as fraud');
});

test('every rejection carries a sentence, never a bare code', () => {
  const cases: MatchInput[] = [
    input({ entries: [] }),
    input({ claim: { trxId: 'x', senderMsisdn: null } }),
    input({ entries: [entry({ claimedByOrderId: 'o1' })] }),
    input({ entries: [entry({ amountPaisa: 1 })] }),
    input({ entries: [entry({ wallet: 'nagad' })] }),
  ];
  for (const c of cases) {
    const r = matchClaim(c);
    const message = r.status === 'settled' ? '' : r.message;
    assert.ok(message.length > 40, `too terse to act on: ${message}`);
    assert.ok(/[.!]$/.test(message.trim()), `not a sentence: ${message}`);
  }
});
