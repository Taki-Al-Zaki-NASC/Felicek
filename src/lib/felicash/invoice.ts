/**
 * Invoices, generated rather than typed.
 *
 * The point of automating this is not tidiness. A seller running a course off
 * a Facebook page is asked for an invoice by exactly the people who matter —
 * a company buying seats, someone claiming it as an expense, and eventually a
 * tax office. Producing one by hand at that moment means reconstructing a
 * payment from a Messenger thread. Producing it at settlement means it already
 * exists, with the transaction ID on it.
 *
 * The number is sequential per seller per month and never reused, because a
 * gap or a duplicate in an invoice series is the first thing anyone auditing
 * one will notice.
 */
import { formatBdt, formatUsd, type Paisa, type Rate, type UsdCents } from './money.ts';
import { dhakaParts, formatDhaka } from './dhaka.ts';
import { formatBd } from './msisdn.ts';
import type { Order, Seller, Wallet } from './schema.ts';

/**
 * `FC-NAZ-2607-0041` — prefix, seller code, YYMM in Dhaka, sequence.
 *
 * YYMM rather than a running total so the sequence resets monthly and stays
 * short; a seller doing two hundred sales a month never sees a five-digit tail.
 */
export function invoiceNumber(code: string, at: number, seq: number): string {
  const p = dhakaParts(at);
  const yy = String(p.year % 100).padStart(2, '0');
  const mm = String(p.month).padStart(2, '0');
  return `FC-${sellerCode(code)}-${yy}${mm}-${String(seq).padStart(4, '0')}`;
}

/** Three upper-case letters. Derived from the store name when not set. */
export function sellerCode(input: string): string {
  const letters = (input ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  return (letters || 'FCH').slice(0, 3).padEnd(3, 'X');
}

export interface ParsedInvoiceNumber {
  code: string;
  year: number;
  month: number;
  seq: number;
}

export function parseInvoiceNumber(input: string): ParsedInvoiceNumber | null {
  const m = /^FC-([A-Z0-9]{3})-(\d{2})(\d{2})-(\d{4})$/.exec((input ?? '').trim());
  if (!m) return null;
  const month = Number(m[3]);
  if (month < 1 || month > 12) return null;
  return { code: m[1], year: 2000 + Number(m[2]), month, seq: Number(m[4]) };
}

/** The key a per-month counter is held under. Same YYMM the number carries. */
export function counterKey(at: number): string {
  const p = dhakaParts(at);
  return `${p.year}-${String(p.month).padStart(2, '0')}`;
}

export interface InvoiceLine {
  label: string;
  detail: string | null;
  /** Rendered value. Already formatted, because the two currencies mix here. */
  value: string;
  /** Emphasised in the printed document. */
  strong?: boolean;
}

export interface Invoice {
  number: string;
  issuedAt: number;
  issuedLabel: string;
  seller: { name: string; email: string; handle: string };
  buyer: { name: string; email: string; msisdn: string | null };
  item: { title: string; priceUsdCents: UsdCents };
  payment: {
    wallet: Wallet;
    trxId: string | null;
    toMsisdn: string;
    askingPaisa: Paisa;
    paidPaisa: Paisa;
    /** Positive when the buyer sent more than the price. Owed back to them. */
    overpaidPaisa: Paisa;
  };
  lines: InvoiceLine[];
  /** Regulatory reality: no VAT is computed. Said once, on the document. */
  footnote: string;
}

/**
 * Builds the document from an order that has settled.
 *
 * Takes the rate that was applied at checkout rather than the seller's current
 * one. An invoice reissued next week must show the same taka figure it showed
 * the day it was paid, or it stops being a record of anything.
 */
export function buildInvoice(
  order: Order,
  seller: Pick<Seller, 'storeName' | 'supportEmail' | 'handle'>,
  rate: Rate,
): Invoice {
  const paid = order.paidPaisa ?? order.askingPaisa;
  const overpaid = Math.max(0, paid - order.askingPaisa);
  const issuedAt = order.verifiedAt ?? order.createdAt;

  const lines: InvoiceLine[] = [
    {
      label: order.productTitle,
      detail: 'Digital product — delivered electronically',
      value: formatUsd(order.priceUsdCents),
    },
    {
      label: 'Converted at',
      detail: `1 USD = ${formatBdt(rate.bdtPaisaPerUsd)} (${rate.source})`,
      value: formatBdt(order.askingPaisa),
    },
    {
      label: `Paid by ${walletName(order.wallet)}`,
      detail: order.claimedTrxId ? `TrxID ${order.claimedTrxId}` : null,
      value: formatBdt(paid),
      strong: true,
    },
  ];

  if (overpaid > 0) {
    lines.push({
      label: 'Overpayment',
      detail: 'Returned or credited by the seller',
      value: formatBdt(overpaid),
    });
  }

  return {
    number: order.invoiceNo ?? '—',
    issuedAt,
    issuedLabel: formatDhaka(issuedAt),
    seller: { name: seller.storeName, email: seller.supportEmail, handle: seller.handle },
    buyer: {
      name: order.buyerName,
      email: order.buyerEmail,
      msisdn: order.buyerMsisdn ? formatBd(order.buyerMsisdn) : null,
    },
    item: { title: order.productTitle, priceUsdCents: order.priceUsdCents },
    payment: {
      wallet: order.wallet,
      trxId: order.claimedTrxId,
      toMsisdn: order.toMsisdn,
      askingPaisa: order.askingPaisa,
      paidPaisa: paid,
      overpaidPaisa: overpaid,
    },
    lines,
    footnote:
      'Paid directly between buyer and seller over mobile financial services. '
      + 'FeliCash records and verifies the transfer; it does not hold funds and '
      + 'is not a party to the sale. No VAT has been computed on this document.',
  };
}

const walletName = (w: Wallet) => (w === 'bkash' ? 'bKash' : 'Nagad');
