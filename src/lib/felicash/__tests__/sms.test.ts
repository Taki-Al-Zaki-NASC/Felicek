import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { normalizeTrxId, parseSms, parseSmsDate, walletFromOriginator } from '../sms.ts';
import { dhakaParts, fromDhaka } from '../dhaka.ts';

const BKASH_RECEIVED =
  'You have received Tk 1,500.00 from 01712345678. Ref None. Fee Tk 0.00. '
  + 'Balance Tk 3,240.50. TrxID BHK7A2XY9Z at 31/07/2026 14:32';

test('a bKash receive SMS yields every field a match needs', () => {
  const p = parseSms(BKASH_RECEIVED, 'bkash');
  assert.ok(p);
  assert.equal(p.kind, 'received');
  assert.equal(p.credit, true);
  assert.equal(p.trxId, 'BHK7A2XY9Z');
  assert.equal(p.senderMsisdn, '01712345678');
  assert.equal(p.amountPaisa, 150_000);
  assert.equal(p.feePaisa, 0);
  assert.equal(p.balancePaisa, 324_050);
  assert.equal(p.occurredAt, fromDhaka(2026, 7, 31, 14, 32));
});

test('an outgoing payment is never counted as income', () => {
  // The seller's own Send Money and Cash Out messages carry an amount, a
  // number and a TrxID. Reading one as a payment credits a buyer for money
  // the seller spent.
  const sent = parseSms(
    'You have sent Tk 500.00 to 01812345678. Fee Tk 5.00. Balance Tk 100.00. '
    + 'TrxID SND1234567 at 31/07/2026 15:00', 'bkash');
  assert.equal(sent?.kind, 'debit');
  assert.equal(sent?.credit, false);

  const out = parseSms(
    'Cash Out Tk 1,000.00 to 01912345678 successful. Fee Tk 18.50. '
    + 'Balance Tk 2,000.00. TrxID CSH1234567 at 31/07/2026 16:00', 'bkash');
  assert.equal(out?.kind, 'debit');
  assert.equal(out?.credit, false);
});

test('cash in and merchant payment are both income', () => {
  const cashin = parseSms(
    'Cash In Tk 3,000.00 from 01911111111 successful. Fee Tk 0.00. '
    + 'Balance Tk 5,000.00. TrxID CIN1234567 at 31/07/2026 18:00', 'bkash');
  assert.equal(cashin?.kind, 'cashin');
  assert.equal(cashin?.credit, true);

  const payment = parseSms(
    'You have received payment Tk 2,000.00 from 01711111111. '
    + 'TrxID PAY1234567 at 31/07/2026 17:00', 'bkash');
  assert.equal(payment?.kind, 'payment');
  assert.equal(payment?.credit, true);
});

test('Nagad wording is read by the same parser', () => {
  const p = parseSms(
    'Money Received. Amount: Tk 500.00 Sender: 01711111111 '
    + 'TxnID: 71ABCDEF1234 Balance: Tk 1,234.56 31/07/2026 16:05', 'nagad');
  assert.ok(p);
  assert.equal(p.wallet, 'nagad');
  assert.equal(p.credit, true);
  assert.equal(p.trxId, '71ABCDEF1234');
  assert.equal(p.senderMsisdn, '01711111111');
  assert.equal(p.amountPaisa, 50_000);
  assert.equal(p.balancePaisa, 123_456);
});

test('a message with no transaction in it is not a transaction', () => {
  assert.equal(parseSms('Your OTP is 123456. Do not share it.', 'bkash'), null);
  assert.equal(parseSms('', 'bkash'), null);
});

test('a wording change loses a field, not the whole row', () => {
  // Tolerance is the point: amount, sender and TrxID are all a match needs,
  // so a rephrased balance line must not take the payment down with it.
  const p = parseSms(
    'You have received Tk 900.00 from 01512345678. TrxID NEW1234567', 'bkash');
  assert.equal(p?.amountPaisa, 90_000);
  assert.equal(p?.trxId, 'NEW1234567');
  assert.equal(p?.balancePaisa, null);
  assert.equal(p?.occurredAt, null);
});

test('dates are read day-first, the way both wallets send them', () => {
  // 12/07 is 12 July. Reading it American drops a month of payments into the
  // wrong bucket and stays invisible for the first twelve days of every month.
  const at = parseSmsDate('at 12/07/2026 10:00');
  assert.ok(at);
  const p = dhakaParts(at);
  assert.equal(p.day, 12);
  assert.equal(p.month, 7);

  assert.equal(parseSmsDate('at 31/07/26 09:05:30'), fromDhaka(2026, 7, 31, 9, 5, 30));
  assert.equal(parseSmsDate('no date here'), null);
  assert.equal(parseSmsDate('at 31/13/2026 10:00'), null, 'month 13 is not a month');
});

test('transaction IDs compare after trimming and upper-casing', () => {
  // A buyer copying one out of a notification picks up a trailing space about
  // half the time, and types it lower-case the rest.
  assert.equal(normalizeTrxId('  bhk7a2xy9z '), 'BHK7A2XY9Z');
  assert.equal(normalizeTrxId('BHK7-A2XY9Z'), 'BHK7A2XY9Z');
  assert.equal(normalizeTrxId('abc'), null, 'too short to be one');
  assert.equal(normalizeTrxId(''), null);
  assert.equal(normalizeTrxId(null), null);
});

test('only wallet originators are read at all', () => {
  assert.equal(walletFromOriginator('bKash'), 'bkash');
  assert.equal(walletFromOriginator('16247'), 'bkash');
  assert.equal(walletFromOriginator('NAGAD'), 'nagad');
  assert.equal(walletFromOriginator('AIRTEL-OFFER'), null);
  assert.equal(walletFromOriginator(null), null);
});
