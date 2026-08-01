/**
 * Every privileged read and write, in one place.
 *
 * Route handlers stay thin on purpose: they parse a request, call one function
 * here, and render the answer. The interesting decisions — what counts as a
 * duplicate, what happens inside the transaction that spends a transaction ID
 * — belong together where they can be read as a whole.
 */
import { FieldValue, type Firestore } from 'firebase-admin/firestore';
import { COL, ledgerId, type ConnectedPage, type LedgerEntry, type Order,
  type Product, type ReceivingAccount, type Seller, type SyncDevice,
  type Visit } from '../schema.ts';
import type { Wallet } from '../sms.ts';
import { parseSms, normalizeTrxId, walletFromOriginator } from '../sms.ts';
import { normalizeBd } from '../msisdn.ts';
import { counterKey, invoiceNumber } from '../invoice.ts';
import { freshSteps, markStep } from '../delivery.ts';
import { hashKey, keysMatch } from './keys.ts';
import type { Paisa } from '../money.ts';

const shape = <T>(snap: { id: string; data: () => unknown }): T =>
  ({ id: snap.id, ...(snap.data() as object) }) as T;

/* ---------------------------------------------------------------- lookups */

export async function sellerById(db: Firestore, id: string): Promise<Seller | null> {
  const snap = await db.collection(COL.sellers).doc(id).get();
  return snap.exists ? shape<Seller>(snap) : null;
}

export async function sellerByHandle(db: Firestore, handle: string): Promise<Seller | null> {
  const q = await db.collection(COL.sellers)
    .where('handle', '==', handle.trim().toLowerCase()).limit(1).get();
  return q.empty ? null : shape<Seller>(q.docs[0]);
}

export async function productBySlug(
  db: Firestore, sellerId: string, slug: string,
): Promise<Product | null> {
  const q = await db.collection(COL.products)
    .where('sellerId', '==', sellerId)
    .where('slug', '==', slug.trim().toLowerCase())
    .limit(1).get();
  return q.empty ? null : shape<Product>(q.docs[0]);
}

/**
 * The number a buyer is told to send to.
 *
 * A seller may have several; the first active one on that wallet wins. Which
 * one it was is recorded on the order, so a seller who rotates a SIM later can
 * still see where an old payment was meant to land.
 */
export async function accountFor(
  db: Firestore, sellerId: string, wallet: Wallet,
): Promise<ReceivingAccount | null> {
  const q = await db.collection(COL.accounts)
    .where('sellerId', '==', sellerId)
    .where('wallet', '==', wallet)
    .where('active', '==', true)
    .limit(1).get();
  return q.empty ? null : shape<ReceivingAccount>(q.docs[0]);
}

export async function pageById(
  db: Firestore, sellerId: string, pageId: string,
): Promise<ConnectedPage | null> {
  const q = await db.collection(COL.pages)
    .where('sellerId', '==', sellerId).where('pageId', '==', pageId)
    .limit(1).get();
  return q.empty ? null : shape<ConnectedPage>(q.docs[0]);
}

/* ----------------------------------------------------------------- device */

/**
 * Authenticates a forwarder.
 *
 * Looks the device up by hash — the plaintext key never touches a query — and
 * re-compares in constant time afterwards, so a hash collision or a partial
 * index match cannot authenticate anything.
 */
export async function deviceByKey(db: Firestore, key: string): Promise<SyncDevice | null> {
  const hash = hashKey(key);
  const q = await db.collection(COL.devices)
    .where('keyHash', '==', hash).where('active', '==', true).limit(1).get();
  if (q.empty) return null;
  const device = shape<SyncDevice>(q.docs[0]);
  return keysMatch(device.keyHash, hash) ? device : null;
}

export interface ForwardedMessage {
  originator: string;
  body: string;
  /** When the phone received the SMS. Used only when the body has no timestamp. */
  receivedAt?: number;
  simSlot?: number;
  /** Which of the seller's numbers took it, if the device knows. */
  accountMsisdn?: string;
}

export interface ForwardResult {
  stored: number;
  duplicate: number;
  ignored: number;
  /** Transaction IDs now on file, so the device can drop them from its outbox. */
  accepted: string[];
}

/**
 * Stores a batch of forwarded messages.
 *
 * Idempotent by document id: the row for a transaction is keyed on seller,
 * wallet and transaction ID, so a device that retries a batch after a timeout
 * — which is the normal case, not the rare one — rewrites the same document
 * instead of creating a second payment.
 *
 * A row that has already settled an order is never overwritten. Re-running an
 * old batch must not unclaim a transaction ID somebody already spent.
 */
