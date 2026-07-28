import type { Timestamp } from 'firebase/firestore';

/**
 * Job, proposal and chat shapes, mirroring the Dart models.
 *
 * Fields are optional where the Android app writes them conditionally, so a
 * document written by an older build does not read as corrupt here.
 */

export type JobStatus = 'open' | 'filled' | 'closed';
export type ProposalStatus =
  | 'draft' | 'submitted' | 'shortlisted' | 'accepted' | 'declined' | 'withdrawn';

export interface Milestone {
  label: string;
  /** Free text as entered ("$450"), not cents — matches Milestone in job.dart. */
  amount: string;
  released?: boolean;
}

export interface Job {
  id: string;
  ownerId: string;
  ownerName: string;
  type: string;
  typeLabel: string;
  title: string;
  description?: string;
  skills?: string[];
  budget?: string;
  budgetValue?: number;
  status?: JobStatus;
  milestones?: Milestone[];
  proposalCount?: number;
  shortlisted?: number;
  views?: number;
  hiredProposalId?: string | null;
  hiredFreelancerId?: string | null;
  escrowHeldCents?: number;
  createdAt?: Timestamp;
  searchTerms?: string[];
}

export interface Proposal {
  id: string;
  jobId: string;
  jobTitle?: string;
  freelancerId: string;
  freelancerName: string;
  status: ProposalStatus;
  bidAmountCents?: number;
  note?: string;
  chatId?: string | null;
  challenge?: {
    completed?: boolean;
    score?: number | null;
    preview?: string | null;
  };
  createdAt?: Timestamp;
}

export interface ChatThread {
  id: string;
  participants: string[];
  participantNames?: Record<string, string>;
  jobId?: string | null;
  jobTitle?: string | null;
  lastMessage?: string;
  lastMessageAt?: Timestamp;
  readUpTo?: Record<string, Timestamp>;
}

export interface Message {
  id: string;
  senderId: string;
  senderName: string;
  text: string;
  imageBase64?: string | null;
  attachmentName?: string | null;
  watermarked?: boolean;
  sentAt?: Timestamp | null;
  clientSentAt?: Timestamp | null;
}

/**
 * A milestone's value in cents.
 *
 * Deliberately the same parse as EngagementRepository.milestoneCents in Dart:
 * pull a "$1,234.56" out of the free-text amount, else split the bid evenly.
 * If these two ever disagree, a client is shown one figure and charged
 * another.
 */
export function milestoneCents(m: Milestone, job: Job, proposal: Proposal): number {
  const match = /\$\s*([\d,]+(?:\.\d+)?)/.exec(m.amount ?? '');
  if (match) {
    const value = Number(match[1].replace(/,/g, ''));
    if (Number.isFinite(value) && value > 0) return Math.round(value * 100);
  }
  const count = job.milestones?.length || 1;
  return Math.round((proposal.bidAmountCents ?? 0) / count);
}
