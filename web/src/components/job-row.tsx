import Link from 'next/link';
import type { Route } from 'next';
import type { Job } from '@/lib/schema';
import { Card, Pill } from './ui';

/** One listing in a feed. Shared by the dashboard, browse and search. */
export function JobRow({ job, owner = false }: { job: Job; owner?: boolean }) {
  const status = job.status ?? 'open';
  return (
    <Card className="transition hover:border-border-strong">
      <Link href={`/jobs/${job.id}` as Route} className="block">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="flex flex-wrap items-center gap-2">
              <Pill tone="violet">{job.typeLabel || job.type}</Pill>
              {status !== 'open' && (
                <Pill tone={status === 'filled' ? 'teal' : 'neutral'}>{status}</Pill>
              )}
            </div>
            <h3 className="mt-2 font-serif text-lg font-semibold">{job.title}</h3>
            {job.description && (
              <p className="mt-1 line-clamp-2 text-sm text-ink-muted">{job.description}</p>
            )}
            {job.skills && job.skills.length > 0 && (
              <div className="mt-2 flex flex-wrap gap-1.5">
                {job.skills.slice(0, 4).map((s) => <Pill key={s}>{s}</Pill>)}
              </div>
            )}
          </div>
          <div className="text-right">
            {job.budget && <p className="font-semibold">{job.budget}</p>}
            {owner && (
              <p className="mt-1 text-xs text-ink-faint">
                {job.proposalCount ?? 0} proposal{(job.proposalCount ?? 0) === 1 ? '' : 's'}
              </p>
            )}
          </div>
        </div>
      </Link>
    </Card>
  );
}
