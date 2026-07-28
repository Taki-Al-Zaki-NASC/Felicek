'use client';

import { useState } from 'react';
import type { Job, Proposal } from '@/lib/schema';
import { describeError, shortlistProposal } from '@/lib/mutations';
import { hire, InsufficientPostingBalance } from '@/lib/escrow';
import { useSession } from '@/lib/session';
import { Card, ErrorState, Pill, money } from './ui';

/**
 * Proposals as the job owner sees them.
 *
 * The owner sees a score and a short preview of a challenge answer — never the
 * full submission. That is not a UI decision: the full answer lives in
 * `proposals/{id}/submission/full`, which firestore.rules scopes to its author,
 * so this page could not show it even if it tried.
 */
export function ProposalList({ job, proposals }: { job: Job; proposals: Proposal[] }) {
  const { user } = useSession();
  const [error, setError] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  async function hireThem(p: Proposal) {
    if (!user) return;
    if (!confirm(
      `Hire ${p.freelancerName} for ${money(p.bidAmountCents ?? 0)}? `
      + 'This moves that amount from your posting balance into escrow.')) return;
    setBusyId(p.id); setError(null);
    try {
      await hire(job, p, user.displayName);
    } catch (e) {
      // The balance message is written for the person reading it, so it is
      // passed through rather than flattened into a generic failure.
      setError(e instanceof InsufficientPostingBalance ? e.message : describeError(e));
    } finally {
      setBusyId(null);
    }
  }

  async function toggle(p: Proposal) {
    setBusyId(p.id); setError(null);
    try {
      await shortlistProposal(p.id, p.status !== 'shortlisted');
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusyId(null);
    }
  }

  return (
    <div className="space-y-3">
      {error && <ErrorState message={error} />}
      {proposals.map((p) => (
        <Card key={p.id}>
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div className="min-w-0">
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-semibold">{p.freelancerName}</span>
                <Pill tone={p.status === 'accepted' ? 'teal'
                  : p.status === 'shortlisted' ? 'blue'
                  : p.status === 'withdrawn' ? 'neutral' : 'neutral'}>
                  {p.status}
                </Pill>
                {typeof p.challenge?.score === 'number' && (
                  <Pill tone="violet">Challenge {p.challenge.score}%</Pill>
                )}
              </div>
              {p.note && <p className="mt-1.5 text-sm text-ink-muted">{p.note}</p>}
              {p.challenge?.preview && (
                <p className="mt-2 rounded-field bg-backdrop px-3 py-2 text-xs text-ink-muted">
                  {p.challenge.preview}
                  <span className="mt-1 block text-ink-faint">
                    Preview only — the full submission is private to its author.
                  </span>
                </p>
              )}
            </div>

            <div className="text-right">
              {typeof p.bidAmountCents === 'number' && (
                <p className="font-serif text-lg font-semibold">{money(p.bidAmountCents)}</p>
              )}
              {(job.status ?? 'open') === 'open' && !job.hiredProposalId
                && p.status !== 'withdrawn' && p.status !== 'declined' && (
                <div className="mt-2 flex flex-col items-end gap-1.5">
                  <button
                    onClick={() => void toggle(p)}
                    disabled={busyId === p.id}
                    className="rounded-[9px] bg-blue-tint px-2.5 py-1 text-[11px] font-semibold text-blue disabled:opacity-50"
                  >
                    {busyId === p.id ? '…'
                      : p.status === 'shortlisted' ? 'Shortlisted ✓' : 'Shortlist'}
                  </button>
                  <button
                    onClick={() => void hireThem(p)}
                    disabled={busyId === p.id}
                    className="rounded-[9px] bg-ink-strong px-2.5 py-1 text-[11px] font-semibold text-canvas disabled:opacity-50"
                  >
                    Hire
                  </button>
                </div>
              )}
            </div>
          </div>
        </Card>
      ))}
    </div>
  );
}
