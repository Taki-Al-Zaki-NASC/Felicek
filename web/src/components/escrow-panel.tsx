'use client';

import { useState } from 'react';
import type { Job, Proposal } from '@/lib/schema';
import { milestoneCents } from '@/lib/schema';
import { breakdown, LOCAL } from '@/lib/fees';
import { Button, Card, ErrorState, Pill, SectionLabel, money } from './ui';
import { InsufficientPostingBalance, releaseMilestone } from '@/lib/escrow';
import { describeError } from '@/lib/mutations';

/**
 * Escrow state and release for the job owner.
 *
 * Release runs the ported transaction in lib/escrow.ts: credit net of fees,
 * both ledger lines, escrow decremented, and on the last milestone the job
 * closes and the freelancer's trust bond unlocks.
 */
export function EscrowPanel({ job, proposals }: { job: Job; proposals: Proposal[] }) {
  const hired = proposals.find((p) => p.id === job.hiredProposalId);
  const milestones = job.milestones ?? [];

  if (!hired) {
    return (
      <Card>
        <SectionLabel>Escrow</SectionLabel>
        <p className="mt-2 text-sm text-ink-muted">
          Nothing is funded yet. Hiring a freelancer moves your posting balance
          into escrow for the first milestone.
        </p>
      </Card>
    );
  }

  const nextIndex = milestones.findIndex((m) => !m.released);
  const next = nextIndex >= 0 ? milestones[nextIndex] : undefined;
  const fees = next ? breakdown(milestoneCents(next, job, hired), LOCAL) : null;
  const releasedCount = milestones.filter((m) => m.released).length;

  return (
    <Card>
      <SectionLabel>Escrow</SectionLabel>
      <p className="mt-2 text-sm">
        <span className="font-semibold">{hired.freelancerName}</span> is hired.
      </p>
      <p className="mt-1 text-xs text-ink-muted">
        {releasedCount} of {milestones.length} milestone
        {milestones.length === 1 ? '' : 's'} released
        {typeof job.escrowHeldCents === 'number'
          && ` · ${money(job.escrowHeldCents)} held`}
      </p>

      {fees && (
        <div className="mt-4 rounded-field bg-backdrop p-3 text-xs">
          <p className="mb-1.5 font-semibold">Next: {next?.label}</p>
          <Row label="Milestone" value={money(fees.grossCents)} />
          <Row label="Processing (2%)" value={`− ${money(fees.gatewayCents)}`} muted />
          <Row label="Felicek fee (1%)" value={`− ${money(fees.platformCents)}`} muted />
          <div className="my-1.5 h-px bg-border" />
          <Row label="They receive" value={money(fees.netCents)} strong />
        </div>
      )}

      {next ? (
        <ReleaseButton job={job} proposal={hired} index={nextIndex}
          isFinal={milestones.filter((m) => !m.released).length === 1} />
      ) : (
        <div className="mt-3"><Pill tone="teal">All milestones released</Pill></div>
      )}
    </Card>
  );
}

function Row({ label, value, muted, strong }: {
  label: string; value: string; muted?: boolean; strong?: boolean;
}) {
  return (
    <div className={`flex justify-between ${muted ? 'text-ink-muted' : ''} ${strong ? 'font-bold' : ''}`}>
      <span>{label}</span><span>{value}</span>
    </div>
  );
}

function ReleaseButton({ job, proposal, index, isFinal }: {
  job: Job; proposal: Proposal; index: number; isFinal: boolean;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function release() {
    // Money leaving escrow is not undoable, so it gets a confirmation.
    const label = job.milestones?.[index]?.label ?? 'this milestone';
    if (!confirm(isFinal
      ? `Release "${label}" and complete this engagement? This cannot be undone.`
      : `Release "${label}" to ${proposal.freelancerName}? This cannot be undone.`)) {
      return;
    }
    setBusy(true); setError(null);
    try {
      await releaseMilestone(job, proposal, index);
    } catch (e) {
      setError(e instanceof InsufficientPostingBalance ? e.message : describeError(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <>
      {error && <div className="mt-3"><ErrorState message={error} /></div>}
      <Button className="mt-4 w-full" busy={busy} onClick={release}>
        {isFinal ? 'Release final milestone' : 'Release milestone'}
      </Button>
    </>
  );
}
