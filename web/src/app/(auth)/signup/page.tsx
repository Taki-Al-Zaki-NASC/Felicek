'use client';

import { useState } from 'react';
import Link from 'next/link';
import { RedirectWhenSignedIn } from '@/components/auth-redirect';
import { describeAuthError, signUp } from '@/lib/auth-actions';
import { DEPOSIT_CENTS, type UserRoleKey } from '@/lib/types';

const ROLES: { key: UserRoleKey; label: string; blurb: string }[] = [
  { key: 'freelancer', label: 'Freelancer', blurb: 'Bid on work. Refundable $20 trust bond.' },
  { key: 'client', label: 'Client', blurb: 'Post jobs. $50 posting balance — your money, spent into escrow.' },
  { key: 'agency', label: 'Agency', blurb: 'Hire as a team. $50 posting balance.' },
  { key: 'startup', label: 'Startup', blurb: 'Build a team. $50 posting balance.' },
];

export default function SignUp() {
  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [role, setRole] = useState<UserRoleKey>('freelancer');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    if (password.length < 8) {
      setError('Choose a password of at least 8 characters.');
      return;
    }
    setBusy(true); setError(null);
    try {
      await signUp(email, password, name, role);
    } catch (err) {
      setError(describeAuthError(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-6 py-12">
      <RedirectWhenSignedIn />
      <h1 className="font-serif text-2xl font-semibold sm:text-3xl">Create your account</h1>
      <p className="mt-2 text-sm text-ink-muted">
        Identity verification and a cleared deposit are required before an
        account can post or bid — there is no skip.
      </p>

      <form onSubmit={submit} className="mt-8 space-y-4">
        <Field label="Name" type="text" value={name} onChange={setName} />
        <Field label="Email" type="email" value={email} onChange={setEmail} />
        <Field label="Password" type="password" value={password} onChange={setPassword} />

        <fieldset>
          <legend className="text-xs font-semibold text-ink-muted">Account type</legend>
          <div className="mt-2 grid gap-2">
            {ROLES.map((r) => (
              <button
                type="button"
                key={r.key}
                onClick={() => setRole(r.key)}
                className={`rounded-card border px-4 py-3 text-left transition ${
                  role === r.key
                    ? 'border-teal bg-teal-tint'
                    : 'border-border bg-surface hover:border-border-strong'
                }`}
              >
                <div className="flex items-baseline justify-between gap-3">
                  <span className="text-sm font-semibold">{r.label}</span>
                  <span className="text-xs text-ink-muted">
                    ${(DEPOSIT_CENTS[r.key] / 100).toFixed(0)}
                  </span>
                </div>
                <p className="mt-0.5 text-xs text-ink-muted">{r.blurb}</p>
              </button>
            ))}
          </div>
        </fieldset>

        {error && (
          <p role="alert" className="rounded-field bg-danger-tint px-3 py-2 text-sm text-danger">
            {error}
          </p>
        )}

        <button
          type="submit"
          disabled={busy || !email || !password}
          className="w-full rounded-button bg-ink-strong px-5 py-3.5 text-sm font-bold text-canvas disabled:opacity-50"
        >
          {busy ? 'Creating…' : 'Create account'}
        </button>
      </form>

      <p className="mt-6 text-center text-sm text-ink-muted">
        Already have an account?{' '}
        <Link href="/signin" className="font-semibold text-teal-deep">Sign in</Link>
      </p>
    </main>
  );
}

function Field({ label, type, value, onChange }: {
  label: string; type: string; value: string; onChange: (v: string) => void;
}) {
  return (
    <label className="block">
      <span className="text-xs font-semibold text-ink-muted">{label}</span>
      <input
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="mt-1.5 w-full rounded-field border border-border bg-surface px-3.5 py-3 text-base outline-none focus:border-teal sm:text-sm"
      />
    </label>
  );
}
