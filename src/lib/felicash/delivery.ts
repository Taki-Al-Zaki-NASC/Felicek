/**
 * Payment confirmed → invoice → product delivered → email sent.
 *
 * The automation the whole thing exists for, written as a state machine rather
 * than a straight line of awaits. That is not architecture for its own sake:
 * email sending fails, and it fails *after* the money is confirmed and the
 * invoice number has been burned. A straight line either loses the order or
 * re-runs the paid parts on retry. A machine that records where it got to can
 * be resumed by anything — a retry, a cron, a seller pressing a button — and
 * will not hand out a second licence key to the same buyer.
 *
 * Every step is idempotent by that construction: a step already `done` is
 * never the next step.
 */
import type { Order, OrderStatus, Product, StepName, StepRecord } from './schema.ts';
import { formatBdt } from './money.ts';
import { formatDhaka } from './dhaka.ts';

/** The pipeline, in order. `verify` is already done by the time an order exists. */
export const STEPS: StepName[] = ['verify', 'invoice', 'fulfil', 'email'];

export const MAX_ATTEMPTS = 5;

export const freshSteps = (): Record<StepName, StepRecord> => ({
  verify: blank(), invoice: blank(), fulfil: blank(), email: blank(),
});

const blank = (): StepRecord => ({ state: 'pending', attempts: 0, at: null, note: null });

/**
 * The next thing to do, or null when there is nothing left.
 *
 * Returns null on a failed step too. A step that has failed its attempts is
 * not "next" — it is a thing the seller has to look at, and quietly retrying
 * it forever is how a broken SMTP password turns into ten thousand queued
 * sends.
 */
export function nextStep(steps: Record<StepName, StepRecord>): StepName | null {
  for (const s of STEPS) {
    const rec = steps[s];
    if (rec.state === 'done' || rec.state === 'skipped') continue;
    if (rec.state === 'failed' && rec.attempts >= MAX_ATTEMPTS) return null;
    return s;
  }
  return null;
}

export function markStep(
  steps: Record<StepName, StepRecord>,
  step: StepName,
  state: StepRecord['state'],
  at: number,
  note: string | null = null,
): Record<StepName, StepRecord> {
  const prev = steps[step];
  return {
    ...steps,
    [step]: {
      state,
      // Attempts count tries, not failures, so a step that succeeds on the
      // third go still reads as having taken three.
      attempts: state === 'pending' ? prev.attempts : prev.attempts + 1,
      at,
      note,
    },
  };
}

/**
 * The order status implied by the steps.
 *
 * Derived rather than stored alongside them, because two fields that describe
 * the same fact are two fields that will eventually disagree.
 *
 * `paid` and `delivered` are kept apart deliberately. Money confirmed is the
 * seller's fact; product in the buyer's hands is the buyer's. An order whose
 * email bounced is paid and not delivered, and collapsing the two would hide
 * exactly the orders that need a human.
 *
 * `review` and `refunded` are not derivable from steps — they are decisions,
 * set by the claim route and by the seller respectively.
 */
export function statusFor(
  steps: Record<StepName, StepRecord>,
  paid: boolean,
): OrderStatus {
  if (!paid) return steps.verify.state === 'failed' ? 'failed' : 'verifying';
  const settled = (s: StepRecord) => s.state === 'done' || s.state === 'skipped';
  return settled(steps.fulfil) && settled(steps.email) ? 'delivered' : 'paid';
}

/**
 * Backoff between retries: 30s, 2m, 8m, 30m, 2h.
 *
 * Quadrupling rather than doubling because the things that fail here — an
 * email provider rate limit, a DNS blip — are minutes-long outages, and four
 * doublings from thirty seconds is still only eight minutes.
 */
export function retryDelayMs(attempt: number): number {
  const schedule = [30_000, 120_000, 480_000, 1_800_000, 7_200_000];
  return schedule[Math.min(Math.max(attempt, 0), schedule.length - 1)];
}

/* -------------------------------------------------------------- templates */

export const DEFAULT_EMAIL_SUBJECT = 'Your {{product}} is ready — {{invoice_no}}';

