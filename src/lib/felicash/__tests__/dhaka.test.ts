import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import {
  dayKey, dhakaParts, formatDhaka, fromDhaka, monthEnd, monthKey, monthLabel,
  monthStart, recentMonthKeys, yearKey,
} from '../dhaka.ts';

test('a wall-clock reading in Dhaka is six hours ahead of UTC', () => {
  assert.equal(fromDhaka(2026, 8, 1, 0, 0, 0), Date.UTC(2026, 7, 1, 0, 0, 0) - 6 * 3600_000);
  const p = dhakaParts(Date.UTC(2026, 6, 31, 19, 30));
  assert.deepEqual(
    [p.year, p.month, p.day, p.hour, p.minute],
    [2026, 8, 1, 1, 30],
  );
});

test('a payment late on the last night of the month belongs to the next one', () => {
  // 31 July 19:30 UTC is 1 August 01:30 in Dhaka. Bucketing this in July is
  // the bug that quietly moves a day of takings every single month.
  assert.equal(monthKey(Date.UTC(2026, 6, 31, 19, 30)), '2026-08');
  assert.equal(dayKey(Date.UTC(2026, 6, 31, 19, 30)), '2026-08-01');
  assert.equal(yearKey(Date.UTC(2026, 11, 31, 18, 30)), '2027');
});

test('a payment early in the UTC morning still belongs to the same Dhaka day', () => {
  assert.equal(monthKey(Date.UTC(2026, 7, 1, 3, 0)), '2026-08');
  assert.equal(dayKey(Date.UTC(2026, 7, 1, 3, 0)), '2026-08-01');
});

test('the month is 1-12, not the 0-11 that has bitten everyone', () => {
  assert.equal(dhakaParts(fromDhaka(2026, 1, 15, 12)).month, 1);
  assert.equal(dhakaParts(fromDhaka(2026, 12, 15, 12)).month, 12);
});

test('a month key spans exactly its own month', () => {
  assert.equal(monthStart('2026-07'), fromDhaka(2026, 7, 1));
  assert.equal(monthEnd('2026-07'), fromDhaka(2026, 8, 1));
  assert.equal(monthEnd('2026-12'), fromDhaka(2027, 1, 1), 'December rolls the year');
});

test('recent month keys are oldest first and cross the year boundary', () => {
  assert.deepEqual(
    recentMonthKeys(fromDhaka(2026, 8, 15, 12), 3),
    ['2026-06', '2026-07', '2026-08'],
  );
  assert.deepEqual(
    recentMonthKeys(fromDhaka(2026, 1, 15, 12), 3),
    ['2025-11', '2025-12', '2026-01'],
  );
  assert.equal(recentMonthKeys(fromDhaka(2026, 8, 15, 12), 12).length, 12);
});

test('labels read the way a seller writes a date', () => {
  assert.equal(monthLabel('2026-07'), 'Jul 2026');
  assert.equal(formatDhaka(fromDhaka(2026, 7, 31, 14, 32)), '31 Jul 2026, 2:32 PM');
  assert.equal(formatDhaka(fromDhaka(2026, 7, 31, 0, 5)), '31 Jul 2026, 12:05 AM');
  assert.equal(formatDhaka(fromDhaka(2026, 7, 31, 12, 0)), '31 Jul 2026, 12:00 PM');
});
