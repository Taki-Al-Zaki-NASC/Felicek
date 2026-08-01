/**
 * Sending the delivery email.
 *
 * One provider is wired up (Resend, because it is a single POST and its free
 * tier covers a seller doing a few hundred orders a month) behind an interface
 * narrow enough that swapping it is a file, not a refactor.
 *
 * The important case is the unconfigured one. A deployment with no mail
 * provider must not fail every order — the buyer already has their product on
 * the screen at that point, and the email is a convenience. So an absent
 * provider is `skipped` with a stated reason, never `failed`, and the order
 * still completes. Failing there would be marking a delivered order undelivered
 * because a nice-to-have was missing.
 */
export interface Envelope {
  to: string;
  subject: string;
  text: string;
  fromName: string;
  replyTo?: string;
}

export type SendResult =
  | { status: 'sent'; note: string }
  | { status: 'skipped'; note: string }
  | { status: 'failed'; note: string };

const FROM = () => process.env.FELICASH_MAIL_FROM;
const KEY = () => process.env.RESEND_API_KEY;

export const isMailConfigured = () => Boolean(KEY() && FROM());

export async function sendEmail(envelope: Envelope): Promise<SendResult> {
  const key = KEY();
  const from = FROM();
  if (!key || !from) {
    return {
      status: 'skipped',
      note: 'No mail provider is configured, so no email was sent. The buyer was '
        + 'shown the product on screen.',
    };
  }
  if (!envelope.to || !envelope.to.includes('@')) {
    return { status: 'skipped', note: 'The buyer did not leave an email address.' };
  }

  try {
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        authorization: `Bearer ${key}`,
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        from: `${envelope.fromName} <${from}>`,
        to: [envelope.to],
        subject: envelope.subject,
        text: envelope.text,
        ...(envelope.replyTo ? { reply_to: envelope.replyTo } : {}),
      }),
    });

    if (!res.ok) {
      // The provider's own body is not shown to a buyer and not stored raw;
      // the status is what a seller can act on, the rest is noise.
      return { status: 'failed', note: `The mail provider refused it (${res.status}).` };
    }
    return { status: 'sent', note: `Sent to ${envelope.to}.` };
  } catch {
    return { status: 'failed', note: 'The mail provider could not be reached.' };
  }
}
