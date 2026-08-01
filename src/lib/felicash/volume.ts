/**
 * Transaction volume, by month and by year.
 *
 * A seller wants three numbers: what came in this month, what came in this
 * year, and whether that is better or worse than last time. Everything here
 * exists to produce those honestly.
 *
 * Two rules that are easy to get wrong and expensive to get wrong:
 *
 * - Buckets are Dhaka days, not UTC days. See dhaka.ts for why that is a
 *   correctness issue and not a display one.
 * - Months with no sales still appear, with zero. Dropping them makes a chart
 *   of [Jan, Mar, Apr] look like three consecutive months and turns a bad
 *   February into an invisible one.
 */
import type { Paisa } from './money.ts';
import { dhakaParts, monthKey, monthLabel, yearKey, recentMonthKeys } from './dhaka.ts';
import type { Wallet } from './sms.ts';

/**
 * One settled payment, flattened.
 *
 * Deliberately not `Order`: the same rollup runs over raw ledger rows when a
 * seller wants total money received rather than money received against an
 * order, and those two figures diverging is itself worth seeing.
 */
export interface VolumeRow {
  at: number;
  paisa: Paisa;
  wallet: Wallet;
  /** Which receiving number took it. Null when the forwarder cannot say. */
  accountMsisdn: string | null;
  productId: string | null;
  /** Anything stable per buyer — the msisdn. Null rows never count as unique. */
  buyerKey: string | null;
}

export interface Bucket {
  key: string;
  label: string;
  grossPaisa: Paisa;
  count: number;
  uniqueBuyers: number;
}

export interface Breakdown {
  key: string;
  label: string;
  grossPaisa: Paisa;
  count: number;
  /** Share of the total, 0-1. Zero when there is no total, never NaN. */
  share: number;
}

export interface VolumeReport {
  /** Oldest first, gaps filled. Length is exactly the requested window. */
  months: Bucket[];
  /** Oldest first. Only years that have rows. */
  years: Bucket[];
  thisMonth: Bucket;
  thisYear: Bucket;
  /** This month against last, as a fraction. Null when last month was zero. */
  monthOverMonth: number | null;
  byWallet: Breakdown[];
  byAccount: Breakdown[];
  byProduct: Breakdown[];
  /** Average settled payment across the whole input. */
  averagePaisa: Paisa;
  grossPaisa: Paisa;
  count: number;
}

export function report(
  rows: VolumeRow[],
  now: number,
  opts: { months?: number; productNames?: Record<string, string> } = {},
): VolumeReport {
  const window = opts.months ?? 12;
  const keys = recentMonthKeys(now, window);

  const byMonth = group(rows, (r) => monthKey(r.at));
  const byYear = group(rows, (r) => yearKey(r.at));

  const months = keys.map((k) => bucket(k, monthLabel(k), byMonth.get(k) ?? []));
  const years = [...byYear.keys()].sort()
    .map((k) => bucket(k, k, byYear.get(k) ?? []));

  const nowMonth = monthKey(now);
  const nowYear = yearKey(now);
  const thisMonth = bucket(nowMonth, monthLabel(nowMonth), byMonth.get(nowMonth) ?? []);
  const thisYear = bucket(nowYear, nowYear, byYear.get(nowYear) ?? []);

  const prevKey = keys[keys.length - 2];
  const prev = prevKey ? (byMonth.get(prevKey) ?? []) : [];
  const prevGross = sum(prev);

  const gross = sum(rows);

  return {
    months,
    years,
    thisMonth,
    thisYear,
    // Growth against zero is not "infinite percent", it is not a percentage at
    // all. Callers render "—" rather than a number that means nothing.
    monthOverMonth: prevGross > 0 ? (thisMonth.grossPaisa - prevGross) / prevGross : null,
    byWallet: breakdown(rows, (r) => r.wallet, (k) => (k === 'bkash' ? 'bKash' : 'Nagad')),
    byAccount: breakdown(rows, (r) => r.accountMsisdn ?? 'unattributed',
      (k) => (k === 'unattributed' ? 'Unattributed' : k)),
    byProduct: breakdown(rows, (r) => r.productId ?? 'other',
      (k) => opts.productNames?.[k] ?? (k === 'other' ? 'Other' : k)),
    averagePaisa: rows.length ? Math.round(gross / rows.length) : 0,
    grossPaisa: gross,
    count: rows.length,
  };
}

function bucket(key: string, label: string, rows: VolumeRow[]): Bucket {
  return {
    key,
    label,
    grossPaisa: sum(rows),
    count: rows.length,
    uniqueBuyers: new Set(rows.map((r) => r.buyerKey).filter(Boolean)).size,
  };
}

function breakdown(
  rows: VolumeRow[],
  keyOf: (r: VolumeRow) => string,
  labelOf: (key: string) => string,
): Breakdown[] {
  const total = sum(rows);
  const groups = group(rows, keyOf);
  return [...groups.entries()]
    .map(([key, rs]) => ({
      key,
      label: labelOf(key),
      grossPaisa: sum(rs),
      count: rs.length,
      share: total > 0 ? sum(rs) / total : 0,
    }))
    .sort((a, b) => b.grossPaisa - a.grossPaisa);
}

const sum = (rows: VolumeRow[]) => rows.reduce((t, r) => t + r.paisa, 0);

function group<T>(rows: T[], keyOf: (r: T) => string): Map<string, T[]> {
  const out = new Map<string, T[]>();
  for (const r of rows) {
    const k = keyOf(r);
    const list = out.get(k);
    if (list) list.push(r); else out.set(k, [r]);
  }
  return out;
}

/**
 * Where a seller's month lands if the rest of it looks like the part so far.
 *
 * Straight-line from elapsed days, which is the assumption a seller makes in
 * their head anyway. Returned separately from the real figure and never
 * blended into it — a projection presented as a total is a lie with a decimal
 * point on it.
 */
export function projectMonth(thisMonth: Bucket, now: number): Paisa | null {
  const [y, m] = thisMonth.key.split('-').map(Number);
  if (!y || !m) return null;
  const daysInMonth = new Date(Date.UTC(y, m, 0)).getUTCDate();
  const { day } = dhakaParts(now);
  if (day < 3 || day >= daysInMonth) return null; // too early to mean anything
  return Math.round((thisMonth.grossPaisa / day) * daysInMonth);
}
