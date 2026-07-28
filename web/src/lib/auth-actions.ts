import {
  createUserWithEmailAndPassword, signInWithEmailAndPassword,
  sendPasswordResetEmail, signOut as fbSignOut, type UserCredential,
} from 'firebase/auth';
import { doc, serverTimestamp, writeBatch } from 'firebase/firestore';
import { firebase } from './firebase';
import { DEPOSIT_CENTS, type UserRoleKey } from './types';

/**
 * Maps Firebase's error codes to sentences.
 *
 * Never `e.message` — that is how CONFIGURATION_NOT_FOUND reached a user's
 * screen on Android looking like a network fault. Every code gets a sentence
 * or an honest fallback.
 */
export function describeAuthError(e: unknown): string {
  const code = (e as { code?: string })?.code ?? '';
  switch (code) {
    case 'auth/invalid-email': return 'That email address is not valid.';
    case 'auth/user-disabled': return 'This account has been disabled.';
    case 'auth/user-not-found':
    case 'auth/wrong-password':
    case 'auth/invalid-credential': return 'Email or password is incorrect.';
    case 'auth/email-already-in-use': return 'An account already exists for that email.';
    case 'auth/weak-password': return 'Choose a stronger password — at least 8 characters.';
    case 'auth/too-many-requests': return 'Too many attempts. Wait a minute and try again.';
    case 'auth/network-request-failed': return 'No connection. Check your network.';
    case 'auth/operation-not-allowed': return 'Email sign-in is not enabled for this project yet.';
    case 'auth/configuration-not-found':
      return 'This site is not connected to a working backend yet '
        + '(Authentication is not set up for this Firebase project). '
        + 'This is a setup issue, not your connection.';
    default: return 'Could not complete that. Please try again.';
  }
}

export async function signIn(email: string, password: string) {
  const fb = firebase();
  if (!fb) throw new Error('Firebase is not configured.');
  await signInWithEmailAndPassword(fb.auth, email.trim(), password);
}

export async function resetPassword(email: string) {
  const fb = firebase();
  if (!fb) throw new Error('Firebase is not configured.');
  await sendPasswordResetEmail(fb.auth, email.trim());
}

export async function signOut() {
  const fb = firebase();
  if (fb) await fbSignOut(fb.auth);
}

/**
 * Creates the account and its profile documents together.
 *
 * The shape has to match what the Android app writes, because both read the
 * same documents — and it has to satisfy firestore.rules, which requires the
 * email to match the token and the deposit to start unpaid.
 */
export async function signUp(
  email: string, password: string, displayName: string, role: UserRoleKey,
) {
  const fb = firebase();
  if (!fb) throw new Error('Firebase is not configured.');

  const cred: UserCredential =
    await createUserWithEmailAndPassword(fb.auth, email.trim(), password);
  const uid = cred.user.uid;
  const name = displayName.trim() || email.split('@')[0];

  const batch = writeBatch(fb.db);
  batch.set(doc(fb.db, 'users', uid), {
    email: cred.user.email,
    displayName: name,
    role,
    onboarded: false,
    profileComplete: false,
    kyc: {
      idSubmitted: false,
      depositPaid: false,       // rules reject any other starting value
      stage: 'none',
      depositAmountCents: DEPOSIT_CENTS[role],
    },
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
  });
  batch.set(doc(fb.db, 'profiles', uid), {
    uid, displayName: name, role, createdAt: serverTimestamp(),
  });
  await batch.commit();
}
