'use client';

import Link from 'next/link';
import { useSession } from '@/lib/session';
import { Button, ErrorState, Loading, Wordmark } from './ui';
import { signOut } from '@/lib/auth-actions';

/**
 * Routing gate. The web mirror of _SessionGate in app/lib/app/app.dart.
 *
 * Same rule as the app: an account cannot reach anything useful until identity
 * and the deposit both clear. Enforcing it here is convenience — firestore.rules
 * is what actually stops an unverified account posting or bidding, and that is
 * tested separately.
 */
export function Gate({ children }: { children: React.ReactNode }) {
  const { stage, user, error } = useSession();

  if (stage === 'booting') return <Loading label="Signing you in…" />;

  if (stage === 'stalled') {
    return (
      <Shell>
        <ErrorState message={error ?? 'Your account could not be loaded.'} />
        <div className="mt-4">
          <Button variant="secondary" onClick={() => void signOut()}>Sign out</Button>
        </div>
      </Shell>
    );
  }

  if (stage === 'signedOut') {
    return (
      <Shell>
        <p className="text-sm text-ink-muted">You need to be signed in to see this.</p>
        <Link href="/signin" className="mt-4 inline-block font-semibold text-teal-deep">
          Sign in
        </Link>
      </Shell>
    );
  }

  if (stage === 'onboarding') {
    return (
      <Shell>
        <h1 className="font-serif text-2xl font-semibold">Finish your profile</h1>
        <p className="mt-2 text-sm text-ink-muted">
          Add your details before browsing work.
        </p>
        <p className="mt-5 text-xs text-ink-faint">
          Profile setup is not built on the web yet — finish it in the Android
          app and this page will let you through.
        </p>
      </Shell>
    );
  }

  if (stage === 'verification') {
    return (
      <Shell>
        <h1 className="font-serif text-2xl font-semibold">Verification required</h1>
        <p className="mt-2 text-sm text-ink-muted">
          Every Felicek account needs identity on file and a cleared deposit
          before it can post or bid. There is no skip.
        </p>
        <p className="mt-5 text-xs text-ink-faint">
          {user?.displayName ? `Signed in as ${user.displayName}. ` : ''}
          Verification is not built on the web yet — complete it in the Android
          app and this page will let you through.
        </p>
      </Shell>
    );
  }

  return <>{children}</>;
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="mx-auto max-w-md px-6 py-20">
      <Wordmark />
      <div className="mt-10">{children}</div>
    </main>
  );
}
