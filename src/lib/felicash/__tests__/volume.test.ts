import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { projectMonth, report, type VolumeRow } from '../volume.ts';
import { fromDhaka } from '../dhaka.ts';

const NOW = fromDhaka(2026, 8, 15, 12);

const row = (over: Partial<VolumeRow> = {}): VolumeRow => ({
  at: NOW - 3600_000,
  paisa: 100_000,
  wallet: 'bkash',
  accountMsisdn: '01812345678',
  productId: 'p1',
  buyerKey: '01712345678',
  ...over,
});

const ROWS: VolumeRow[] = [
  row({ at: fromDhaka(2026, 6, 10, 12), paisa: 100_000 }),
  row({ at: fromDhaka(2026, 6, 22, 12), paisa: 100_000 }),
  row({ at: fromDhaka(2026, 7, 20, 12), paisa: 300_000 }),
  row({ at: fromDhaka(2026, 8, 2, 12), paisa: 200_000 }),
  row({ at: fromDhaka(2026, 8, 9, 12), paisa: 250_000 }),
];

test('months come back oldest first with the right totals', () => {
  const r = report(ROWS, NOW, { months: 3 });
  assert.deepEqual(r.months.map((m) => m.key), ['2026-06', '2026-07', '2026-08']);
  assert.deepEqual(r.months.map((m) => m.grossPaisa), [200_000, 300_000, 450_000]);
  assert.deepEqual(r.months.map((m) => m.count), [2, 1, 2]);
  assert.equal(r.months[0].label, 'Jun 2026');
});

test('a month with no sales is a zero, not a missing bar', () => {
  // Dropping empty months makes [Jan, Mar, Apr] look consecutive and turns a
  // bad February into an invisible one.
  const r = report(ROWS, NOW, { months: 6 });
  assert.equal(r.months.length, 6);
  assert.deepEqual(r.months.map((m) => m.key),
    ['2026-03', '2026-04', '2026-05', '2026-06', '2026-07', '2026-08']);
  assert.deepEqual(r.months.slice(0, 3).map((m) => m.grossPaisa), [0, 0, 0]);
});

test('this month and this year are the buckets containing now', () => {
  const r = report(ROWS, NOW);
  assert.equal(r.thisMonth.key, '2026-08');
  assert.equal(r.thisMonth.grossPaisa, 450_000);
  assert.equal(r.thisYear.key, '2026');
  assert.equal(r.thisYear.grossPaisa, 950_000);
  assert.equal(r.thisYear.count, 5);
});

test('yearly buckets span more than one year', () => {
  const r = report([...ROWS, row({ at: fromDhaka(2025, 11, 3, 12), paisa: 50_000 })], NOW);
  assert.deepEqual(r.years.map((y) => y.key), ['2025', '2026']);
  assert.equal(r.years[0].grossPaisa, 50_000);
});

test('month-over-month is a fraction, and null when there is nothing to compare', () => {
  assert.equal(report(ROWS, NOW).monthOverMonth, 0.5);
  // Growth against a zero month is not "infinite percent" — it is not a
  // percentage at all, and rendering one would be a made-up number.
  const augustOnly = ROWS.filter((r) => r.at > fromDhaka(2026, 8, 1));
  assert.equal(report(augustOnly, NOW).monthOverMonth, null);
});

test('takings are bucketed by the Dhaka day they happened on', () => {
  const lateJulyUtc = Date.UTC(2026, 6, 31, 19, 0); // 1 August, 01:00 in Dhaka
  const r = report([row({ at: lateJulyUtc, paisa: 70_000 })], NOW, { months: 3 });
  assert.equal(r.months.find((m) => m.key === '2026-08')?.grossPaisa, 70_000);
  assert.equal(r.months.find((m) => m.key === '2026-07')?.grossPaisa, 0);
});

test('unique buyers are counted once however often they buy', () => {
  const r = report([
    row({ buyerKey: '01711111111' }),
    row({ buyerKey: '01711111111' }),
    row({ buyerKey: '01722222222' }),
    row({ buyerKey: null }),
  ], NOW);
  assert.equal(r.thisMonth.count, 4);
  assert.equal(r.thisMonth.uniqueBuyers, 2, 'an unknown buyer is not a unique one');
});

test('breakdowns are sorted by size and their shares add up', () => {
  const r = report([
    row({ wallet: 'bkash', paisa: 300_000 }),
    row({ wallet: 'nagad', paisa: 100_000 }),
  ], NOW);
  assert.deepEqual(r.byWallet.map((w) => w.label), ['bKash', 'Nagad']);
  assert.equal(r.byWallet[0].share, 0.75);
  assert.equal(r.byWallet.reduce((t, w) => t + w.share, 0), 1);
});

test('products are named when names are supplied, and grouped when they are not', () => {
  const r = report([
    row({ productId: 'p1', paisa: 100_000 }),
    row({ productId: null, paisa: 50_000 }),
  ], NOW, { productNames: { p1: 'Flutter Course' } });
  assert.deepEqual(r.byProduct.map((p) => p.label), ['Flutter Course', 'Other']);
});

test('an empty ledger reports zeroes rather than NaN', () => {
  const r = report([], NOW, { months: 3 });
  assert.equal(r.grossPaisa, 0);
  assert.equal(r.averagePaisa, 0);
  assert.equal(r.count, 0);
  assert.equal(r.monthOverMonth, null);
  assert.equal(r.months.length, 3);
  assert.deepEqual(r.byWallet, []);
});

test('the average is over settled payments, not over months', () => {
  assert.equal(report(ROWS, NOW).averagePaisa, 190_000);
});

test('a month is only projected once there is enough of it to project from', () => {
  const r = report(ROWS, NOW);
  assert.equal(projectMonth(r.thisMonth, NOW), 930_000); // ৳4,500 over 15 of 31 days
  assert.equal(projectMonth(r.thisMonth, fromDhaka(2026, 8, 2, 12)), null);
  assert.equal(projectMonth(r.thisMonth, fromDhaka(2026, 8, 31, 12)), null,
    'on the last day the real figure is the answer');
});
