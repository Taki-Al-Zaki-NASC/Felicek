'use client';

import type { Job, Proposal } from '@/lib/schema';
import { milestoneCents } from '@/lib/schema';
import { breakdown, LOCAL } from '@/lib/fees';
import { Card, Pill, SectionLabel, money } from './ui';

/**
 * Escrow state for the job owner.
 *
 * Read-only for now: releasing a milestone moves real money through a
 * transaction that also credits the ledger, closes the job and unlocks the
 * freelancer's trust bond. That belongs in one implementation, and it already
 * exists in EngagementRepository — porting it is the Escrow step, not this one.
 * Showing the numbers without the button is honest; a button that half-works
 * would not be.
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

  const next = milestones.find((m) => !m.released);
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

      {!next && (
        <div className="mt-3"><Pill tone="teal">All milestones released</Pill></div>
      )}

      <p className="mt-3 text-xs text-ink-faint">
        Releasing runs in the Android app for now — it moves money, credits both
        ledgers and closes the engagement in one transaction, and that is being
        ported rather than reimplemented.
      </p>
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
