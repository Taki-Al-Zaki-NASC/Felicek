/**
 * Payment confirmed → product delivered → email sent.
 *
 * The state machine in ../delivery.ts decides what happens next; this does it.
 * Keeping the decision and the doing apart is what makes the decision testable
 * without a database, and it is why a resumed pipeline cannot repeat a step:
 * `nextStep` never returns a step already marked done, whoever is calling.
 *
 * The pipeline is safe to call more than once on the same order, which matters
 * because three different things call it — a settled claim, a seller pressing
 * "deliver now", and a retry after a mail outage.
 */
import type { Firestore } from 'firebase-admin/firestore';
import type { Order, Product, Seller, StepName } from '../schema.ts';
import {
  fulfil, markStep, nextStep, renderTemplate, statusFor, templateVars,
  DEFAULT_EMAIL_BODY, DEFAULT_EMAIL_SUBJECT,
} from '../delivery.ts';
import { countSale, issueKey, updateOrder } from './store.ts';
import { sendEmail } from './email.ts';

export interface PipelineResult {
  order: Order;
  /** What the buyer should be shown right now. Null for a manual product. */
  fulfilment: string | null;
  emailNote: string;
}

export async function runDelivery(db: Firestore, args: {
  order: Order;
  seller: Seller;
  product: Product;
  baseUrl: string;
  now: number;
}): Promise<PipelineResult> {
  let { order } = args;
  const { seller, product, baseUrl, now } = args;
  let emailNote = '';

  // Bounded rather than `while (true)`: there are four steps, and a loop that
  // cannot terminate is not a risk worth taking in a payment path.
  for (let guard = 0; guard < 8; guard++) {
    const step: StepName | null = nextStep(order.steps);
    if (step === null || step === 'verify' || step === 'invoice') break;

    if (step === 'fulfil') {
      order = await doFulfil(db, order, product, now);
      continue;
    }

    const result = await doEmail(order, seller, product, baseUrl);
    emailNote = result.note;
    order = await persist(db, order,
      markStep(order.steps, 'email', result.status === 'sent' ? 'done'
        : result.status === 'skipped' ? 'skipped' : 'failed', now, result.note));
    break;
  }

  if (order.status === 'delivered' && !order.deliveredAt) {
    await updateOrder(db, order.id, { deliveredAt: now });
    order = { ...order, deliveredAt: now };
    void countSale(db, product.id);
  }

  return { order, fulfilment: order.fulfilment, emailNote };
}

async function doFulfil(
  db: Firestore, order: Order, product: Product, now: number,
): Promise<Order> {
  // Licence keys are popped in a transaction rather than read here, because
  // two buyers paying in the same second would otherwise be handed the same
  // key. Every other kind of delivery is a constant and needs no lock.
  if (product.delivery.kind === 'key') {
    const issued = await issueKey(db, product.id);
    if (!issued.ok) {
      return persist(db, order,
        markStep(order.steps, 'fulfil', 'failed', now,
          'The licence keys for this product have run out.'),
        { note: 'The seller has run out of keys for this product. They have been notified.' });
    }
    return persist(db, order, markStep(order.steps, 'fulfil', 'done', now),
      { fulfilment: issued.key });
  }

  const result = fulfil(product);
  if (!result.ok) {
    return persist(db, order, markStep(order.steps, 'fulfil', 'failed', now, result.message),
      { note: 'Your payment is confirmed. The seller has been notified to send your product.' });
  }
  if (result.manual) {
    // Not a failure: the seller always intended to hand this over themselves.
    return persist(db, order, markStep(order.steps, 'fulfil', 'skipped', now,
      'This product is delivered by the seller by hand.'),
      { note: 'Payment confirmed. The seller will send your product shortly.' });
  }
  return persist(db, order, markStep(order.steps, 'fulfil', 'done', now),
    { fulfilment: result.payload });
}

async function doEmail(
  order: Order, seller: Seller, product: Product, baseUrl: string,
) {
  const vars = templateVars(order, {
    fulfilment: order.fulfilment,
    invoiceLink: `${baseUrl}/i/${order.id}`,
    sellerName: seller.storeName,
  });
  const subject = renderTemplate(product.email?.subject || DEFAULT_EMAIL_SUBJECT, vars);
  const body = renderTemplate(product.email?.body || DEFAULT_EMAIL_BODY, vars);

  return sendEmail({
    to: order.buyerEmail,
    subject: subject.text,
    text: body.text,
    fromName: seller.storeName,
    replyTo: seller.supportEmail,
  });
}

/** Writes the step change and the status it implies, and returns the new order. */
async function persist(
  db: Firestore,
  order: Order,
  steps: Order['steps'],
  extra: Partial<Order> = {},
): Promise<Order> {
  const status = statusFor(steps, order.paidPaisa !== null);
  const patch = { ...extra, steps, status };
  await updateOrder(db, order.id, patch);
  return { ...order, ...patch };
}
