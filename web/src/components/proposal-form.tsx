'use client';

import { useEffect, useState } from 'react';
import { useSession } from '@/lib/session';
import type { Job, Proposal } from '@/lib/schema';
import {
  describeError, myProposalFor, submitProposal, withdrawProposal,
} from '@/lib/mutations';
import { Button, Card, ErrorState, Loading, Pill, money } from './ui';
import { breakdown, CARD } from '@/lib/fees';

/**
 * Bid on a job.
 *
 * The existing-proposal lookup has three outcomes, not two: found, not found,
 * and *unknown*. Treating a failed read as "you have not applied" would offer
 * the form to someone who already applied, and a second submit is a duplicate
 * the owner has to untangle. That exact bug shipped in the Android app.
 */
export function ProposalForm({ job }: { job: Job }) {
  const { user } = useSession();
  const [mine, setMine] = useState<Proposal | null>(null);
  const [state, setState] = useState<'loading' | 'ready' | 'unknown'>('loading');
  const [bid, setBid] = useState('');
  const [note, setNote] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!user) return;
    let live = true;
    myProposalFor(job.id, user.uid)
      .then((p) => { if (live) { setMine(p); setState('ready'); } })
      .catch(() => { if (live) setState('unknown'); });
    return () => { live = false; };
  }, [job.id, user]);

  if (!user) return <Loading />;
  if (state === 'loading') return <Loading label="Checking your proposals…" />;

  if (state === 'unknown') {
    return (
      <ErrorState message="We could not check whether you have already applied to this job, so the form is hidden to avoid sending a duplicate. Reload to try again." />
    );
  }

  if (mine && mine.status !== 'withdrawn') {
    return (
      <Card>
        <div className="flex items-center justify-between">
          <span className="text-sm font-semibold">Your proposal</span>
          <Pill tone={mine.status === 'accepted' ? 'teal'
            : mine.status === 'shortlisted' ? 'blue'
            : mine.status === 'declined' ? 'danger' : 'neutral'}>
            {mine.status}
          </Pill>
        </div>
        {typeof mine.bidAmountCents === 'number' && (
          <p className="mt-2 font-serif text-2xl font-semibold">
            {money(mine.bidAmountCents)}
          </p>
        )}
        {mine.note && <p className="mt-2 text-sm text-ink-muted">{mine.note}</p>}

        {mine.status === 'submitted' && (
          <>
            {error && <div className="mt-3"><ErrorState message={error} /></div>}
            <Button variant="secondary" busy={busy} className="mt-4 w-full"
              onClick={async () => {
                setBusy(true); setError(null);
                try {
                  await withdrawProposal(mine.id);
                  setMine({ ...mine, status: 'withdrawn' });
                } catch (e) { setError(describeError(e)); }
                finally { setBusy(false); }
              }}>
              Withdraw
            </Button>
          </>
        )}
      </Card>
    );
  }

  if ((job.status ?? 'open') !== 'open') {
    return <Card><p className="text-sm text-ink-muted">This listing is no longer accepting proposals.</p></Card>;
  }

  const cents = Math.round(Number(bid.replace(/[^0-9.]/g, '')) * 100);
  const valid = Number.isFinite(cents) && cents > 0;
  const fees = valid ? breakdown(cents, CARD) : null;

  return (
    <Card>
      <h2 className="font-serif text-lg font-semibold">Submit a proposal</h2>
      <form
        className="mt-4 space-y-3"
        onSubmit={async (e) => {
          e.preventDefault();
          if (!valid || busy) return;
          setBusy(true); setError(null);
          try {
            const id = await submitProposal({
              job, freelancerId: user.uid, freelancerName: user.displayName,
              bidAmountCents: cents, note,
            });
            setMine({
              id, jobId: job.id, freelancerId: user.uid,
              freelancerName: user.displayName, status: 'submitted',
              bidAmountCents: cents, note,
            });
          } catch (err) { setError(describeError(err)); }
          finally { setBusy(false); }
        }}
      >
        <label className="block">
          <span className="text-xs font-semibold text-ink-muted">Your bid</span>
          <input value={bid} onChange={(e) => setBid(e.target.value)} placeholder="$0.00"
            className="mt-1.5 w-full rounded-field border border-border px-3.5 py-3 text-base outline-none focus:border-teal sm:text-sm" />
        </label>

        <label className="block">
          <span className="text-xs font-semibold text-ink-muted">Cover note</span>
          <textarea value={note} rows={5} onChange={(e) => setNote(e.target.value)}
            placeholder="Why you, and how you would approach it."
            className="mt-1.5 w-full rounded-field border border-border px-3.5 py-3 text-base outline-none focus:border-teal sm:text-sm" />
        </label>

        {fees && (
          <div className="rounded-field bg-backdrop p-3 text-xs">
            <Row label="Your bid" value={money(fees.grossCents)} />
            <Row label={`Processing (${fees.schedule.rate * 100}% + $0.30)`}
              value={`− ${money(fees.gatewayCents)}`} muted />
            <Row label="Felicek fee (1%)" value={`− ${money(fees.platformCents)}`} muted />
            <div className="my-1.5 h-px bg-border" />
            <Row label="You receive" value={money(fees.netCents)} strong />
            {fees.feesExceedAmount && (
              <p className="mt-2 text-danger">
                Fees exceed this amount — the flat processing charge does not scale down.
              </p>
            )}
          </div>
        )}

        {error && <ErrorState message={error} />}

        <Button type="submit" busy={busy} disabled={!valid} className="w-full">
          Submit proposal
        </Button>
      </form>
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
