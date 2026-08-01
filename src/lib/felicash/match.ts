/**
 * Matching a buyer's claim against the ledger.
 *
 * This is the whole product in one function. A buyer types a phone number and
 * a TrxID; somewhere in the seller's ledger there is — or is not — a row that
 * says money arrived. Everything else in FeliCash is plumbing around this
 * decision.
 *
 * Two principles it is built on:
 *
 * 1. **A failure is a sentence, not a code.** "Payment not found" is the
 *    answer that generates a support message. The buyer is holding a receipt;
 *    telling them *which* part disagreed — the amount was ৳200 short, the
 *    money came from a different number, the TrxID has already been used — is
 *    the difference between them fixing it themselves and them messaging the
 *    seller on Messenger at 1am.
 *
 * 2. **"I have never seen this TrxID" and "I have not heard from your device
 *    in nine minutes" are different answers.** The first is a rejection. The
 *    second is "not yet — try again in a moment", and returning the first when
 *    the second is true tells a buyer who genuinely paid that they did not.
 *    This is the failure mode a naive matcher has, and it is the one that
 *    costs the seller the sale.
 */
import type { Paisa } from './money.ts';
import { formatBdt } from './money.ts';
import { sameMsisdn, maskMsisdn } from './msisdn.ts';
import { normalizeTrxId, type Wallet } from './sms.ts';
import type { LedgerEntry } from './schema.ts';

export interface MatchPolicy {
  /** Settle even if the amount is short by up to this. Default zero. */
  underpayTolerancePaisa: Paisa;
  /** Overpayment up to this settles (and is flagged); beyond it, a human looks. */
  overpayAcceptPaisa: Paisa;
  /** A ledger row older than this cannot settle a new order. */
  maxEntryAgeMs: number;
  /** Require that the money came from the number the buyer typed. */
  requireSenderMatch: boolean;
  /**
   * How long after a device's last sync a missing TrxID is read as "not here
   * yet" rather than "not real". Deliberately generous: SMS delivery in
   * Bangladesh is routinely a minute or two behind the transaction itself,
   * and being wrong in this direction only costs a retry.
   */
  syncGraceMs: number;
}

export const DEFAULT_POLICY: MatchPolicy = {
  underpayTolerancePaisa: 0,
  overpayAcceptPaisa: 50_000, // ৳500
  maxEntryAgeMs: 7 * 24 * 60 * 60 * 1000,
  requireSenderMatch: true,
  syncGraceMs: 10 * 60 * 1000,
};

export type MatchReason =
  | 'malformed_trxid'
  | 'unknown_trxid'
  | 'not_yet_synced'
  | 'already_claimed'
  | 'not_a_credit'
  | 'wrong_wallet'
  | 'wrong_account'
  | 'sender_mismatch'
  | 'amount_short'
  | 'amount_over'
  | 'stale_entry';

export type MatchWarning = 'overpaid' | 'third_party_payer' | 'underpaid_within_tolerance';

export type MatchOutcome =
  /** Money is in, the order can be delivered now. */
  | { status: 'settled'; entry: LedgerEntry; warnings: MatchWarning[]; paidPaisa: Paisa }
  /** A real payment that a person should look at before anything is released. */
  | { status: 'review'; entry: LedgerEntry; reason: MatchReason; message: string }
  /** No settlement. `retryable` means "the same claim may work shortly". */
  | { status: 'rejected'; reason: MatchReason; message: string; retryable: boolean };

export interface MatchInput {
  claim: {
    trxId: string;
    senderMsisdn: string | null;
  };
  expected: {
    askingPaisa: Paisa;
    wallet: Wallet;
    /** The seller number the buyer was told to send to. */
    toMsisdn: string;
  };
  /** Candidate rows. In production this is the lookup by deterministic id. */
  entries: LedgerEntry[];
  /** Last time the seller's forwarder checked in. Null means never. */
  lastSyncAt: number | null;
  now: number;
  policy?: Partial<MatchPolicy>;
}

