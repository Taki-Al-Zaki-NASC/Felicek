/**
 * Reading a bKash or Nagad SMS.
 *
 * The reference project this idea comes from (bKash-Sync) parses the SMS on
 * the Android device and uploads a structured row. FeliCash parses here, on
 * the server, and the device forwards the body verbatim. That is a deliberate
 * difference and the reason for it is boring: bKash changes its SMS wording
 * without warning, and when it does, a device-side parser means every seller
 * is broken until they each install a new APK. A server-side parser means one
 * deploy. The device stays dumb on purpose.
 *
 * The other half of the job is refusing messages. A seller's own outgoing
 * "Cash Out" and "Send Money" texts contain an amount, a number and a TrxID,
 * and they are not income. Counting one as a payment would credit a buyer for
 * money the seller spent.
 */
import { parseTakaToPaisa, type Paisa } from './money.ts';
import { normalizeBd } from './msisdn.ts';
import { fromDhaka } from './dhaka.ts';

export type Wallet = 'bkash' | 'nagad';

/** What the message says happened. Only `credit` kinds can settle an order. */
export type SmsKind =
  | 'received'   // person-to-person Send Money, landing on a personal number
  | 'payment'    // merchant/QR Payment
  | 'cashin'     // agent Cash In
  | 'debit'      // anything leaving the account — never income
  | 'unknown';

export interface ParsedSms {
  wallet: Wallet;
  kind: SmsKind;
  /** True only for kinds that add money to the seller's balance. */
  credit: boolean;
  trxId: string | null;
  senderMsisdn: string | null;
  amountPaisa: Paisa | null;
  feePaisa: Paisa | null;
  balancePaisa: Paisa | null;
  /** Epoch ms, from the timestamp inside the message body, or null. */
  occurredAt: number | null;
}

/** Senders worth reading at all, so an unrelated promo SMS is dropped early. */
const ORIGINATORS: Record<string, Wallet> = {
  bkash: 'bkash',
  nagad: 'nagad',
  '16247': 'bkash',
  '16167': 'nagad',
};

export function walletFromOriginator(originator: string | null | undefined): Wallet | null {
  if (!originator) return null;
  return ORIGINATORS[originator.trim().toLowerCase()] ?? null;
}

/**
 * A bKash TrxID is ten characters of upper-case alphanumerics; Nagad's is
 * usually longer. Both are compared case-insensitively after trimming, because
 * a buyer copying one out of a notification picks up a trailing space roughly
 * every other time and types it in lower case the rest.
 */
export function normalizeTrxId(input: string | null | undefined): string | null {
  if (!input) return null;
  const cleaned = String(input).replace(/[^a-z0-9]/gi, '').toUpperCase();
  return cleaned.length >= 6 && cleaned.length <= 24 ? cleaned : null;
}

const DEBIT_MARKERS = [
  /you have sent/i, /cash out/i, /send money/i, /payment of tk/i,
  /has been debited/i, /you have paid/i, /withdraw/i, /transferred to/i,
];

const KIND_MARKERS: [RegExp, SmsKind][] = [
  [/cash in/i, 'cashin'],
  [/received payment|payment received|you have received payment/i, 'payment'],
  [/you have received|money received|received tk/i, 'received'],
];

/**
 * Parses a message body into a row, or returns null when it is not a wallet
 * message at all.
 *
 * Tolerant by construction: every field is pulled independently, so a wording
 * change that breaks the balance pattern still yields a usable amount, sender
 * and TrxID — which is all a match actually needs.
 */
export function parseSms(body: string, wallet: Wallet): ParsedSms | null {
  const text = (body ?? '').replace(/\s+/g, ' ').trim();
  if (!text) return null;

  const trxId = normalizeTrxId(
    /(?:trx\s*id|txn\s*id|transaction\s*id|trxid)[:\s.]*([a-z0-9]{6,24})/i.exec(text)?.[1],
  );
  const amountPaisa = parseTakaToPaisa(
    /(?:amount[:\s]*)?tk\.?\s*([\d,]+(?:\.\d{1,2})?)/i.exec(text)?.[1],
  );

  // Nothing here identifies a transaction without at least these two.
  if (!trxId && amountPaisa === null) return null;

  const isDebit = DEBIT_MARKERS.some((re) => re.test(text));
  const kind: SmsKind = isDebit
    ? 'debit'
    : KIND_MARKERS.find(([re]) => re.test(text))?.[1] ?? 'unknown';

  return {
    wallet,
    kind,
    credit: kind === 'received' || kind === 'payment' || kind === 'cashin',
    trxId,
    senderMsisdn: normalizeBd(
      /(?:from|sender)[:\s]*(\+?8?8?0?1[\d\s-]{8,14})/i.exec(text)?.[1],
    ),
    amountPaisa,
    feePaisa: parseTakaToPaisa(/fee[:\s]*tk\.?\s*([\d,]+(?:\.\d{1,2})?)/i.exec(text)?.[1]),
    balancePaisa: parseTakaToPaisa(
      /balance[:\s]*tk\.?\s*([\d,]+(?:\.\d{1,2})?)/i.exec(text)?.[1],
    ),
    occurredAt: parseSmsDate(text),
  };
}

/**
 * The timestamp inside the body, as epoch ms.
 *
 * Read as `dd/mm/yyyy`, which is what both wallets send and what everyone in
 * the country writes. Reading it American would silently turn 07/08 into
 * July and drop a month of payments into the wrong bucket — and the mistake
 * is invisible for the first twelve days of every month.
 */
export function parseSmsDate(text: string): number | null {
  const m = /(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})[,\s]+(\d{1,2}):(\d{2})(?::(\d{2}))?/
    .exec(text);
  if (!m) return null;
  const [, dd, mm, yy, hh, min, ss] = m;
  const day = Number(dd);
  const month = Number(mm);
  const year = yy.length === 2 ? 2000 + Number(yy) : Number(yy);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return fromDhaka(year, month, day, Number(hh), Number(min), Number(ss ?? 0));
}
