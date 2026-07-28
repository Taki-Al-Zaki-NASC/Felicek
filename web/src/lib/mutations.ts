import {
  addDoc, collection, doc, getDoc, increment, runTransaction,
  serverTimestamp, updateDoc,
} from 'firebase/firestore';
import { firebase } from './firebase';
import type { Job, Milestone, Proposal } from './schema';

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