export async function forwardMessages(
  db: Firestore,
  device: SyncDevice,
  messages: ForwardedMessage[],
  now: number,
): Promise<ForwardResult> {
  const result: ForwardResult = { stored: 0, duplicate: 0, ignored: 0, accepted: [] };
  const parsed: { id: string; entry: Omit<LedgerEntry, 'id'> }[] = [];

  for (const m of messages) {
    const wallet = walletFromOriginator(m.originator);
    if (!wallet) { result.ignored++; continue; }

    const sms = parseSms(m.body ?? '', wallet);
    if (!sms || !sms.trxId || sms.amountPaisa === null) { result.ignored++; continue; }

    const id = ledgerId(device.sellerId, wallet, sms.trxId);
    parsed.push({
      id,
      entry: {
        sellerId: device.sellerId,
        wallet,
        trxId: sms.trxId,
        kind: sms.kind,
        credit: sms.credit,
        senderMsisdn: sms.senderMsisdn,
        accountMsisdn: normalizeBd(m.accountMsisdn ?? null),
        amountPaisa: sms.amountPaisa,
        feePaisa: sms.feePaisa,
        balancePaisa: sms.balancePaisa,
        // The body's own timestamp is authoritative; the phone's clock is a
        // fallback, because a phone with the wrong date would otherwise file
        // real payments into the wrong month.
        occurredAt: sms.occurredAt ?? m.receivedAt ?? now,
        receivedAt: m.receivedAt ?? now,
        source: 'device',
        deviceId: device.id,
        claimedByOrderId: null,
        claimedAt: null,
        simSlot: m.simSlot ?? null,
      },
    });
  }

  if (parsed.length) {
    const refs = parsed.map((p) => db.collection(COL.ledger).doc(p.id));
    const existing = await db.getAll(...refs);
    const batch = db.batch();
    parsed.forEach((p, i) => {
      const prior = existing[i];
      if (prior.exists) {
        result.duplicate++;
        result.accepted.push(p.entry.trxId);
        return; // never rewrite a row that may already have settled an order
      }
      batch.set(refs[i], p.entry);
      result.stored++;
      result.accepted.push(p.entry.trxId);
    });
    await batch.commit();
  }

  await db.collection(COL.devices).doc(device.id).update({
    lastSeenAt: now,
    lastSyncAt: now,
    forwardedCount: FieldValue.increment(result.stored),
  });

  return result;
}

/**
 * The delta a device is missing, and the transaction IDs it reported that we
 * never stored.
 *
 * Same idea as the reference project's bidirectional sync: both sides send
 * what they have, and each learns what the other is missing, so neither has to
 * re-upload its whole history to converge.
 */
export async function syncDelta(
  db: Firestore, device: SyncDevice, deviceTrxIds: string[], limit = 500,
): Promise<{ missingOnServer: string[]; missingOnDevice: string[] }> {
  const q = await db.collection(COL.ledger)
    .where('sellerId', '==', device.sellerId)
    .orderBy('receivedAt', 'desc').limit(limit).get();

  const onServer = new Set(q.docs.map((d) => (d.data() as LedgerEntry).trxId));
  const onDevice = new Set(
    deviceTrxIds.map((t) => normalizeTrxId(t)).filter((t): t is string => t !== null),
  );

  return {
    missingOnServer: [...onDevice].filter((t) => !onServer.has(t)),
    missingOnDevice: [...onServer].filter((t) => !onDevice.has(t)),
  };
}

/** Both wallets are read, so paying on the wrong one is diagnosable. */
export async function candidateEntries(
  db: Firestore, sellerId: string, trxId: string,
): Promise<LedgerEntry[]> {
  const refs = (['bkash', 'nagad'] as Wallet[])
    .map((w) => db.collection(COL.ledger).doc(ledgerId(sellerId, w, trxId)));
  const snaps = await db.getAll(...refs);
  return snaps.filter((s) => s.exists).map((s) => shape<LedgerEntry>(s));
}

export async function lastSyncAt(db: Firestore, sellerId: string): Promise<number | null> {
  const q = await db.collection(COL.devices)
    .where('sellerId', '==', sellerId).where('active', '==', true).get();
  const times = q.docs
    .map((d) => (d.data() as SyncDevice).lastSyncAt)
    .filter((t): t is number => typeof t === 'number');
  return times.length ? Math.max(...times) : null;
}

/* ------------------------------------------------------------ visits, orders */

export async function recordVisit(
  db: Firestore, visit: Omit<Visit, 'id'>,
): Promise<string> {
  const ref = await db.collection(COL.visits).add(visit);
  return ref.id;
}

export async function createOrder(
  db: Firestore, order: Omit<Order, 'id'>,
): Promise<Order> {
  const ref = await db.collection(COL.orders).add(order);
  if (order.attribution.visitId) {
    // Best effort: a lost stitch costs a funnel row, not an order.
    await db.collection(COL.visits).doc(order.attribution.visitId)
      .update({ orderId: ref.id }).catch(() => undefined);
  }
  return { id: ref.id, ...order };
}

