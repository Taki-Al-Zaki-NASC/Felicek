/**
 * The small amount of HTTP every route needs.
 *
 * One convention worth stating, because it looks wrong at a glance: a claim
 * that does not match is answered with 200 and `ok: false`, not with 4xx. The
 * request was well-formed and was processed correctly; "this transaction ID
 * does not match" is the *answer*, not a failure to answer. Statuses are kept
 * for things that genuinely went wrong — a malformed body, a missing order, a
 * throttle, an unconfigured deployment — so a client can treat a non-200 as
 * "something broke" rather than having to distinguish two kinds of 422.
 */
export const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: {
      'content-type': 'application/json; charset=utf-8',
      // Nothing here is ever cacheable: it is all one buyer's own order.
      'cache-control': 'no-store',
    },
  });

export const fail = (message: string, status = 400, extra: object = {}) =>
  json({ ok: false, message, ...extra }, status);

/** Parses a JSON body, returning null rather than throwing on garbage. */
export async function readJson<T>(req: Request): Promise<T | null> {
  try {
    const body = await req.json();
    return body && typeof body === 'object' ? (body as T) : null;
  } catch {
    return null;
  }
}

/**
 * The caller's address, for throttling only.
 *
 * Proxy headers are trivially forged, which is exactly why this is never used
 * for authorisation — only to make enumeration from one source more expensive.
 */
export function clientIp(req: Request): string {
  const forwarded = req.headers.get('x-forwarded-for');
  return (forwarded?.split(',')[0] ?? req.headers.get('x-real-ip') ?? 'unknown').trim();
}

/** The public origin, for links inside emails and invoices. */
export function baseUrlFrom(req: Request): string {
  const configured = process.env.FELICASH_PUBLIC_URL;
  if (configured) return configured.replace(/\/+$/, '');
  try {
    return new URL(req.url).origin;
  } catch {
    return '';
  }
}

export const asString = (v: unknown, max = 200) =>
  typeof v === 'string' ? v.trim().slice(0, max) : '';

/** Deliberately permissive: rejecting a valid address is worse than accepting a typo. */
export const looksLikeEmail = (v: string) => /^[^@\s]+@[^@\s.]+\.[^@\s]+$/.test(v);
