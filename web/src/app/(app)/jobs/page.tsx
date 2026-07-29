'use client';

import { useMemo, useState } from 'react';
import Link from 'next/link';
import type { Route } from 'next';
import { useSession } from '@/lib/session';
import { openJobs, useCollection } from '@/lib/queries';
import type { Job } from '@/lib/schema';
import { JobRow } from '@/components/job-row';
import { EmptyState, ErrorState, Loading, SectionLabel } from '@/components/ui';

/**
 * Browse and filter open work — the Upwork search structure, Felicek styling.
 *
 * Filtering is client-side over the live open-jobs window. That is a
 * deliberate limit, not an oversight: Firestore cannot do full-text search,
 * and the app solves the same problem with denormalised `searchTerms` prefix
 * arrays rather than a paid search service. At this volume filtering the
 * loaded window is honest and instant; the prefix query is what it grows into.
 */
export default function BrowseJobs() {
  const { user } = useSession();
  const { data, loading, error } = useCollection<Job>('jobs', openJobs(60), []);
  const [term, setTerm] = useState('');
  const [skill, setSkill] = useState<string | null>(null);

  const skills = useMemo(() => {
    const counts = new Map<string, number>();
    for (const j of data) for (const s of j.skills ?? []) {
      counts.set(s, (counts.get(s) ?? 0) + 1);
    }
    return [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 12);
  }, [data]);

  const shown = useMemo(() => {
    const q = term.trim().toLowerCase();
    return data.filter((j) => {
      if (skill && !(j.skills ?? []).includes(skill)) return false;
      if (!q) return true;
      return `${j.title} ${j.description ?? ''} ${(j.skills ?? []).join(' ')}`
        .toLowerCase().includes(q);
    });
  }, [data, term, skill]);

  return (
    <>
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="font-serif text-2xl font-semibold sm:text-3xl">Find work</h1>
          <p className="mt-1 text-sm text-ink-muted">
            Every listing here is from an identity-verified, deposit-backed account.
          </p>
        </div>
        {user && user.role !== 'freelancer' && (
          <Link href={'/jobs/new' as Route}
            className="rounded-button bg-ink-strong px-5 py-3 text-sm font-bold text-canvas">
            Post a job
          </Link>
        )}
      </div>

      <div className="mt-6 grid gap-5 lg:grid-cols-[240px_1fr] lg:gap-6">
        <aside className="space-y-4 lg:space-y-5">
          <div>
            <SectionLabel>Search</SectionLabel>
            <input
              value={term}
              onChange={(e) => setTerm(e.target.value)}
              placeholder="Title, skill, keyword"
              className="mt-2 w-full rounded-field border border-border bg-surface px-3.5 py-2.5 text-base outline-none focus:border-teal sm:text-sm"
            />
          </div>

          {skills.length > 0 && (
            <div>
              <SectionLabel>Skills</SectionLabel>
              <div className="mt-2 flex flex-wrap gap-1.5 max-lg:max-h-24 max-lg:overflow-y-auto">
                {skills.map(([s, n]) => (
                  <button
                    key={s}
                    onClick={() => setSkill(skill === s ? null : s)}
                    aria-pressed={skill === s}
                    className={`rounded-[9px] px-2.5 py-1 text-[11px] font-semibold transition ${
                      skill === s ? 'bg-teal text-white' : 'bg-backdrop text-ink-muted hover:bg-border'
                    }`}
                  >
                    {s} <span className="opacity-60">{n}</span>
                  </button>
                ))}
              </div>
            </div>
          )}
        </aside>

        <section>
          {loading ? <Loading />
            : error ? <ErrorState message={error} />
            : shown.length === 0 ? (
              <EmptyState
                title={data.length === 0 ? 'Nothing open right now' : 'No match'}
                message={data.length === 0
                  ? 'New listings appear here as clients post them.'
                  : 'Try a different keyword, or clear the skill filter.'}
              />
            ) : (
              <div className="space-y-3">
                <p className="text-xs text-ink-faint">
                  {shown.length} of {data.length} open listing{data.length === 1 ? '' : 's'}
                </p>
                {shown.map((j) => <JobRow key={j.id} job={j} />)}
              </div>
            )}
        </section>
      </div>
    </>
  );
}
