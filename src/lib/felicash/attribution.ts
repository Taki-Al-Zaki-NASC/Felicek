/**
 * Where the sale came from, and whether it finished.
 *
 * A seller posts a checkout link into a Facebook page post. What they cannot
 * see from Facebook's own insights is the part that matters: of the people who
 * tapped it, how many actually ended up paying, and where the ones who did not
 * fell out. Facebook reports the click. Nobody reports the ending.
 *
 * So a FeliCash link carries a page reference, every open is recorded, and an
 * order is stitched back to the open that produced it. That gives the one
 * sentence a seller actually wants: *this post brought 214 people, 41 started
 * a payment, 37 completed.*
 *
 * The reference is a checksum, not a signature. Attribution is a reporting
 * number, not a security boundary — nothing is granted or charged on the
 * strength of it — so the right strength is "catches a mangled paste", which
 * is what actually happens to these links. Spending an HMAC here would imply a
 * guarantee this data does not need and cannot really make.
 */

export interface Ref {
  pageId: string;
  campaign: string | null;
}

/** FNV-1a, 32-bit. Small, deterministic, and not pretending to be a hash. */
function fnv1a(input: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    h ^= input.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

const b64url = (s: string) =>
  btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

const unb64url = (s: string) => {
  const padded = s.replace(/-/g, '+').replace(/_/g, '/');
  return atob(padded + '='.repeat((4 - (padded.length % 4)) % 4));
};

/**
 * The `r=` value on a checkout link.
 *
 * The campaign is percent-encoded before base64 because sellers name campaigns
 * in Bangla, and btoa throws outright on anything above Latin-1 — an exception
 * while building a share link, for a Bengali campaign name, in a Bangladeshi
 * product.
 */
export function encodeRef(ref: Ref): string {
  const payload = `${ref.pageId}~${encodeURIComponent(ref.campaign ?? '')}`;
  const body = b64url(payload);
  return `${body}.${fnv1a(payload).toString(36).slice(0, 4)}`;
}

/** Null when the value is absent, mangled, or was not produced by encodeRef. */
export function decodeRef(input: string | null | undefined): Ref | null {
  if (!input) return null;
  const dot = input.lastIndexOf('.');
  if (dot <= 0) return null;
  try {
    const payload = unb64url(input.slice(0, dot));
    if (fnv1a(payload).toString(36).slice(0, 4) !== input.slice(dot + 1)) return null;
    const [pageId, campaign] = payload.split('~');
    if (!pageId) return null;
    return { pageId, campaign: campaign ? decodeURIComponent(campaign) : null };
  } catch {
    return null;
  }
}

export type Channel =
  | 'facebook' | 'messenger' | 'instagram' | 'whatsapp' | 'direct' | 'other';

const HOSTS: [RegExp, Channel][] = [
  [/(^|\.)messenger\.com$|(^|\.)m\.me$/i, 'messenger'],
  [/(^|\.)facebook\.com$|(^|\.)fb\.com$|(^|\.)fb\.me$/i, 'facebook'],
  [/(^|\.)instagram\.com$/i, 'instagram'],
  [/(^|\.)whatsapp\.com$/i, 'whatsapp'],
];

/**
 * Which app the buyer arrived from.
 *
 * `fbclid` is checked before the referrer and that ordering is the point:
 * Facebook's in-app browser frequently sends no referrer at all, so a visit
 * that plainly came from Facebook otherwise records as `direct` and the
 * seller's best-performing channel reads as their worst.
 */
export function channelOf(input: {
  referrer?: string | null;
  query?: Record<string, string | undefined> | URLSearchParams | null;
}): Channel {
  const get = (k: string) => {
    const q = input.query;
    if (!q) return undefined;
    return q instanceof URLSearchParams ? q.get(k) ?? undefined : q[k];
  };
  if (get('fbclid')) return 'facebook';
  if (get('igshid')) return 'instagram';

  if (!input.referrer) return 'direct';
  try {
    const host = new URL(input.referrer).hostname;
    return HOSTS.find(([re]) => re.test(host))?.[1] ?? 'other';
  } catch {
    return 'other';
  }
}

/* ------------------------------------------------------------- the funnel */

/** How far a single visit got. Ordered worst to best. */
export type Outcome =
  | 'opened_only'
  | 'abandoned_at_claim'
  | 'failed_verification'
  | 'in_review'
  | 'paid_pending'
  | 'delivered';

/** Shapes kept minimal so a caller can pass either a live order or a report row. */
export interface FunnelOrder {
  visitId: string | null;
  pageId: string | null;
  status: 'awaiting_payment' | 'verifying' | 'review' | 'paid' | 'delivered' | 'failed' | 'refunded';
  claimedTrxId: string | null;
}

export interface FunnelVisit {
  id: string;
  pageId: string | null;
  campaign: string | null;
  channel: Channel | string;
  at: number;
}

export function outcomeOf(order: FunnelOrder | null | undefined): Outcome {
  if (!order) return 'opened_only';
  switch (order.status) {
    case 'delivered': return 'delivered';
    case 'paid': return 'paid_pending';
    case 'review': return 'in_review';
    case 'failed': return 'failed_verification';
    case 'refunded': return 'delivered';
    case 'verifying': return order.claimedTrxId ? 'failed_verification' : 'abandoned_at_claim';
    default: return order.claimedTrxId ? 'failed_verification' : 'abandoned_at_claim';
  }
}

/**
 * The question the seller asked: did it end here?
 *
 * True only when money is confirmed. A payment sitting in review is not an
 * ending — somebody still has to do something — and counting it as one is how
 * a dashboard shows a completion rate the seller's bank balance disagrees with.
 */
export const endedHere = (o: Outcome) => o === 'delivered' || o === 'paid_pending';

export interface Stage {
  key: 'opened' | 'started' | 'verified' | 'delivered';
  label: string;
  count: number;
  /** Share of the stage above it, 0-1. The number that shows where they leave. */
  keptFromPrevious: number;
}

export interface PageRow {
  pageId: string;
  campaign: string | null;
  opened: number;
  started: number;
  completed: number;
  /** Completed over opened, 0-1. */
  conversion: number;
}

export interface Funnel {
  stages: Stage[];
  pages: PageRow[];
  byChannel: { channel: string; opened: number; completed: number }[];
  /** Visits with no order at all — the silent majority, worth naming. */
  openedOnly: number;
}

export function funnel(visits: FunnelVisit[], orders: FunnelOrder[]): Funnel {
  const byVisit = new Map<string, FunnelOrder>();
  for (const o of orders) if (o.visitId) byVisit.set(o.visitId, o);

  const rows = visits.map((v) => ({ visit: v, outcome: outcomeOf(byVisit.get(v.id)) }));

  const opened = rows.length;
  const started = rows.filter((r) => r.outcome !== 'opened_only'
    && r.outcome !== 'abandoned_at_claim').length;
  const verified = rows.filter((r) => endedHere(r.outcome) || r.outcome === 'in_review').length;
  const delivered = rows.filter((r) => r.outcome === 'delivered').length;

  const stages: Stage[] = [
    { key: 'opened', label: 'Opened the link', count: opened, keptFromPrevious: 1 },
    { key: 'started', label: 'Entered a transaction ID', count: started, keptFromPrevious: ratio(started, opened) },
    { key: 'verified', label: 'Payment confirmed', count: verified, keptFromPrevious: ratio(verified, started) },
    { key: 'delivered', label: 'Product delivered', count: delivered, keptFromPrevious: ratio(delivered, verified) },
  ];

  const pageMap = new Map<string, PageRow>();
  for (const { visit, outcome } of rows) {
    const key = `${visit.pageId ?? 'direct'}::${visit.campaign ?? ''}`;
    const row = pageMap.get(key) ?? {
      pageId: visit.pageId ?? 'direct',
      campaign: visit.campaign,
      opened: 0, started: 0, completed: 0, conversion: 0,
    };
    row.opened++;
    if (outcome !== 'opened_only' && outcome !== 'abandoned_at_claim') row.started++;
    if (endedHere(outcome)) row.completed++;
    pageMap.set(key, row);
  }
  const pages = [...pageMap.values()]
    .map((r) => ({ ...r, conversion: ratio(r.completed, r.opened) }))
    .sort((a, b) => b.opened - a.opened);

  const channelMap = new Map<string, { channel: string; opened: number; completed: number }>();
  for (const { visit, outcome } of rows) {
    const c = channelMap.get(visit.channel) ?? { channel: visit.channel, opened: 0, completed: 0 };
    c.opened++;
    if (endedHere(outcome)) c.completed++;
    channelMap.set(visit.channel, c);
  }

  return {
    stages,
    pages,
    byChannel: [...channelMap.values()].sort((a, b) => b.opened - a.opened),
    openedOnly: rows.filter((r) => r.outcome === 'opened_only').length,
  };
}

/** Zero over zero is zero here, not NaN — this goes straight into a percentage. */
const ratio = (a: number, b: number) => (b > 0 ? a / b : 0);
