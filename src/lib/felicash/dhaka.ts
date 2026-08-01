/**
 * Dates in Asia/Dhaka, everywhere, without exception.
 *
 * This is not a formatting preference. A payment that lands at 03:00 UTC on
 * 1 August happened at 09:00 on 1 August in Dhaka — but one that lands at
 * 19:30 UTC on 31 July also happened on 1 August there. Bucket by UTC and a
 * seller's July closes with a day's takings in the wrong month, every month,
 * and the yearly total they file taxes against is wrong at both ends.
 *
 * Bangladesh Standard Time is UTC+6 with no daylight saving, so a fixed offset
 * is correct here rather than merely convenient — there is no rule to get
 * wrong, and no dependency on the server's own timezone, which on Vercel is
 * UTC and on a laptop is anything.
 */
export const DHAKA_OFFSET_MS = 6 * 60 * 60 * 1000;

export interface DhakaParts {
  year: number;
  /** 1-12, not the 0-11 that has caused this bug in every codebase. */
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
}

export function dhakaParts(epochMs: number): DhakaParts {
  const d = new Date(epochMs + DHAKA_OFFSET_MS);
  return {
    year: d.getUTCFullYear(),
    month: d.getUTCMonth() + 1,
    day: d.getUTCDate(),
    hour: d.getUTCHours(),
    minute: d.getUTCMinutes(),
    second: d.getUTCSeconds(),
  };
}

/** Epoch ms for a wall-clock reading taken in Dhaka. Month is 1-12. */
export function fromDhaka(
  year: number, month: number, day: number,
  hour = 0, minute = 0, second = 0,
): number {
  return Date.UTC(year, month - 1, day, hour, minute, second) - DHAKA_OFFSET_MS;
}

const pad = (n: number) => String(n).padStart(2, '0');

/** `2026-07`. Sorts lexicographically, which is why it is a string and not a pair. */
export const monthKey = (epochMs: number) => {
  const p = dhakaParts(epochMs);
  return `${p.year}-${pad(p.month)}`;
};

/** `2026`. */
export const yearKey = (epochMs: number) => String(dhakaParts(epochMs).year);

/** `2026-07-31`, for daily series. */
export const dayKey = (epochMs: number) => {
  const p = dhakaParts(epochMs);
  return `${p.year}-${pad(p.month)}-${pad(p.day)}`;
};

/** First instant of a `2026-07` month, in epoch ms. */
export function monthStart(key: string): number {
  const [y, m] = key.split('-').map(Number);
  return fromDhaka(y, m, 1);
}

/** First instant of the month after `2026-07`. Exclusive upper bound. */
export function monthEnd(key: string): number {
  const [y, m] = key.split('-').map(Number);
  return m === 12 ? fromDhaka(y + 1, 1, 1) : fromDhaka(y, m + 1, 1);
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** `Jul 2026`, for a report heading. */
export function monthLabel(key: string): string {
  const [y, m] = key.split('-').map(Number);
  return `${MONTHS[m - 1]} ${y}`;
}

/** `31 Jul 2026, 2:32 PM` — the format bKash's own app uses for a receipt. */
export function formatDhaka(epochMs: number): string {
  const p = dhakaParts(epochMs);
  const h12 = p.hour % 12 === 0 ? 12 : p.hour % 12;
  const meridiem = p.hour < 12 ? 'AM' : 'PM';
  return `${p.day} ${MONTHS[p.month - 1]} ${p.year}, ${h12}:${pad(p.minute)} ${meridiem}`;
}

/** The `2026-07` keys from `count` months ago up to the month containing `now`. */
export function recentMonthKeys(now: number, count: number): string[] {
  const p = dhakaParts(now);
  const keys: string[] = [];
  for (let i = count - 1; i >= 0; i--) {
    const total = p.year * 12 + (p.month - 1) - i;
    keys.push(`${Math.floor(total / 12)}-${pad((total % 12) + 1)}`);
  }
  return keys;
}
