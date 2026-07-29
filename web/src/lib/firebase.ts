import { initializeApp, getApps, type FirebaseApp } from 'firebase/app';
import { getAuth, type Auth } from 'firebase/auth';
import { getFirestore, type Firestore } from 'firebase/firestore';

/**
 * Firebase for the web.
 *
 * Deliberately NOT google-services.json — that file is Android-only. A web app
 * has to be registered separately in the same project (felicek-9b728), which
 * yields the values below. Same project means the same Auth users, the same
 * Firestore documents, and the same security rules the 65 rules tests pin.
 *
 * NEXT_PUBLIC_* is compiled into the browser bundle, which is correct here and
 * not a leak: a Firebase web API key identifies a project, it does not
 * authorise anything. firestore.rules is the boundary. See the note in
 * .gitignore.
 */
const config = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  // Both spellings accepted: the Firebase console labels this
  // "messagingSenderId", so that is what people paste, but .env.example
  // originally shortened it. Reading either avoids a silently-undefined value.
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID
    ?? process.env.NEXT_PUBLIC_FIREBASE_SENDER_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

/** True once every required value is present. */
export const isFirebaseConfigured = Boolean(
  config.apiKey && config.projectId && config.appId,
);

/**
 * Returns null rather than throwing when config is missing.
 *
 * The Android app shipped a build where an unguarded Firebase getter threw
 * before the first frame, so the app hung on a splash screen forever with no
 * error. The same mistake here would be a blank page. Callers check for null
 * and render the "not configured" state instead.
 */
export function firebase(): { app: FirebaseApp; auth: Auth; db: Firestore } | null {
  if (!isFirebaseConfigured) return null;
  const app = getApps().length ? getApps()[0] : initializeApp(config);
  return { app, auth: getAuth(app), db: getFirestore(app) };
}
