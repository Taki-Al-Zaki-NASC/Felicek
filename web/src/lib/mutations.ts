import {
  addDoc, collection, doc, getDoc, increment, runTransaction,
  serverTimestamp, setDoc, updateDoc, writeBatch,
} from 'firebase/firestore';
import { firebase } from './firebase';
import type { Job, Milestone, Proposal } from './schema';
import type { CheckResult, DocumentType } from './identity-check';

/** Turns any thrown value into a sentence. Never surfaces the raw exception. */
export function describeError(e: unknown): string {
  const code = (e as { code?: string })?.code ?? '';
  if (code === 'permission-denied') {
    return 'The server refused that. Your account may not be verified, or the '
      + 'security rules have not been deployed for this project.';
  }
  if (code === 'unavailable') return 'No connection. Check your network and try again.';
  if (code === 'not-found') return 'That no longer exists.';
  if (code === 'failed-precondition') {
    return 'That could not be completed — something changed while you were working. '
      + 'Reload and try again.';
  }
  return 'That could not be completed. Please try again.';
}

/** Prefix terms for search, matching the app's denormalised searchTerms. */
function searchTerms(title: string, skills: string[]): string[] {
  const words = `${title} ${skills.join(' ')}`
    .toLowerCase().split(/[^a-z0-9]+/).filter((w) => w.length > 1);
  const out = new Set<string>();
  for (const w of words) {
    for (let i = 2; i <= Math.min(w.length, 12); i++) out.add(w.slice(0, i));
  }
  return [...out].slice(0, 200); // Firestore caps array-contains index entries
}

export async function postJob(input: {
  ownerId: string; ownerName: string;
  title: string; description: string; type: string; typeLabel: string;
  budget: string; budgetValue: number | null;
  skills: string[]; milestones: Milestone[];
}) {
  const fb = firebase();
  if (!fb) throw new Error('Firebase is not configured.');
  const ref = await addDoc(collection(fb.db, 'jobs'), {
    ownerId: input.ownerId,
    ownerName: input.ownerName,
    title: input.title.trim(),
    description: input.description.trim(),
    type: input.type,
    typeLabel: input.typeLabel,
    budget: input.budget.trim(),
    budgetValue: input.budgetValue,
    skills: input.skills,
    milestones: input.milestones,
    status: 'open',
    proposalCount: 0,
    shortlisted: 0,
    views: 0,
    escrowHeldCents: 0,
    searchTerms: searchTerms(input.title, input.skills),
    createdAt: serverTimestamp(),
  });
  return ref.id;
}

export async function setJobStatus(jobId: string, status: 'open' | 'closed') {
  const fb = firebase();
  if (!fb) throw new Error('Firebase is not configured.');
  await updateDoc(doc(fb.db, 'jobs', jobId), { status, updatedAt: serverTimestamp() });
}

/**
 * Submits a proposal.
 *
 * The document id is deterministic — `{jobId}__{uid}` — exactly as the app
 * builds it, so a double submit overwrites rather than creating a second
 * proposal for the same person on the same job.
 */
export async function submitProposal(input: {
  job: Job; freelancerId: string; freelancerName: string;
  bidAmountCents: number; note: string;
}) {
  const fb = firebase();
  if (!fb) throw new Error('Firebase is not configured.');
  const id = `${input.job.id}__${input.freelancerId}`;
  const ref = doc(fb.db, 'proposals', id);

  await runTransaction(fb.db, async (tx) => {
    const existing = await tx.get(ref);
    tx.set(ref, {
      jobId: input.job.id,
      jobTitle: input.job.title,
      ownerId: input.job.ownerId,
      freelancerId: input.freelancerId,
      freelancerName: input.freelancerName,
      bidAmountCents: input.bidAmountCents,
      note: input.note.trim(),
      status: 'submitted',
      createdAt: serverTimestamp(),
    }, { merge: true });

    // Only count a genuinely new proposal, or a resubmit inflates the tally.
    if (!existing.exists()) {
      tx.update(doc(fb.db, 'jobs', input.job.id), { proposalCount: increment(1) });
    }
  });
  return id;
}

export async function withdrawProposal(proposalId: string) {
  const fb = firebase();
  if (!fb) throw new Error('Firebase is not configured.');
  await updateDoc(doc(fb.db, 'proposals', proposalId), {
    status: 'withdrawn', updatedAt: serverTimestamp(),
  });
}

export async function shortlistProposal(proposalId: string, on: boolean) {
  const fb = firebase();
  if (!fb) throw new Error('Firebase is not configured.');
  await updateDoc(doc(fb.db, 'proposals', proposalId), {
    status: on ? 'shortlisted' : 'submitted', updatedAt: serverTimestamp(),
  });
}

/** Whether this account already has a proposal on this job. */
export async function myProposalFor(jobId: string, uid: string): Promise<Proposal | null> {
  const fb = firebase();
  if (!fb) return null;
  const snap = await getDoc(doc(fb.db, 'proposals', `${jobId}__${uid}`));
  return snap.exists() ? ({ id: snap.id, ...snap.data() } as Proposal) : null;
}

/**
 * Deterministic thread id, matching ChatThread.idFor in the app.
 *
 * Sorted so both participants derive the same id regardless of who opens the
 * conversation, and scoped by job so the same pair can hold separate threads
 * for separate engagements. Without this, two people opening a chat at the
 * same moment fork it into two.
 */
export function chatIdFor(a: string, b: string, jobId?: string | null) {
  const pair = [a, b].sort().join('__');
  return jobId ? `${pair}__${jobId}` : pair;
}

