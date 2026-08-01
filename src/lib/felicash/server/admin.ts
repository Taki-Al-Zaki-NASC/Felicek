/**
 * The privileged Firestore handle. Server only — never imported by a page.
 *
 * Verification cannot happen in the browser, and this is not a stylistic
 * point. Matching a claim means reading the seller's ledger, and the seller's
 * ledger is every payment they have ever received: amounts, phone numbers,
 * running balance. A client-side match would need those documents readable by
 * whoever is standing on the checkout page. So the ledger is readable by
 * nobody through the rules, and only this handle — which bypasses them — can
 * see it.
 *
 * Returns null rather than throwing when the service account is absent, the
 * same discipline as lib/firebase.ts. A missing credential should render "this
 * deployment is not finished" on the checkout page, not a stack trace where
 * the price used to be.
 */
import { cert, getApps, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';

export interface AdminHandle {
  app: App;
  db: Firestore;
}

let cached: AdminHandle | null | undefined;

/**
 * The service account, from either a raw JSON string or base64 of one.
 *
 * Base64 is accepted because a JSON blob with newlines in a `\n`-escaped
 * private key is the single most commonly mangled environment variable there
 * is — every dashboard mangles it differently.
 */
function credentials(): { projectId: string; clientEmail: string; privateKey: string } | null {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) return null;
  try {
    const text = raw.trim().startsWith('{')
      ? raw
      : Buffer.from(raw, 'base64').toString('utf8');
    const parsed = JSON.parse(text) as Record<string, string>;
    const projectId = parsed.project_id ?? parsed.projectId;
    const clientEmail = parsed.client_email ?? parsed.clientEmail;
    const privateKey = (parsed.private_key ?? parsed.privateKey ?? '').replace(/\\n/g, '\n');
    if (!projectId || !clientEmail || !privateKey) return null;
    return { projectId, clientEmail, privateKey };
  } catch {
    return null;
  }
}

export function admin(): AdminHandle | null {
  if (cached !== undefined) return cached;
  const creds = credentials();
  if (!creds) { cached = null; return null; }

  const app = getApps().find((a) => a.name === 'felicash')
    ?? initializeApp({ credential: cert(creds), projectId: creds.projectId }, 'felicash');
  const db = getFirestore(app);
  // Firestore rejects undefined values outright; sparse documents are normal
  // here, and a dropped optional field is better than a rejected write.
  try { db.settings({ ignoreUndefinedProperties: true }); } catch { /* already set */ }

  cached = { app, db };
  return cached;
}

export const isAdminConfigured = () => admin() !== null;

/** The sentence shown when the deployment has no service account. */
export const NOT_CONFIGURED =
  'This FeliCash deployment has no server credentials yet, so payments cannot be '
  + 'verified. The store owner needs to set FIREBASE_SERVICE_ACCOUNT.';
