import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import {
  formatBdt, formatCompactBdt, formatUsd, parseTakaToPaisa, paisaToUsdCents,
  rateIsStale, roundPaisa, usdToPaisa, type Rate,
} from '../money.ts';

const RATE: Rate = { bdtPaisaPerUsd: 12_250, capturedAt: 0, source: 'test' };

test('a USD price converts into paisa at the quoted rate', () => {
  // $10.00 at ৳122.50 is ৳1,225.00 exactly, so no rounding mode can disagree.
  assert.equal(usdToPaisa(1000, RATE, 'exact'), 122_500);
  assert.equal(usdToPaisa(1000, RATE, 'taka-up'), 122_500);
});

test('the default rounds up to a whole taka', () => {
  // $10.50 is ৳1,286.25 — a figure no buyer will type into the bKash app.
  assert.equal(usdToPaisa(1050, RATE, 'exact'), 128_625);
  assert.equal(usdToPaisa(1050, RATE, 'taka-near'), 128_600);
  assert.equal(usdToPaisa(1050, RATE), 128_700);
  assert.equal(usdToPaisa(1050, RATE), usdToPaisa(1050, RATE, 'taka-up'));
});

test('rounding up never leaves the seller short', () => {
  for (const cents of [199, 499, 1999, 4999, 12_345]) {
    assert.ok(usdToPaisa(cents, RATE) >= usdToPaisa(cents, RATE, 'exact'));
    assert.equal(usdToPaisa(cents, RATE) % 100, 0, 'asking price is a whole taka');
  }
});

test('a nonsense price or rate converts to zero rather than NaN', () => {
  assert.equal(usdToPaisa(0, RATE), 0);
  assert.equal(usdToPaisa(-100, RATE), 0);
  assert.equal(usdToPaisa(1000, { ...RATE, bdtPaisaPerUsd: 0 }), 0);
  assert.equal(usdToPaisa(Number.NaN, RATE), 0);
});

test('paisa converts back to cents', () => {
  assert.equal(paisaToUsdCents(122_500, RATE), 1000);
  assert.equal(paisaToUsdCents(0, RATE), 0);
});

test('roundPaisa modes', () => {
  assert.equal(roundPaisa(12_345, 'exact'), 12_345);
  assert.equal(roundPaisa(12_301, 'taka-up'), 12_400);
  assert.equal(roundPaisa(12_301, 'taka-near'), 12_300);
  assert.equal(roundPaisa(12_300, 'taka-up'), 12_300, 'an exact taka is not bumped');
});

test('a stale rate is not quoted', () => {
  const now = 1_000_000_000;
  assert.equal(rateIsStale({ ...RATE, capturedAt: now - 60_000 }, now), false);
  assert.equal(rateIsStale({ ...RATE, capturedAt: now - 7 * 3600_000 }, now), true);
});

test('taka renders without decimals when it is a whole number', () => {
  assert.equal(formatBdt(244_900), '৳2,449');
  assert.equal(formatBdt(128_625), '৳1,286.25');
  assert.equal(formatBdt(0), '৳0');
  assert.equal(formatBdt(150_000, { symbol: false }), '1,500');
});

test('grouping is western, matching what the bKash SMS prints', () => {
  // Not 1,50,000 — the number on screen is compared by eye against the SMS.
  assert.equal(formatBdt(15_000_000), '৳150,000');
});

test('USD always shows both decimal places', () => {
  assert.equal(formatUsd(1999), '$19.99');
  assert.equal(formatUsd(1000), '$10.00');
});

test('compact taka uses lakh and crore', () => {
  assert.equal(formatCompactBdt(4_820_000_000), '৳4.82Cr'); // ৳48,200,000
  assert.equal(formatCompactBdt(150_000 * 100), '৳1.5L');
  assert.equal(formatCompactBdt(1_000 * 100), '৳1K');
  assert.equal(formatCompactBdt(999 * 100), '৳999');
});

test('an amount is pulled out of an SMS fragment', () => {
  assert.equal(parseTakaToPaisa('Tk 1,500.00'), 150_000);
  assert.equal(parseTakaToPaisa('Tk1500'), 150_000);
  assert.equal(parseTakaToPaisa('1500.5'), 150_050);
});

test('a failed parse is null, not zero', () => {
  // A caller must be able to tell "no amount here" from "the amount was zero".
  assert.equal(parseTakaToPaisa('no digits at all'), null);
  assert.equal(parseTakaToPaisa(''), null);
  assert.equal(parseTakaToPaisa(null), null);
  assert.equal(parseTakaToPaisa('Tk 0.00'), 0);
});
