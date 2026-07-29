'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import type { Route } from 'next';
import { useSession } from '@/lib/session';
import { describeError, postJob } from '@/lib/mutations';
import type { Milestone } from '@/lib/schema';
import { Button, Card, ErrorState, SectionLabel } from '@/components/ui';

const TYPES = [
  { key: 'freelance', label: 'Freelance' },
  { key: 'contract', label: 'Contract' },
  { key: 'fulltime', label: 'Full-time' },
  { key: 'internship', label: 'Internship' },
];

export default function PostJob() {
  const { user } = useSession();
  const router = useRouter();

  const [title, setTitle] = useState('');
  const [description, setDescription] = useState('');
  const [type, setType] = useState(TYPES[0]);
  const [budget, setBudget] = useState('');
  const [skillText, setSkillText] = useState('');
  const [milestones, setMilestones] = useState<Milestone[]>([
    { label: 'Kickoff', amount: '' },
  ]);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // A freelancer account cannot post; the rules refuse it, and offering the
  // form anyway would just produce a permission error at the end.
  if (user && user.role === 'freelancer') {
    return (
      <ErrorState message="Freelancer accounts bid on work rather than post it. Switch your account type from your profile to post a job." />
    );
  }

  const skills = skillText.split(',').map((s) => s.trim()).filter(Boolean);
  const ready = title.trim().length > 3 && description.trim().length > 20;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!user || busy || !ready) return;
    setBusy(true); setError(null);
    try {
      const budgetValue = Number(budget.replace(/[^0-9.]/g, ''));
      const id = await postJob({
        ownerId: user.uid,
        ownerName: user.displayName,
        title, description,
        type: type.key, typeLabel: type.label,
        budget,
        budgetValue: Number.isFinite(budgetValue) && budgetValue > 0 ? budgetValue : null,
        skills,
        milestones: milestones.filter((m) => m.label.trim()),
      });
      router.push(`/jobs/${id}` as Route);
    } catch (err) {
      setError(describeError(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto max-w-2xl">
      <h1 className="font-serif text-2xl font-semibold sm:text-3xl">Post a job</h1>
      <p className="mt-1 text-sm text-ink-muted">
        Only identity-verified, deposit-backed freelancers can bid on this.
      </p>

      <form onSubmit={submit} className="mt-7 space-y-5">
        <Text label="Title" value={title} onChange={setTitle}
          hint="What you need done, in a line." />
        <Area label="Description" value={description} onChange={setDescription}
          hint="Scope, deliverables, and how you will judge the work." />

        <div>
          <SectionLabel>Type</SectionLabel>
          <div className="mt-2 flex flex-wrap gap-2">
            {TYPES.map((t) => (
              <button key={t.key} type="button" onClick={() => setType(t)}
                aria-pressed={type.key === t.key}
                className={`rounded-[9px] px-3 py-1.5 text-xs font-semibold transition ${
                  type.key === t.key ? 'bg-violet text-white' : 'bg-violet-tint text-violet'
                }`}>
                {t.label}
              </button>
            ))}
          </div>
        </div>

        <Text label="Budget" value={budget} onChange={setBudget} hint="e.g. $1,200 or $45/hr" />
        <Text label="Skills" value={skillText} onChange={setSkillText}
          hint="Comma separated — these drive search and filtering." />

        <div>
          <SectionLabel>Milestones</SectionLabel>
          <p className="mt-1 text-xs text-ink-muted">
            Escrow is released one milestone at a time. Amounts like “$450” are
            parsed; anything else splits the accepted bid evenly.
          </p>
          <div className="mt-2 space-y-2">
            {milestones.map((m, i) => (
              <Card key={i} className="flex flex-wrap gap-2 p-2.5">
                <input
                  value={m.label}
                  onChange={(e) => setMilestones(milestones.map((x, j) =>
                    j === i ? { ...x, label: e.target.value } : x))}
                  placeholder="Stage"
                  className="min-w-0 flex-1 rounded-field border border-border px-3 py-2 text-base outline-none focus:border-teal sm:text-sm"
                />
                <input
                  value={m.amount}
                  onChange={(e) => setMilestones(milestones.map((x, j) =>
                    j === i ? { ...x, amount: e.target.value } : x))}
                  placeholder="$0.00"
                  className="w-28 rounded-field border border-border px-3 py-2 text-base outline-none focus:border-teal sm:text-sm"
                />
                {milestones.length > 1 && (
                  <button type="button" aria-label={`Remove milestone ${i + 1}`}
                    onClick={() => setMilestones(milestones.filter((_, j) => j !== i))}
                    className="px-2 text-sm text-ink-faint hover:text-danger">×</button>
                )}
              </Card>
            ))}
          </div>
          <button type="button"
            onClick={() => setMilestones([...milestones, { label: '', amount: '' }])}
            className="mt-2 text-xs font-bold text-teal-deep">+ Add milestone</button>
        </div>

        {error && <ErrorState message={error} />}

        <Button type="submit" busy={busy} disabled={!ready} className="w-full">
          Post job
        </Button>
        {!ready && (
          <p className="text-center text-xs text-ink-faint">
            A title and a description of at least 20 characters are required.
          </p>
        )}
      </form>
    </div>
  );
}

function Text({ label, value, onChange, hint }: {
  label: string; value: string; onChange: (v: string) => void; hint?: string;
}) {
  return (
    <label className="block">
      <span className="text-xs font-semibold text-ink-muted">{label}</span>
      <input value={value} onChange={(e) => onChange(e.target.value)}
        className="mt-1.5 w-full rounded-field border border-border bg-surface px-3.5 py-3 text-base outline-none focus:border-teal sm:text-sm" />
      {hint && <span className="mt-1 block text-xs text-ink-faint">{hint}</span>}
    </label>
  );
}

function Area({ label, value, onChange, hint }: {
  label: string; value: string; onChange: (v: string) => void; hint?: string;
}) {
  return (
    <label className="block">
      <span className="text-xs font-semibold text-ink-muted">{label}</span>
      <textarea value={value} rows={6} onChange={(e) => onChange(e.target.value)}
        className="mt-1.5 w-full rounded-field border border-border bg-surface px-3.5 py-3 text-base outline-none focus:border-teal sm:text-sm" />
      {hint && <span className="mt-1 block text-xs text-ink-faint">{hint}</span>}
    </label>
  );
}
