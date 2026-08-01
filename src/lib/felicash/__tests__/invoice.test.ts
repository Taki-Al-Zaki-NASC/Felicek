import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import {
  buildInvoice, counterKey, invoiceNumber, parseInvoiceNumber, sellerCode,
} from '../invoice.ts';
import { fromDhaka } from '../dhaka.ts';
import { freshSteps } from '../delivery.ts';
import type { Order } from '../schema.ts';
import type { Rate } from '../money.ts';

const RATE: Rate = { bdtPaisaPerUsd: 12_250, capturedAt: 0, source: 'manual' };
const AT = fromDhaka(2026, 7, 31, 23, 30);

test('an invoice number carries the seller, the month and the sequence', () => {
  assert.equal(invoiceNumber('NAZ', AT, 41), 'FC-NAZ-2607-0041');
  assert.equal(invoiceNumber('NAZ', AT, 1), 'FC-NAZ-2607-0001');
  assert.equal(invoiceNumber('NAZ', AT, 12_345), 'FC-NAZ-2607-12345');
});

test('the month on the invoice is the Dhaka month', () => {
  // 31 July 19:00 UTC is already 1 August in Dhaka. An invoice dated into the
  // previous month is a gap in one series and a duplicate risk in the next.
  const lateJulyUtc = Date.UTC(2026, 6, 31, 19, 0);
  assert.equal(invoiceNumber('NAZ', lateJulyUtc, 1), 'FC-NAZ-2608-0001');
  assert.equal(counterKey(lateJulyUtc), '2026-08');
});

test('a seller code is always three characters', () => {
  assert.equal(sellerCode('Nazmul Store'), 'NAZ');
  assert.equal(sellerCode('ab'), 'ABX');
  assert.equal(sellerCode(''), 'FCH');
  assert.equal(sellerCode('শিক্ষা'), 'FCH', 'a Bangla-only name still yields a code');
  assert.equal(sellerCode('7 Days Bootcamp'), '7DA');
});

test('an invoice number parses back into its parts', () => {
  assert.deepEqual(parseInvoiceNumber('FC-NAZ-2607-0041'),
    { code: 'NAZ', year: 2026, month: 7, seq: 41 });
  assert.deepEqual(parseInvoiceNumber(invoiceNumber(sellerCode('Nazmul'), AT, 9)),
    { code: 'NAZ', year: 2026, month: 7, seq: 9 });
});

test('anything that is not one of our numbers parses to null', () => {
  assert.equal(parseInvoiceNumber('FC-NAZ-2613-0001'), null, 'there is no month 13');
  assert.equal(parseInvoiceNumber('FC-NAZ-2607-41'), null);
  assert.equal(parseInvoiceNumber('INV-2026-41'), null);
  assert.equal(parseInvoiceNumber(''), null);
});

const order = (over: Partial<Order> = {}): Order => ({
  id: 'order1',
  sellerId: 'seller1',
  productId: 'p1',
  productTitle: 'Flutter in 30 Days',
  buyerName: 'Rafi Ahmed',
  buyerEmail: 'rafi@example.com',
  buyerMsisdn: '01712345678',
  claimedTrxId: 'ABC1234567',
  wallet: 'bkash',
  toMsisdn: '01812345678',
  priceUsdCents: 1999,
  askingPaisa: 244_900,
  paidPaisa: 244_900,
  status: 'delivered',
  ledgerId: 'seller1__bkash__ABC1234567',
  invoiceNo: 'FC-NAZ-2607-0041',
  fulfilment: 'https://drive.example/course',
  steps: freshSteps(),
  attribution: { pageId: null, pageName: null, campaign: null, channel: 'direct', visitId: null },
  note: null,
  createdAt: AT - 60_000,
  verifiedAt: AT,
  deliveredAt: AT,
  ...over,
});

const SELLER = { storeName: 'Nazmul Store', supportEmail: 'me@example.com', handle: 'nazmul' };

test('the invoice states both currencies and the rate between them', () => {
  const inv = buildInvoice(order(), SELLER, RATE);
  assert.equal(inv.number, 'FC-NAZ-2607-0041');
  assert.equal(inv.lines[0].value, '$19.99');
  assert.equal(inv.lines[1].value, '৳2,449');
  assert.match(inv.lines[1].detail ?? '', /1 USD = ৳122\.50/);
  assert.equal(inv.lines[2].value, '৳2,449');
  assert.match(inv.lines[2].detail ?? '', /ABC1234567/);
});

test('the invoice is built from the rate that applied at checkout', () => {
  // Reissued next week it must still show the taka figure the buyer paid, or
  // it stops being a record of anything.
  const inv = buildInvoice(order(), SELLER, RATE);
  assert.equal(inv.payment.askingPaisa, 244_900);
  assert.equal(inv.payment.paidPaisa, 244_900);
  assert.equal(inv.payment.trxId, 'ABC1234567');
});

test('an overpayment appears as its own line', () => {
  const inv = buildInvoice(order({ paidPaisa: 250_000 }), SELLER, RATE);
  assert.equal(inv.payment.overpaidPaisa, 5_100);
  const line = inv.lines.find((l) => l.label === 'Overpayment');
  assert.equal(line?.value, '৳51');
});

test('an exact payment has no overpayment line', () => {
  const inv = buildInvoice(order(), SELLER, RATE);
  assert.equal(inv.payment.overpaidPaisa, 0);
  assert.equal(inv.lines.some((l) => l.label === 'Overpayment'), false);
});

test('the buyer number is printed readably, not as raw digits', () => {
  assert.equal(buildInvoice(order(), SELLER, RATE).buyer.msisdn, '+880 1712-345678');
  assert.equal(buildInvoice(order({ buyerMsisdn: null }), SELLER, RATE).buyer.msisdn, null);
});

test('the document says what FeliCash is and is not', () => {
  // A buyer chasing a refund needs to know who holds the money. It is not us.
  const inv = buildInvoice(order(), SELLER, RATE);
  assert.match(inv.footnote, /does not hold funds/);
  assert.match(inv.footnote, /VAT/);
});

test('an order that never settled still dates its invoice from creation', () => {
  const inv = buildInvoice(order({ verifiedAt: null, paidPaisa: null }), SELLER, RATE);
  assert.equal(inv.issuedAt, AT - 60_000);
  assert.equal(inv.payment.paidPaisa, 244_900, 'falls back to the asking price');
});
