'use client';

import Link from 'next/link';
import type { Route } from 'next';
import { useSession } from '@/lib/session';
import { useCollection, myJobs, myProposals, openJobs } from '@/lib/queries';
import type { Job, Proposal } from '@/lib/schema';
import { EmptyState, ErrorState, Loading, SectionLabel, Stat, money } from '@/components/ui';
import { JobRow } from '@/components/job-row';

/**
 * Role-aware home.
 *
 * A client sees what they have posted and what it is costing; a freelancer
 * sees work to bid on and where their bids stand. Same split as the app's
 * home screen, which is itself the Upwork structure the brief asked for.
 */
export default function Dashboard() {
  const { user } = useSession();
  if (!user) return <Loading />;
  const posts = user.role !== 'freelancer';
  return posts ? <ClientHome uid={user.uid} name={user.displayName} />
               : <FreelancerHome uid={user.uid} name={user.displayName} />;
}

function ClientHome({ uid, name }: { uid: string; name: string }) {
  const jobs = useCollection<Job>('jobs', myJobs(uid), [uid]);

  if (jobs.loading) return <Loading />;
  // Never render "0 jobs, $0 escrow" off a failed read — that is a confident
  // wrong answer about the client's own money.
  if (jobs.error) return <ErrorState message={jobs.error} />;

  const open = jobs.data.filter((j) => (j.status ?? 'open') === 'open');
  const escrow = jobs.data.reduce((sum, j) => sum + (j.escrowHeldCents ?? 0), 0);
  const proposals = jobs.data.reduce((sum, j) => sum + (j.proposalCount ?? 0), 0);

  return (
    <>
      <Header title={`Welcome back, ${name}`} subtitle="Your postings and engagements." />

      <div className="mt-6 grid gap-3 sm:grid-cols-3">
        <Stat label="Open listings" value={String(open.length)} tone="teal" />
        <Stat label="Proposals received" value={String(proposals)} tone="blue" />
        <Stat label="Escrow held" value={money(escrow)} tone="violet" />
      </div>

      <div className="mt-9 flex items-center justify-between">
        <SectionLabel>Your listings</SectionLabel>
        <Link href={'/jobs/new' as Route} className="text-xs font-bold text-teal-deep">
          Post a job
        </Link>
      </div>

      <div className="mt-3 space-y-3">
        {jobs.data.length === 0 ? (
          <EmptyState
            title="No listings yet"
            message="Post a job and verified freelancers can start bidding."
          />
        ) : jobs.data.map((j) => <JobRow key={j.id} job={j} owner />)}
      </div>
    </>
  );
}

function FreelancerHome({ uid, name }: { uid: string; name: string }) {
  const mine = useCollection<Proposal>('proposals', myProposals(uid), [uid]);
  const feed = useCollection<Job>('jobs', openJobs(), []);

  if (mine.loading || feed.loading) return <Loading />;

  const active = mine.data.filter(
    (p) => p.status === 'submitted' || p.status === 'shortlisted');
  const won = mine.data.filter((p) => p.status === 'accepted');

  return (
    <>
      <Header title={`Welcome back, ${name}`} subtitle="Work to bid on, and where your bids stand." />

      <div className="mt-6 grid gap-3 sm:grid-cols-3">
        <Stat label="Active bids" value={mine.error ? '—' : String(active.length)} tone="blue" />
        <Stat label="Won" value={mine.error ? '—' : String(won.length)} tone="teal" />
        <Stat label="Open listings" value={feed.error ? '—' : String(feed.data.length)} tone="violet" />
      </div>

      {mine.error && <div className="mt-4"><ErrorState message={mine.error} /></div>}

      <div className="mt-9 flex items-center justify-between">
        <SectionLabel>Open work</SectionLabel>
        <Link href={'/jobs' as Route} className="text-xs font-bold text-teal-deep">
          Browse all
        </Link>
      </div>

      <div className="mt-3 space-y-3">
        {feed.error ? <ErrorState message={feed.error} />
          : feed.data.length === 0 ? (
            <EmptyState title="Nothing open right now"
              message="New listings appear here as clients post them." />
          ) : feed.data.slice(0, 8).map((j) => <JobRow key={j.id} job={j} />)}
      </div>
    </>
  );
}

function Header({ title, subtitle }: { title: string; subtitle: string }) {
  return (
    <div>
      <h1 className="font-serif text-2xl font-semibold sm:text-3xl">{title}</h1>
      <p className="mt-1 text-sm text-ink-muted">{subtitle}</p>
    </div>
  );
}
