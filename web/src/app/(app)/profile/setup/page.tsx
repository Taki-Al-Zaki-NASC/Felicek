'use client';

import { useState } from 'react';
import { useSession } from '@/lib/session';
import { completeProfile, describeError } from '@/lib/mutations';
import { signOut } from '@/lib/auth-actions';
import { Button, ErrorState, Loading } from '@/components/ui';

/**
 * Profile setup — the page that clears the `onboarding` stage.
 *
 * signUp writes onboarded:false, so without this every new web account lands
 * on a blocking screen with nothing behind it. This is the way out.
 */
export default function ProfileSetup() {
  const { user } = useSession();
  const [displayName, setDisplayName] = useState(user?.displayName ?? '');
  const [title, setTitle] = useState('');
  const [bio, setBio] = useState('');
  const [location, setLocation] = useState('');
  const [skillText, setSkillText] = useState('');
  const [rate, setRate] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (!user) return <Loading />;

  const isFreelancer = user.role === 'freelancer';
  const ready = displayName.trim().length > 1 && bio.trim().length > 10;

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (!user || busy || !ready) return;
    setBusy(true); setError(null);
    try {
      const parsed = Number(rate.replace(/[^0-9.]/g, ''));
      await completeProfile({
        uid: user.uid,
        displayName, title, bio, location,
        skills: skillText.split(',').map((s) => s.trim()).filter(Boolean),
        hourlyRate: Number.isFinite(parsed) && parsed > 0 ? parsed : null,
        role: user.role,
      });
      // No redirect needed: the session snapshot moves the stage on, and the
      // gate routes from there.
    } catch (err) {
      setError(describeError(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="mx-auto max-w-lg px-1">
      <h1 className="font-serif text-2xl font-semibold sm:text-3xl">Finish your profile</h1>
      <p className="mt-1.5 text-sm text-ink-muted">
        {isFreelancer
          ? 'This is what clients see when you bid.'
          : 'This is what freelancers see when you post work.'}
      </p>

      <form onSubmit={submit} className="mt-7 space-y-4">
        <Field label="Display name" value={displayName} onChange={setDisplayName} />
        <Field label={isFreelancer ? 'Headline' : 'Company or role'}
          value={title} onChange={setTitle}
          hint={isFreelancer ? 'e.g. Flutter developer, 6 years' : 'e.g. Nimbus Labs'} />
        <Area label="About" value={bio} onChange={setBio}
          hint="At least a sentence or two — this is the part people actually read." />
        <Field label="Location" value={location} onChange={setLocation}
          hint="City and country." />

        {isFreelancer && (
          <>
            <Field label="Skills" value={skillText} onChange={setSkillText}
              hint="Comma separated." />
            <Field label="Hourly rate" value={rate} onChange={setRate}
              hint="Optional. Leave blank if you quote per project." />
          </>
        )}

        {error && <ErrorState message={error} />}

        <Button type="submit" busy={busy} disabled={!ready} className="w-full">
          Save and continue
        </Button>
        {!ready && (
          <p className="text-center text-xs text-ink-faint">
            A display name and a short description are required.
          </p>
        )}
      </form>

      <button onClick={() => void signOut()}
        className="mx-auto mt-6 block text-xs font-semibold text-ink-faint hover:text-danger">
        Sign out
      </button>
    </div>
  );
}

function Field({ label, value, onChange, hint }: {
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
      <textarea value={value} rows={5} onChange={(e) => onChange(e.target.value)}
        className="mt-1.5 w-full rounded-field border border-border bg-surface px-3.5 py-3 text-base outline-none focus:border-teal sm:text-sm" />
      {hint && <span className="mt-1 block text-xs text-ink-faint">{hint}</span>}
    </label>
  );
}