export function matchClaim(input: MatchInput): MatchOutcome {
  const policy = { ...DEFAULT_POLICY, ...input.policy };
  const { expected, now } = input;

  const trxId = normalizeTrxId(input.claim.trxId);
  if (!trxId) {
    return reject('malformed_trxid', false,
      'That does not look like a transaction ID. It is the code at the end of '
      + 'the confirmation SMS — around ten letters and numbers, like 9F5D3A1B2C.');
  }

  const entry = input.entries.find((e) => normalizeTrxId(e.trxId) === trxId);

  if (!entry) {
    // The important fork. If the forwarder has not reported in recently, the
    // honest answer is that we do not know yet.
    const silentFor = input.lastSyncAt === null ? Infinity : now - input.lastSyncAt;
    if (silentFor > policy.syncGraceMs) {
      return reject('not_yet_synced', true,
        'We have not received this payment yet — the seller\'s confirmation feed '
        + 'is running behind. Your money is safe. Wait a minute and press verify '
        + 'again; nothing is charged twice.');
    }
    return reject('unknown_trxid', true,
      `No payment with transaction ID ${trxId} has reached this account. Check the `
      + 'ID against your confirmation SMS — it is easy to read 0 as O. If you have '
      + 'only just sent the money, wait a moment and try again.');
  }

  if (entry.claimedByOrderId) {
    return reject('already_claimed', false,
      'That transaction ID has already been used for another order. Each payment '
      + 'unlocks one purchase. If you believe this is a mistake, contact the seller '
      + `and quote ${trxId}.`);
  }

  if (!entry.credit) {
    return reject('not_a_credit', false,
      'That transaction ID belongs to a payment leaving the account, not one '
      + 'arriving. Check that you copied the ID from the SMS confirming the money '
      + 'you sent.');
  }

  if (entry.wallet !== expected.wallet) {
    return reject('wrong_wallet', false,
      `That payment came through ${walletName(entry.wallet)}, but this order was `
      + `set up for ${walletName(expected.wallet)}. Contact the seller — the money `
      + 'has arrived, it is just on the other wallet.');
  }

  if (now - entry.occurredAt > policy.maxEntryAgeMs) {
    return review(entry, 'stale_entry',
      'That payment is older than this order. The seller will confirm it by hand.');
  }

  // The seller's own number the money landed on. Only checked when the device
  // reports it — plenty of forwarders cannot tell which SIM took the SMS.
  if (entry.accountMsisdn && !sameMsisdn(entry.accountMsisdn, expected.toMsisdn)) {
    return review(entry, 'wrong_account',
      'That payment reached a different one of the seller\'s numbers than this '
      + 'order expected. The seller will confirm it by hand.');
  }

  const paid = entry.amountPaisa;
  const asking = expected.askingPaisa;
  const warnings: MatchWarning[] = [];

  if (paid < asking - policy.underpayTolerancePaisa) {
    const short = asking - paid;
    return reject('amount_short', true,
      `We received ${formatBdt(paid)} against ${formatBdt(asking)}. `
      + `Send the remaining ${formatBdt(short)} and verify again with the new `
      + 'transaction ID.');
  }
  if (paid < asking) warnings.push('underpaid_within_tolerance');

  if (paid > asking) {
    const over = paid - asking;
    if (over > policy.overpayAcceptPaisa) {
      return review(entry, 'amount_over',
        `We received ${formatBdt(paid)} against ${formatBdt(asking)} — `
        + `${formatBdt(over)} more than the price. The seller will confirm the `
        + 'order and arrange the difference.');
    }
    warnings.push('overpaid');
  }

  // Sender check last, so a buyer paying the wrong amount from the right
  // number is told about the amount rather than sent down a review path.
  if (entry.senderMsisdn && !sameMsisdn(entry.senderMsisdn, input.claim.senderMsisdn)) {
    if (policy.requireSenderMatch) {
      return reject('sender_mismatch', false,
        `That payment came from ${maskMsisdn(entry.senderMsisdn)}, not the number `
        + 'you entered. Enter the number the money was sent from — if a friend or '
        + 'family member paid for you, enter theirs.');
    }
    warnings.push('third_party_payer');
  }

  return { status: 'settled', entry, warnings, paidPaisa: paid };
}

const walletName = (w: Wallet) => (w === 'bkash' ? 'bKash' : 'Nagad');

const reject = (reason: MatchReason, retryable: boolean, message: string): MatchOutcome =>
  ({ status: 'rejected', reason, message, retryable });

const review = (entry: LedgerEntry, reason: MatchReason, message: string): MatchOutcome =>
  ({ status: 'review', entry, reason, message });

/**
 * What the seller sees in their orders list.
 *
 * Separate from the buyer-facing sentence on purpose: the buyer is told what
 * to do next, the seller is told what happened.
 */
export const SELLER_SUMMARY: Record<MatchReason, string> = {
  malformed_trxid: 'Buyer entered something that is not a transaction ID',
  unknown_trxid: 'No matching transaction in the ledger',
  not_yet_synced: 'Forwarder is behind — transaction not received yet',
  already_claimed: 'Transaction ID already used on another order',
  not_a_credit: 'Transaction is a debit, not an incoming payment',
  wrong_wallet: 'Paid on the other wallet',
  wrong_account: 'Landed on a different receiving number',
  sender_mismatch: 'Paid from a number the buyer did not declare',
  amount_short: 'Underpaid',
  amount_over: 'Overpaid beyond the automatic threshold',
  stale_entry: 'Transaction predates the order',
};
