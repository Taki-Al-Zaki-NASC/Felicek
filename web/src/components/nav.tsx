'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { Route } from 'next';
import { useSession } from '@/lib/session';
import { signOut } from '@/lib/auth-actions';
import { Wordmark } from './ui';

/**
 * Top navigation. The four destinations match the app's bottom bar — Home,
 * Proposals, Payment, Profile — so someone moving between phone and desktop
 * finds the same places.
 */
const LINKS: { href: Route; label: string }[] = [
  { href: '/dashboard' as Route, label: 'Home' },
  { href: '/jobs' as Route, label: 'Jobs' },
  { href: '/proposals' as Route, label: 'Proposals' },
  { href: '/messages' as Route, label: 'Messages' },
  { href: '/wallet' as Route, label: 'Payment' },
];

export function Nav() {
  const path = usePathname();
  const { user } = useSession();

  return (
    <header className="sticky top-0 z-20 border-b border-border bg-canvas/90 backdrop-blur">
      <div className="mx-auto flex max-w-6xl items-center gap-6 px-5 py-3">
        <Wordmark href={'/dashboard' as Route} />

        <nav className="flex flex-1 items-center gap-1 overflow-x-auto">
          {LINKS.map((l) => {
            const active = path === l.href || path.startsWith(`${l.href}/`);
            return (
              <Link
                key={l.href}
                href={l.href}
                aria-current={active ? 'page' : undefined}
                className={`whitespace-nowrap rounded-[9px] px-3 py-2 text-sm font-medium transition ${
                  active ? 'bg-teal-tint text-teal' : 'text-ink-muted hover:bg-backdrop'
                }`}
              >
                {l.label}
              </Link>
            );
          })}
        </nav>

        <div className="flex items-center gap-3">
          <Link href={'/profile' as Route}
            className="hidden text-sm font-medium text-ink-muted hover:text-ink sm:block">
            {user?.displayName ?? 'Profile'}
          </Link>
          <button onClick={() => void signOut()}
            className="text-xs font-semibold text-ink-faint hover:text-danger">
            Sign out
          </button>
        </div>
      </div>
    </header>
  );
}
