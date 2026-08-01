/**
 * Starting a checkout.
 *
 * The order is created *before* the buyer is shown the seller's number, not
 * after they claim a payment. Two reasons, one of each kind.
 *
 * Commercially: the seller learns who dropped out. An order with no
 * transaction ID on it is somebody who saw the price, got as far as the
 * payment details and left — which is the most useful row in the whole funnel
 * and is invisible if orders only exist once money moves.
 *
 * Practically: the receiving number is not on the public page. A bot crawling
 * checkout links gets a form, not a list of every seller's bKash number.
 */
import { admin, NOT_CONFIGURED } from '@/lib/felicash/server/admin';
import {
  accountFor, createOrder, productBySlug, recordVisit, sellerByHandle,
} from '@/lib/felicash/server/store';
import { asString, fail, json, looksLikeEmail, readJson } from '@/lib/felicash/server/http';
import { channelOf, decodeRef } from '@/lib/felicash/attribution';
import { freshSteps } from '@/lib/felicash/delivery';
import { usdToPaisa } from '@/lib/felicash/money';
import type { Order, Wallet } from '@/lib/felicash/schema';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

interface Body {
  handle?: string;
  slug?: string;
  buyerName?: string;
  buyerEmail?: string;
  wallet?: string;
  visitId?: string;
  ref?: string;
  referrer?: string;
}

export async function POST(req: Request) {
  const fb = admin();
  if (!fb) return fail(NOT_CONFIGURED, 503);

  const body = await readJson<Body>(req);
  if (!body) return fail('That request could not be read.', 400);

  const buyerName = asString(body.buyerName, 80);
  const buyerEmail = asString(body.buyerEmail, 160).toLowerCase();
  const wallet: Wallet = body.wallet === 'nagad' ? 'nagad' : 'bkash';

  if (buyerName.length < 2) return fail('Please enter your name.', 400);
  if (!looksLikeEmail(buyerEmail)) {
    return fail('Please enter an email address we can send the product to.', 400);
  }

  const seller = await sellerByHandle(fb.db, asString(body.handle, 60));
  if (!seller) return fail('That store does not exist.', 404);

  const product = await productBySlug(fb.db, seller.id, asString(body.slug, 80));
  if (!product || !product.active) {
    return fail('That product is not on sale.', 404);
  }

  const account = await accountFor(fb.db, seller.id, wallet);
  if (!account) {
    return fail(
      `This seller is not accepting ${wallet === 'bkash' ? 'bKash' : 'Nagad'} `
      + 'right now. Try the other wallet, or contact them.', 409,
    );
  }

  const now = Date.now();
  const ref = decodeRef(body.ref);
  const channel = channelOf({ referrer: body.referrer, query: null });

  // A visit is normally recorded when the page loads. Creating one here covers
  // a buyer whose browser blocked that call — an order with no visit would
  // otherwise vanish from the funnel entirely.
  const visitId = asString(body.visitId, 60) || await recordVisit(fb.db, {
    sellerId: seller.id,
    productId: product.id,
    pageId: ref?.pageId ?? null,
    campaign: ref?.campaign ?? null,
    channel,
    at: now,
    orderId: null,
  });

  const askingPaisa = product.priceOverridePaisa
    ?? usdToPaisa(product.priceUsdCents, seller.rate);

  const draft: Omit<Order, 'id'> = {
    sellerId: seller.id,
    productId: product.id,
    productTitle: product.title,
    buyerName,
    buyerEmail,
    buyerMsisdn: null,
    claimedTrxId: null,
    wallet,
    toMsisdn: account.msisdn,
    priceUsdCents: product.priceUsdCents,
    askingPaisa,
    paidPaisa: null,
    status: 'awaiting_payment',
    ledgerId: null,
    invoiceNo: null,
    fulfilment: null,
    steps: freshSteps(),
    attribution: {
      pageId: ref?.pageId ?? null,
      pageName: null,
      campaign: ref?.campaign ?? null,
      channel,
      visitId,
    },
    note: null,
    createdAt: now,
    verifiedAt: null,
    deliveredAt: null,
  };

  const order = await createOrder(fb.db, draft);

  return json({
    ok: true,
    orderId: order.id,
    askingPaisa,
    wallet,
    toMsisdn: account.msisdn,
    accountType: account.type,
    // Echoed back so the payment screen states the number it is asking for
    // rather than trusting whatever the form still holds.
    buyerEmail,
    reference: order.id.slice(-6).toUpperCase(),
  });
}
