/**
 * The FeliCash documents.
 *
 * Times are epoch milliseconds — plain numbers — not Firestore `Timestamp`s.
 * That is deliberate and it is the one place this file diverges from
 * lib/schema.ts on the marketplace side. A FeliCash document is written by an
 * API route through firebase-admin and read in a browser through the web SDK,
 * and those two packages ship different `Timestamp` classes that do not
 * `instanceof` each other. A number is the same number in both, needs no
 * conversion at the boundary, and sorts correctly in a Firestore query.
 *
 * Money is paisa everywhere. See money.ts.
 */
import type { Paisa, Rate, UsdCents } from './money.ts';
import type { Wallet, SmsKind } from './sms.ts';

/** Re-exported so a consumer of a document type needs one import, not two. */
export type { Wallet } from './sms.ts';

export const COL = {
  sellers: 'felicash_sellers',
  accounts: 'felicash_accounts',
  devices: 'felicash_devices',
  ledger: 'felicash_ledger',
  products: 'felicash_products',
  orders: 'felicash_orders',
  attempts: 'felicash_attempts',
  pages: 'felicash_pages',
  visits: 'felicash_visits',
} as const;

/* ------------------------------------------------------------------ seller */

export interface Seller {
  id: string;
  /** Owning Felicek account. One seller document per uid. */
  uid: string;
  /** URL segment: felicash.app/pay/<handle>/<slug>. Lower-case, unique. */
  handle: string;
  storeName: string;
  supportEmail: string;
  /** Prefix inside invoice numbers, e.g. `NAZ` in FC-NAZ-2607-0041. */
  invoiceCode: string;
  rate: Rate;
  /** Settle an order even when the money came from a different number. */
  allowThirdPartyPayer: boolean;
  /** Send the delivery email automatically, or hold every order for review. */
  autoDeliver: boolean;
  createdAt: number;
}

/* -------------------------------------------------- receiving accounts */

export type AccountType = 'personal' | 'agent' | 'merchant';

export interface ReceivingAccount {
  id: string;
  sellerId: string;
  wallet: Wallet;
  /** Canonical `01XXXXXXXXX`. See msisdn.ts. */
  msisdn: string;
  label: string;
  type: AccountType;
  active: boolean;
  createdAt: number;
}

/* ------------------------------------------------------------ sync device */

/**
 * A phone running the forwarder, holding the SIM the money lands on.
 *
 * Only the hash of its key is stored. A leaked database should not hand
 * somebody the ability to write fake payments into a seller's ledger, which is
 * exactly what a plaintext key column would do.
 */
export interface SyncDevice {
  id: string;
  sellerId: string;
  name: string;
  keyHash: string;
  keyHint: string;
  active: boolean;
  lastSeenAt: number | null;
  lastSyncAt: number | null;
  forwardedCount: number;
  createdAt: number;
}

/* ----------------------------------------------------------------- ledger */

export type LedgerSource = 'device' | 'manual' | 'import';

export interface LedgerEntry {
  /** `<sellerId>__<wallet>__<TRXID>`. Deterministic, so a replayed sync is a no-op. */
  id: string;
  sellerId: string;
  wallet: Wallet;
  trxId: string;
  kind: SmsKind;
  credit: boolean;
  senderMsisdn: string | null;
  /** The seller's own number the money landed on, when the device reports it. */
  accountMsisdn: string | null;
  amountPaisa: Paisa;
  feePaisa: Paisa | null;
  balancePaisa: Paisa | null;
  occurredAt: number;
  receivedAt: number;
  source: LedgerSource;
  deviceId: string | null;
  /** Set once, by the transaction that settles an order. The claim lock. */
  claimedByOrderId: string | null;
  claimedAt: number | null;
  /** SIM slot on the forwarding phone, for sellers running two numbers. */
  simSlot: number | null;
}