export async function openThread(input: {
  meId: string; meName: string;
  otherId: string; otherName: string;
  jobId?: string | null; jobTitle?: string | null;
}) {
  const fb = firebase();
  if (!fb) throw new Error('Firebase is not configured.');
  const id = chatIdFor(input.meId, input.otherId, input.jobId);
  await setDoc(doc(fb.db, 'chats', id), {
    participants: [input.meId, input.otherId].sort(),
    participantNames: { [input.meId]: input.meName, [input.otherId]: input.otherName },
    jobId: input.jobId ?? null,
    jobTitle: input.jobTitle ?? null,
    updatedAt: serverTimestamp(),
  }, { merge: true });
  return id;
}

/**
 * Sends a message and updates the thread preview in one batch-free pair.
 *
 * clientSentAt is set locally because an unresolved serverTimestamp reads as
 * null on the sending device, which would sort a pending message to the wrong
 * end of the list. The app orders on the same field for the same reason.
 */
export async function sendMessage(input: {
  chatId: string; senderId: string; senderName: string; text: string;
}) {
  const fb = firebase();
  if (!fb) throw new Error('Firebase is not configured.');
  const body = input.text.trim();
  if (!body) return;

  await addDoc(collection(fb.db, 'chats', input.chatId, 'messages'), {
    senderId: input.senderId,
    senderName: input.senderName,
    text: body,
    sentAt: serverTimestamp(),
    clientSentAt: new Date(),
  });
  await updateDoc(doc(fb.db, 'chats', input.chatId), {
    lastMessage: body.length > 120 ? `${body.slice(0, 119)}\u2026` : body,
    lastMessageAt: serverTimestamp(),
  });
}

/**
 * Marks the thread read up to now.
 *
 * A chat-level watermark, not a flag per message — one write marks two hundred
 * messages read instead of two hundred writes. Same shape the app uses, so
 * both surfaces read each other's receipts.
 */
export async function markRead(chatId: string, uid: string) {
  const fb = firebase();
  if (!fb) return;
  await updateDoc(doc(fb.db, 'chats', chatId), {
    [`readUpTo.${uid}`]: serverTimestamp(),
  });
}

/**
 * Records an identity submission: the number, the captured images, and the
 * screening verdict.
 *
 * Images go to the owner-only `identity` subcollection, never onto the profile
 * document — the profile is streamed live, so a few hundred KB there would be
 * re-downloaded on every unrelated change.
 *
 * A passing screen sets stage to verified because on the free tier there is no
 * server running a review queue, and an account that has paid a real deposit
 * should not block behind a review nobody performs. Documented in
 * docs/VERIFICATION.md; it is the first thing a real provider replaces.
 */
export async function submitIdentity(input: {
  uid: string;
  type: DocumentType;
  reference: string;
  documentBase64: string;
  selfieBase64: string;
  documentCheck: CheckResult;
  selfieCheck: CheckResult;
}) {
  const fb = firebase();
  if (!fb) throw new Error('Firebase is not configured.');

  const images = collection(fb.db, 'users', input.uid, 'identity');
  await setDoc(doc(images, 'document'), {
    kind: 'document', documentType: input.type,
    imageBase64: input.documentBase64, capturedAt: serverTimestamp(),
  });
  await setDoc(doc(images, 'selfie'), {
    kind: 'selfie', imageBase64: input.selfieBase64, capturedAt: serverTimestamp(),
  });

  await setDoc(doc(fb.db, 'users', input.uid), {
    kyc: {
      idSubmitted: true,
      idDocumentType: input.type,
      idReference: input.reference.trim(),
      hasDocumentImage: true,
      hasSelfieImage: true,
      stage: 'verified',
      autoCheck: {
        checkedAt: new Date().toISOString(),
        method: 'web-screening-v1',
        document: summarise(input.documentCheck),
        selfie: summarise(input.selfieCheck),
      },
      submittedAt: serverTimestamp(),
    },
    updatedAt: serverTimestamp(),
  }, { merge: true });
}

const summarise = (c: CheckResult) => ({
  passed: c.passed,
  sharpness: Number(c.sharpness.toFixed(1)),
  brightness: Number(c.brightness.toFixed(1)),
  width: c.width, height: c.height,
});

/**
 * Completes the profile and clears the onboarding stage.
 *
 * Sets both `onboarded` and `profileComplete`, because SessionController and
 * the web gate both require the pair — setting one leaves the account stuck on
 * a screen it just finished.
 *
 * Writes profiles/{uid} too: that is the public half other people read, and a
 * name saved only on the private document leaves the person appearing as
 * "Felicek user" everywhere else.
 */
export async function completeProfile(input: {
  uid: string;
  displayName: string;
  title: string;
  bio: string;
  location: string;
  skills: string[];
  hourlyRate: number | null;
  role: string;
}) {
  const fb = firebase();
  if (!fb) throw new Error('Firebase is not configured.');

  const name = input.displayName.trim();
  const shared = {
    displayName: name,
    title: input.title.trim(),
    bio: input.bio.trim(),
    location: input.location.trim(),
    skills: input.skills,
    hourlyRateCents: input.hourlyRate === null ? null : Math.round(input.hourlyRate * 100),
  };

  const batch = writeBatch(fb.db);
  batch.set(doc(fb.db, 'users', input.uid), {
    ...shared,
    onboarded: true,
    profileComplete: true,
    updatedAt: serverTimestamp(),
  }, { merge: true });
  batch.set(doc(fb.db, 'profiles', input.uid), {
    uid: input.uid,
    role: input.role,
    ...shared,
    updatedAt: serverTimestamp(),
  }, { merge: true });
  await batch.commit();
}