export const DEFAULT_EMAIL_BODY = [
  'Hi {{buyer_name}},',
  '',
  'Payment confirmed. Thank you.',
  '',
  '{{product}}',
  '{{fulfilment}}',
  '',
  'Paid: {{amount}} via {{wallet}}',
  'Transaction ID: {{trx_id}}',
  'Invoice: {{invoice_no}} — {{invoice_link}}',
  '',
  'Any trouble, just reply to this email.',
  '{{seller}}',
].join('\n');

export type TemplateVars = Record<string, string>;

export interface Rendered {
  text: string;
  /** Tokens the template used that nothing supplied. */
  missing: string[];
}

/**
 * Fills `{{token}}` placeholders.
 *
 * An unknown token renders as an empty string rather than being left in the
 * output. A buyer must never receive an email containing a literal
 * `{{dowload_link}}` because the seller mistyped it — so the typo is reported
 * back through `missing`, which the template editor shows at the moment of
 * saving, and the buyer's copy just reads a little short.
 */
export function renderTemplate(template: string, vars: TemplateVars): Rendered {
  const missing: string[] = [];
  const text = (template ?? '').replace(/\{\{\s*([a-z0-9_]+)\s*\}\}/gi, (_, name: string) => {
    const key = name.toLowerCase();
    if (!(key in vars)) { missing.push(key); return ''; }
    return vars[key];
  });
  return { text, missing: [...new Set(missing)] };
}

/** Everything a delivery template may refer to. One place, so the editor can list it. */
export function templateVars(
  order: Order,
  opts: { fulfilment: string | null; invoiceLink: string; sellerName: string },
): TemplateVars {
  return {
    buyer_name: order.buyerName || 'there',
    buyer_email: order.buyerEmail,
    product: order.productTitle,
    amount: formatBdt(order.paidPaisa ?? order.askingPaisa),
    wallet: order.wallet === 'bkash' ? 'bKash' : 'Nagad',
    trx_id: order.claimedTrxId ?? '—',
    invoice_no: order.invoiceNo ?? '—',
    invoice_link: opts.invoiceLink,
    fulfilment: opts.fulfilment ?? '',
    order_id: order.id,
    seller: opts.sellerName,
    date: formatDhaka(order.verifiedAt ?? order.createdAt),
  };
}

export const TEMPLATE_TOKENS = [
  'buyer_name', 'buyer_email', 'product', 'amount', 'wallet', 'trx_id',
  'invoice_no', 'invoice_link', 'fulfilment', 'order_id', 'seller', 'date',
];

/* ------------------------------------------------------------- fulfilment */

export type Fulfilment =
  | { ok: true; payload: string; keysLeft: number | null; manual: false }
  | { ok: true; payload: string; keysLeft: null; manual: true }
  | { ok: false; reason: 'out_of_stock' | 'not_configured'; message: string };

/**
 * What the buyer gets, and what is left afterwards.
 *
 * Pure: it computes the next key pool rather than mutating one, so the caller
 * can write the order and the decremented pool in a single transaction. A key
 * popped outside a transaction is a key handed to two buyers the first time
 * two people pay at once.
 */
export function fulfil(product: Pick<Product, 'delivery'>): Fulfilment {
  const d = product.delivery;
  switch (d.kind) {
    case 'link':
    case 'file':
      if (!d.payload) {
        return { ok: false, reason: 'not_configured',
          message: 'No download link is set on this product.' };
      }
      return { ok: true, payload: d.payload, keysLeft: null, manual: false };

    case 'key': {
      const next = d.keys[0];
      if (!next) {
        return { ok: false, reason: 'out_of_stock',
          message: 'The licence keys for this product have run out.' };
      }
      return { ok: true, payload: next, keysLeft: d.keys.length - 1, manual: false };
    }

    case 'manual':
    default:
      return { ok: true, payload: '', keysLeft: null, manual: true };
  }
}

/** The pool after a key has been issued. Never mutates the argument. */
export const poolAfterIssue = (keys: string[]) => keys.slice(1);
