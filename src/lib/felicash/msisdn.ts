/**
 * Bangladeshi mobile numbers.
 *
 * A buyer types their number six different ways — 01712345678, +8801712345678,
 * 8801712345678, 0171-234-5678, or with a stray space from a paste. The SMS
 * from bKash writes it a seventh way. Every one of those has to compare equal
 * to the same ledger row, or the buyer sees "payment not found" while holding
 * a receipt that says otherwise.
 *
 * So there is exactly one canonical form here — `01XXXXXXXXX`, eleven digits —
 * and nothing else is ever compared or stored.
 */

/** Operator prefixes in service: Grameenphone, Robi, Banglalink, Teletalk, Airtel, Skitto. */
const OPERATORS: Record<string, string> = {
  '013': 'Grameenphone',
  '014': 'Banglalink',
  '015': 'Teletalk',
  '016': 'Airtel',
  '017': 'Grameenphone',
  '018': 'Robi',
  '019': 'Banglalink',
};

/**
 * Canonical `01XXXXXXXXX`, or null when the input is not a BD mobile number.
 *
 * Null, not the input unchanged: a caller that gets its input back would
 * happily store "+88 017-1234-5678" as a key and never match anything.
 */
export function normalizeBd(input: string | null | undefined): string | null {
  if (!input) return null;
  let digits = String(input).replace(/[^\d+]/g, '');
  if (digits.startsWith('+')) digits = digits.slice(1);
  if (digits.startsWith('880')) digits = digits.slice(3);
  else if (digits.startsWith('88') && digits.length === 13) digits = digits.slice(2);
  // A number typed without its leading zero — common when the country code was
  // stripped by a form that expected one.
  if (digits.length === 10 && digits.startsWith('1')) digits = `0${digits}`;
  if (digits.length !== 11 || !digits.startsWith('01')) return null;
  return digits.slice(0, 3) in OPERATORS ? digits : null;
}

export const isValidBd = (input: string | null | undefined) =>
  normalizeBd(input) !== null;

export function operatorOf(input: string | null | undefined): string | null {
  const n = normalizeBd(input);
  return n ? OPERATORS[n.slice(0, 3)] ?? null : null;
}

/** Two numbers are the same number, whatever shape they arrived in. */
export function sameMsisdn(a: string | null | undefined, b: string | null | undefined) {
  const x = normalizeBd(a);
  return x !== null && x === normalizeBd(b);
}

/**
 * `017****5678` — enough for a buyer to recognise their own number, not enough
 * for a shoulder-surfer to read a stranger's off a shared screen. Order pages
 * are opened in public places and screenshotted into Messenger threads.
 */
export function maskMsisdn(input: string | null | undefined): string {
  const n = normalizeBd(input);
  if (!n) return '—';
  return `${n.slice(0, 3)}****${n.slice(7)}`;
}

/** `+880 1712-345678`, for invoices and anywhere a number is read aloud. */
export function formatBd(input: string | null | undefined): string {
  const n = normalizeBd(input);
  if (!n) return '—';
  return `+880 ${n.slice(1, 5)}-${n.slice(5)}`;
}
