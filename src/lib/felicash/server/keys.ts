/**
 * Device keys.
 *
 * The forwarder phone holds a key that lets it write into a seller's ledger.
 * That is the most dangerous credential in the system — anybody holding it can
 * invent payments — so two things follow.
 *
 * Only the hash is stored. A dump of the database must not hand somebody the
 * ability to fabricate transactions, which is exactly what a plaintext column
 * would do. The reference project stores its keys encrypted on the device and
 * is candid that this stops a SharedPreferences dump and not a decompiler; the
 * same is true here, and the mitigation is that a key is revocable in one tap
 * and scoped to exactly one seller.
 *
 * Comparison is constant-time. A hash comparison that short-circuits leaks the
 * hash a byte at a time to anyone willing to measure, and `===` on a string
 * short-circuits.
 */
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';

/** `fck_` then 32 bytes of hex. Prefixed so a leaked key is greppable. */
export function newDeviceKey(): string {
  return `fck_${randomBytes(24).toString('hex')}`;
}

export const hashKey = (key: string) =>
  createHash('sha256').update(key.trim()).digest('hex');

/** `fck_…a91c` — enough to tell two devices apart in a list, useless alone. */
export function keyHint(key: string): string {
  const trimmed = key.trim();
  return `fck_…${trimmed.slice(-4)}`;
}

export function keysMatch(a: string, b: string): boolean {
  const x = Buffer.from(a, 'utf8');
  const y = Buffer.from(b, 'utf8');
  // timingSafeEqual throws on a length mismatch, which is itself a leak; hash
  // outputs are fixed-length so an unequal length here means malformed input.
  if (x.length !== y.length) return false;
  return timingSafeEqual(x, y);
}

/** The bearer token off a request, or null. Accepts a bare key too. */
export function bearerFrom(header: string | null): string | null {
  if (!header) return null;
  const trimmed = header.trim();
  const match = /^Bearer\s+(.+)$/i.exec(trimmed);
  return (match?.[1] ?? trimmed) || null;
}

/** A token for a webhook handshake or a one-time link. Not a device key. */
export const newToken = () => randomBytes(16).toString('hex');