export const ledgerId = (sellerId: string, wallet: Wallet, trxId: string) =>
  `${sellerId}__${wallet}__${trxId}`;

/* ---------------------------------------------------------------- product */

export type DeliveryKind = 'link' | 'key' | 'file' | 'manual';

export interface Product {
  id: string;
  sellerId: string;
  slug: string;
  title: string;
  description: string;
  priceUsdCents: UsdCents;
  /** Overrides the seller rate when set — for a price fixed in taka. */
  priceOverridePaisa: Paisa | null;
  coverEmoji: string;
  active: boolean;
  delivery: {
    kind: DeliveryKind;
    /** A URL for `link`, a file path for `file`, ignored for `key`/`manual`. */
    payload: string;
    /** One-time keys for `key`. Popped in order; empty means sold out. */
    keys: string[];
    keysIssued: number;
  };
  email: {
    subject: string;
    body: string;
  };
  soldCount: number;
  createdAt: number;
}

/* ------------------------------------------------------------------ order */

/**
 * The order lifecycle, in the order it happens.
 *
 * `awaiting_payment` is the state a link sits in before anybody claims
 * anything; it exists so the funnel can tell a checkout nobody finished from
 * one nobody opened.
 */
export type OrderStatus =
  | 'awaiting_payment'
  | 'verifying'
  | 'review'
  | 'paid'
  | 'delivered'
  | 'failed'
  | 'refunded';

export type StepName = 'verify' | 'invoice' | 'fulfil' | 'email';
export type StepState = 'pending' | 'done' | 'failed' | 'skipped';

export interface StepRecord {
  state: StepState;
  attempts: number;
  at: number | null;
  /** A sentence, never a raw exception. Shown to the seller. */
  note: string | null;
}

export interface Order {
  id: string;
  sellerId: string;
  productId: string;
  productTitle: string;
  buyerName: string;
  buyerEmail: string;
  /** What the buyer typed. Canonicalised before it is stored. */
  buyerMsisdn: string | null;
  claimedTrxId: string | null;
  wallet: Wallet;
  /** The account the buyer was told to send to. */
  toMsisdn: string;
  priceUsdCents: UsdCents;
  askingPaisa: Paisa;
  paidPaisa: Paisa | null;
  status: OrderStatus;
  ledgerId: string | null;
  invoiceNo: string | null;
  /** Populated once fulfilment runs: the link, key or note the buyer receives. */
  fulfilment: string | null;
  steps: Record<StepName, StepRecord>;
  attribution: OrderAttribution;
  /** Buyer-facing sentence when something needs the seller's attention. */
  note: string | null;
  createdAt: number;
  verifiedAt: number | null;
  deliveredAt: number | null;
}

export interface OrderAttribution {
  /** Decoded from the `?r=` on the checkout link. Null for a direct visit. */
  pageId: string | null;
  pageName: string | null;
  campaign: string | null;
  /** `facebook`, `messenger`, `direct`, … as reported by the referrer. */
  channel: string;
  visitId: string | null;
}

/* --------------------------------------------------------- facebook page */

export interface ConnectedPage {
  id: string;
  sellerId: string;
  /** Numeric page id as Facebook reports it. */
  pageId: string;
  pageName: string;
  /** Echoed back on the webhook handshake. Generated, never chosen. */
  verifyToken: string;
  active: boolean;
  connectedAt: number;
  lastEventAt: number | null;
}

/** One checkout open, so an abandoned link is distinguishable from an unseen one. */
export interface Visit {
  id: string;
  sellerId: string;
  productId: string;
  pageId: string | null;
  campaign: string | null;
  channel: string;
  at: number;
  /** Set when this visit turns into an order. */
  orderId: string | null;
}

/* ---------------------------------------------------------- claim attempt */

export interface ClaimAttempt {
  id: string;
  sellerId: string;
  orderId: string | null;
  msisdn: string | null;
  trxId: string | null;
  outcome: string;
  at: number;
}
