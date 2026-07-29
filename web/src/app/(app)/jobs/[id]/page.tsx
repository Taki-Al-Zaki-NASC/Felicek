'use client';

import { use, useEffect, useState } from 'react';
import { doc, onSnapshot } from 'firebase/firestore';
import { firebase } from '@/lib/firebase';
import { useSession } from '@/lib/session';
import { proposalsForJob, useCollection } from '@/lib/queries';
import type { Job, Proposal } from '@/lib/schema';
import { describeError, setJobStatus } from '@/lib/mutations';
import {
  Button, Card, EmptyState, ErrorState, Loading, Pill, SectionLabel,
} from '@/components/ui';
import { ProposalForm } from '@/components/proposal-form';
import { ProposalList } from '@/components/proposal-list';
import { EscrowPanel } from '@/components/escrow-panel';

export default function JobDetail({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const { user } = useSession();
  const [job, setJob] = useState<Job | null>(null);
  const [state, setState] = useState<'loading' | 'ready' | 'missing' | 'error'>('loading');
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const fb = firebase();
    if (!fb) { setState('error'); setError('Firebase is not configured.'); return; }
    return onSnapshot(
      doc(fb.db, 'jobs', id),
      (snap) => {
        if (!snap.exists()) { setState('missing'); return; }
        setJob({ id: snap.id, ...snap.data() } as Job);
        setState('ready');
      },
      (e) => { setState('error'); setError(describeError(e)); },
    );
  }, [id]);

  if (state === 'loading') return <Loading />;
  if (state === 'error') return <ErrorState message={error ?? 'That could not be loaded.'} />;
  if (state === 'missing' || !job) {
    return <EmptyState title="Listing unavailable"
      message="This job may have been closed or removed." />;
  }

  const isOwner = user?.uid === job.ownerId;
  return isOwner ? <OwnerView job={job} /> : <FreelancerView job={job} />;
}

function OwnerView({ job }: { job: Job }) {
  const proposals = useCollection<Proposal>('proposals', proposalsForJob(job.id), [job.id]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function close() {
    if (!confirm('Close this listing? It will no longer accept proposals.')) return;
    setBusy(true); setError(null);
    try {
      await setJobStatus(job.id, 'closed');
    } catch (e) {
      setError(describeError(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="grid gap-6 md:gap-8 lg:grid-cols-[1fr_320px]">
      <div>
        <JobHeader job={job} />
        <div className="mt-8">
          <SectionLabel>Proposals ({proposals.data.length})</SectionLabel>
          <div className="mt-3">
            {proposals.loading ? <Loading />
              : proposals.error ? <ErrorState message={proposals.error} />
              : proposals.data.length === 0 ? (
                <EmptyState title="No proposals yet"
                  message="Verified freelancers will appear here as they bid." />
              ) : <ProposalList job={job} proposals={proposals.data} />}
          </div>
        </div>
      </div>

      <aside className="space-y-4">
        <EscrowPanel job={job} proposals={proposals.data} />
        {error && <ErrorState message={error} />}
        {(job.status ?? 'open') === 'open' && (
          <Button variant="danger" busy={busy} onClick={close} className="w-full">
            Close listing
          </Button>
        )}
      </aside>
    </div>
  );
}

function FreelancerView({ job }: { job: Job }) {
  return (
    <div className="grid gap-6 md:gap-8 lg:grid-cols-[1fr_340px]">
      <aside className="order-first lg:order-last"><ProposalForm job={job} /></aside>
      <JobHeader job={job} />
    </div>
  );
}

function JobHeader({ job }: { job: Job }) {
  const status = job.status ?? 'open';
  return (
    <article>
      <div className="flex flex-wrap items-center gap-2">
        <Pill tone="violet">{job.typeLabel || job.type}</Pill>
        {status !== 'open' && (
          <Pill tone={status === 'filled' ? 'teal' : 'neutral'}>{status}</Pill>
        )}
      </div>
      <h1 className="mt-3 font-serif text-2xl font-semibold sm:text-3xl">{job.title}</h1>
      <p className="mt-1 text-sm text-ink-muted">
        Posted by {job.ownerName}
        {job.budget ? ` · ${job.budget}` : ''}
      </p>

      {job.description && (
        <p className="mt-5 whitespace-pre-wrap text-sm leading-relaxed">{job.description}</p>
      )}

      {job.skills && job.skills.length > 0 && (
        <div className="mt-5 flex flex-wrap gap-1.5">
          {job.skills.map((s) => <Pill key={s} tone="blue">{s}</Pill>)}
        </div>
      )}

      {job.milestones && job.milestones.length > 0 && (
        <div className="mt-7">
          <SectionLabel>Milestones</SectionLabel>
          <div className="mt-2 space-y-2">
            {job.milestones.map((m, i) => (
              <Card key={i} className="flex items-center justify-between p-3">
                <span className="text-sm">{m.label}</span>
                <span className="flex items-center gap-2">
                  <span className="text-sm font-semibold">{m.amount || '—'}</span>
                  {m.released && <Pill tone="teal">Released</Pill>}
                </span>
              </Card>
            ))}
          </div>
        </div>
      )}
    </article>
  );
}
