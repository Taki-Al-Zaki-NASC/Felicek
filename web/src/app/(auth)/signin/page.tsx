'use client';

import { useState } from 'react';
import Link from 'next/link';
import { RedirectWhenSignedIn } from '@/components/auth-redirect';
import { describeAuthError, signIn } from '@/lib/auth-actions';

export default function SignIn() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    setBusy(true); setError(null);
    try {
      await signIn(email, password);
    } catch (err) {
      setError(describeAuthError(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-md flex-col justify-center px-6">
      <RedirectWhenSignedIn />
      <h1 className="font-serif text-2xl font-semibold sm:text-3xl">Welcome back</h1>
      <p className="mt-2 text-sm text-ink-muted">Sign in to your Felicek account.</p>

      <form onSubmit={submit} className="mt-8 space-y-4">
        <Field label="Email" type="email" value={email} onChange={setEmail} />
        <Field label="Password" type="password" value={password} onChange={setPassword} />

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
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
      </form>

      <p className="mt-6 text-center text-sm text-ink-muted">
        New here?{' '}
        <Link href="/signup" className="font-semibold text-teal-deep">Create an account</Link>
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
