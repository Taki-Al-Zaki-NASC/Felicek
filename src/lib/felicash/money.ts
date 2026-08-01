/**
 * Money for FeliCash.
 *
 * Two currencies, one hard rule: never store a float. USD is held in cents,
 * BDT in paisa, and the only place the two are allowed to meet is
 * `usdToPaisa`. Everything downstream — the checkout total, the ledger match,
 * the invoice, the monthly rollup — works in paisa, so a rounding decision is
 * made once instead of six times with six answers.
 *
 * Same discipline as fees.ts on the marketplace side, for the same reason: a
 * platform that computes a price twice eventually charges two different
 * numbers for one thing.
 */

/** United States cents. A $19.99 course is 1999. */
export type UsdCents = number;
/** Bangladeshi paisa, 1/100 of a taka. ৳1,500.00 is 150000. */
export type Paisa = number;

export const PAISA_PER_TAKA = 100;

export interface Rate {
  /** Paisa for one whole USD. 1 USD = ৳122.50 is 12_250. */
  bdtPaisaPerUsd: number;
  /** When this rate was captured, epoch ms. Quoted prices go stale. */
  capturedAt: number;
  /** Where it came from, so a wrong number is traceable. */
  source: string;
}

/**
 * How a converted price is rounded before it is shown to a buyer.
 *
 * `taka-up` is the default and not an arbitrary one. A buyer paying from the
 * bKash app types the amount by hand, and nobody types ৳2,447.53 — they type
 * 2448, the match fails on the paisa, and the seller gets a support message
 * instead of a sale. Rounding up rather than to nearest also means a rate that
 * moves during checkout cannot leave the seller short.
 */
export type Rounding = 'exact' | 'taka-up' | 'taka-near';

export function roundPaisa(paisa: Paisa, mode: Rounding): Paisa {
  if (mode === 'exact') return Math.round(paisa);
  const takas = paisa / PAISA_PER_TAKA;
  const whole = mode === 'taka-up' ? Math.ceil(takas) : Math.round(takas);
  return whole * PAISA_PER_TAKA;
}

/**
 * The price a buyer is asked to send, in paisa.
 *
 * Sellers on Facebook price in USD because that is what the course was priced
 * at; buyers pay in taka because that is what bKash moves. This is the only
 * bridge between the two.
 */
export function usdToPaisa(
  usdCents: UsdCents,
  rate: Rate,
  mode: Rounding = 'taka-up',
): Paisa {
  if (!Number.isFinite(usdCents) || usdCents <= 0) return 0;
  if (!Number.isFinite(rate.bdtPaisaPerUsd) || rate.bdtPaisaPerUsd <= 0) return 0;
  return roundPaisa((usdCents * rate.bdtPaisaPerUsd) / 100, mode);
}

/** The reverse, for reporting a taka figure back in the seller's pricing currency. */
export function paisaToUsdCents(paisa: Paisa, rate: Rate): UsdCents {
  if (!Number.isFinite(paisa) || paisa <= 0) return 0;
  if (!Number.isFinite(rate.bdtPaisaPerUsd) || rate.bdtPaisaPerUsd <= 0) return 0;
  return Math.round((paisa * 100) / rate.bdtPaisaPerUsd);
}

/**
 * A rate older than this is not quoted to a buyer without a refresh.
 *
 * Six hours, because an intraday move of a percent on a ৳3,000 course is ৳30 —
 * small enough not to churn every checkout, large enough to matter over a week
 * of sales.
 */
export const RATE_MAX_AGE_MS = 6 * 60 * 60 * 1000;

export const rateIsStale = (rate: Rate, now: number) =>
  now - rate.capturedAt > RATE_MAX_AGE_MS;

const GROUPED = (n: number, fractionDigits: number) =>
  n.toLocaleString('en-US', {
    minimumFractionDigits: fractionDigits,
    maximumFractionDigits: fractionDigits,
  });

/**
 * Taka, grouped western-style.
 *
 * Not the Indian 1,50,000 grouping: bKash's own SMS and app both render
 * 1,50,000 as 150,000.00, and the number on this screen is compared by eye
 * against the number in that SMS.
 */
export function formatBdt(paisa: Paisa, opts: { symbol?: boolean } = {}): string {
  const symbol = opts.symbol === false ? '' : '৳';
  const whole = paisa % PAISA_PER_TAKA === 0;
  return symbol + GROUPED(paisa / PAISA_PER_TAKA, whole ? 0 : 2);
}

export function formatUsd(cents: UsdCents): string {
  return `$${GROUPED(cents / 100, 2)}`;
}

/**
 * Lakh and crore, for report headlines only.
 *
 * A seller reading "this year: ৳4,82,00,000" has to count digits. "৳4.82Cr"
 * they read at a glance. Detail views keep the full number — this is for the
 * one big figure at the top of a card, never for anything that gets reconciled.
 */
export function formatCompactBdt(paisa: Paisa): string {
  const taka = paisa / PAISA_PER_TAKA;
  const abs = Math.abs(taka);
  if (abs >= 1e7) return `৳${trim(taka / 1e7)}Cr`;
  if (abs >= 1e5) return `৳${trim(taka / 1e5)}L`;
  if (abs >= 1e3) return `৳${trim(taka / 1e3)}K`;
  return formatBdt(paisa);
}

const trim = (n: number) => n.toFixed(2).replace(/\.?0+$/, '');

/**
 * Pulls a taka amount out of free text, returning paisa.
 *
 * Written for SMS bodies, where the amount arrives as "Tk 1,500.00" or
 * "1500.00" or "Tk1500". Returns null rather than 0 on failure, because a
 * failed parse and a genuine zero must not read the same to the caller.
 */
export function parseTakaToPaisa(text: string | null | undefined): Paisa | null {
  if (!text) return null;
  const match = /(?:tk\.?\s*)?(\d[\d,]*(?:\.\d{1,2})?)/i.exec(text.trim());
  if (!match) return null;
  const value = Number(match[1].replace(/,/g, ''));
  if (!Number.isFinite(value)) return null;
  return Math.round(value * PAISA_PER_TAKA);
}
