/**
 * Rate limiting on the claim endpoint.
 *
 * A transaction ID is ten alphanumerics, so nobody is guessing one. The threat
 * this is actually for is narrower and real: somebody who has seen *one* valid
 * ID — a screenshot posted in a group, a forwarded SMS — trying it against
 * every product on a seller's store, and somebody hammering the endpoint to
 * find which IDs exist at all. Both look like a burst of failures from one
 * origin, which is the shape this catches.
 *
 * Only failures are counted. A buyer who pays for three courses in five
 * minutes is a good day, not an attack.
 */

export interface ThrottleRule {
  windowMs: number;
  max: number;
  label: string;
}

/** Per buyer number. Generous — mistyping a TrxID twice is normal. */
export const PER_BUYER: ThrottleRule =
  { windowMs: 10 * 60_000, max: 6, label: 'this number' };

/** Per origin against one seller, which is where enumeration shows up. */
export const PER_ORIGIN: ThrottleRule =
  { windowMs: 10 * 60_000, max: 20, label: 'this connection' };

export interface Assessment {
  allowed: boolean;
  /** Failures left in the window before the door closes. */
  remaining: number;
  /** How long until one falls out of the window. Zero when allowed. */
  retryAfterMs: number;
  /** A sentence for the buyer. Null when allowed. */
  message: string | null;
}

/**
 * `failures` is every failed attempt timestamp on record; anything outside the
 * window is ignored here rather than by the caller, so a caller that over-reads
 * from the database is still correct.
 */
export function assess(failures: number[], now: number, rule: ThrottleRule): Assessment {
  const cutoff = now - rule.windowMs;
  const live = failures.filter((t) => t > cutoff).sort((a, b) => a - b);

  if (live.length < rule.max) {
    return {
      allowed: true,
      remaining: rule.max - live.length,
      retryAfterMs: 0,
      message: null,
    };
  }

  // The oldest live failure is the one whose expiry re-opens the door.
  const retryAfterMs = Math.max(0, live[0] + rule.windowMs - now);
  return {
    allowed: false,
    remaining: 0,
    retryAfterMs,
    message:
      `Too many failed attempts from ${rule.label}. Wait ${humanise(retryAfterMs)} `
      + 'and try again. If your payment went through, it is safe — nothing is lost '
      + 'by waiting, and the seller can confirm it by hand.',
  };
}

/** Applies every rule and returns the first that says no. */
export function assessAll(
  checks: { failures: number[]; rule: ThrottleRule }[],
  now: number,
): Assessment {
  let best: Assessment = { allowed: true, remaining: Infinity, retryAfterMs: 0, message: null };
  for (const c of checks) {
    const a = assess(c.failures, now, c.rule);
    if (!a.allowed) return a;
    if (a.remaining < best.remaining) best = a;
  }
  return best;
}

function humanise(ms: number): string {
  const mins = Math.ceil(ms / 60_000);
  if (mins <= 1) return 'a minute';
  if (mins < 60) return `${mins} minutes`;
  const hours = Math.ceil(mins / 60);
  return hours === 1 ? 'an hour' : `${hours} hours`;
}
