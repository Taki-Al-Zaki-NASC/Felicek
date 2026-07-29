'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useSession } from '@/lib/session';
import { Button, ErrorState, Loading, Wordmark } from './ui';
import { signOut } from '@/lib/auth-actions';

/**
 * Routing gate. The web mirror of _SessionGate in app/lib/app/app.dart.
 *
 * An account cannot reach anything useful until identity and the deposit both
 * clear. Enforcing it here is convenience — firestore.rules is what actually
 * stops an unverified account posting or bidding.
 *
 * The pages that *resolve* a stage must not be gated by that stage. /verify
 * clears `verification` and /profile/setup clears `onboarding`; blocking either
 * behind its own stage makes a closed loop, where the screen offers a link and
 * the link renders the same screen. That shipped, and it left no way through
 * the app at all.
 */
const RESOLVES: Record<string, string> = {
  verification: '/verify',
  onboarding: '/profile/setup',
};

export function Gate({ children }: { children: React.ReactNode }) {
  const { stage, user, error } = useSession();
  const path = usePathname();

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

  // Already on the page that clears this stage — let it render.
  if (RESOLVES[stage] === path) return <>{children}</>;

  if (stage === 'onboarding') {
    return (
      <Shell>
        <h1 className="font-serif text-2xl font-semibold">Finish your profile</h1>
        <p className="mt-2 text-sm text-ink-muted">
          A name and a short description of your work, so people know who they
          are dealing with.
        </p>
        <Link href="/profile/setup"
          className="mt-6 inline-block rounded-button bg-ink-strong px-5 py-3 text-sm font-bold text-canvas">
          Continue
        </Link>
        <SignOutLink />
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
        <Link href="/verify"
          className="mt-6 inline-block rounded-button bg-ink-strong px-5 py-3 text-sm font-bold text-canvas">
          Verify {user?.displayName ? `as ${user.displayName}` : 'now'}
        </Link>
        <SignOutLink />
      </Shell>
    );
  }

  return <>{children}</>;
}

/** Always offer a way out of a blocking screen, or it is a trap. */
function SignOutLink() {
  return (
    <button onClick={() => void signOut()}
      className="mt-5 block text-xs font-semibold text-ink-faint hover:text-danger">
      Sign out
    </button>
  );
}

function Shell({ children }: { children: React.ReactNode }) {
  return (
    <main className="mx-auto max-w-md px-5 py-16 sm:py-20">
      <Wordmark />
      <div className="mt-8 sm:mt-10">{children}</div>
    </main>
  );
}