export async function orderById(db: Firestore, id: string): Promise<Order | null> {
  const snap = await db.collection(COL.orders).doc(id).get();
  return snap.exists ? shape<Order>(snap) : null;
}

export const updateOrder = (db: Firestore, id: string, patch: Partial<Order>) =>
  db.collection(COL.orders).doc(id).update(patch);

/* -------------------------------------------------------------- throttling */

/**
 * Failed attempts are kept as an array on one document per subject rather than
 * as a queryable collection.
 *
 * A collection would need an equality-plus-range composite index and a read
 * per attempt to trim. One document is a single read, a single write, and no
 * index — and the data is a bounded list of numbers that is never reported on.
 */
const attemptDoc = (db: Firestore, subject: string) =>
  db.collection(COL.attempts).doc(subject.replace(/[^a-z0-9:_-]/gi, '_').slice(0, 300));

export async function failuresFor(db: Firestore, subject: string): Promise<number[]> {
  const snap = await attemptDoc(db, subject).get();
  const data = snap.data() as { failures?: number[] } | undefined;
  return data?.failures ?? [];
}

/** Keeps the most recent 50. Older ones are outside every window anyway. */
export async function recordFailure(db: Firestore, subject: string, now: number) {
  const ref = attemptDoc(db, subject);
  const prior = await failuresFor(db, subject);
  await ref.set({ failures: [...prior, now].slice(-50), updatedAt: now });
}

export async function clearFailures(db: Firestore, subject: string) {
  await attemptDoc(db, subject).set({ failures: [], updatedAt: Date.now() });
}

/* ------------------------------------------------------------- settlement */

export class AlreadyClaimed extends Error {
  constructor() { super('already_claimed'); }
}

/**
 * Spends a transaction ID against an order, and allocates its invoice number.
 *
 * One transaction, and it has to be one. Two buyers submitting the same
 * transaction ID at the same moment is not a hypothetical — it is what happens
 * when somebody posts their receipt screenshot into the course's Facebook
 * group. Checking `claimedByOrderId` outside a transaction lets both reads see
 * null and both writes succeed, and the seller has sold one course twice.
 *
 * The invoice sequence is allocated in the same transaction for the same
 * reason: two concurrent settlements must not be handed the same number.
 */
export async function settleOrder(db: Firestore, args: {
  order: Order;
  entry: LedgerEntry;
  paidPaisa: Paisa;
  now: number;
}): Promise<{ invoiceNo: string }> {
  const { order, entry, paidPaisa, now } = args;
  const entryRef = db.collection(COL.ledger).doc(entry.id);
  const orderRef = db.collection(COL.orders).doc(order.id);
  const sellerRef = db.collection(COL.sellers).doc(order.sellerId);

  return db.runTransaction(async (tx) => {
    const [entrySnap, sellerSnap] = await Promise.all([tx.get(entryRef), tx.get(sellerRef)]);
    const fresh = entrySnap.data() as LedgerEntry | undefined;
    if (!fresh || fresh.claimedByOrderId) throw new AlreadyClaimed();

    const seller = sellerSnap.data() as Seller | undefined;
    const key = counterKey(now);
    const counters = (sellerSnap.data() as { invoiceCounters?: Record<string, number> })
      ?.invoiceCounters ?? {};
    const seq = (counters[key] ?? 0) + 1;
    const invoiceNo = invoiceNumber(seller?.invoiceCode ?? 'FCH', now, seq);

    tx.update(entryRef, { claimedByOrderId: order.id, claimedAt: now });
    tx.set(sellerRef, { invoiceCounters: { [key]: seq } }, { merge: true });

    const steps = markStep(
      markStep(order.steps ?? freshSteps(), 'verify', 'done', now),
      'invoice', 'done', now, invoiceNo,
    );
    tx.update(orderRef, {
      status: 'paid',
      paidPaisa,
      ledgerId: entry.id,
      invoiceNo,
      verifiedAt: now,
      steps,
      note: null,
    });

    return { invoiceNo };
  });
}

/**
 * Pops one licence key inside a transaction.
 *
 * Outside one, two buyers paying in the same second receive the same key.
 */
export async function issueKey(
  db: Firestore, productId: string,
): Promise<{ ok: true; key: string } | { ok: false; reason: 'out_of_stock' }> {
  const ref = db.collection(COL.products).doc(productId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const product = snap.data() as Product | undefined;
    const keys = product?.delivery?.keys ?? [];
    if (!keys.length) return { ok: false as const, reason: 'out_of_stock' as const };
    tx.update(ref, {
      'delivery.keys': keys.slice(1),
      'delivery.keysIssued': FieldValue.increment(1),
    });
    return { ok: true as const, key: keys[0] };
  });
}

export const countSale = (db: Firestore, productId: string) =>
  db.collection(COL.products).doc(productId)
    .update({ soldCount: FieldValue.increment(1) }).catch(() => undefined);
