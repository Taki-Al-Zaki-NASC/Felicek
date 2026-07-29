'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import type { Route } from 'next';
import { useSession } from '@/lib/session';
import { signOut } from '@/lib/auth-actions';
import { Wordmark } from './ui';

/**
 * Navigation.
 *
 * Two layouts, not one squeezed. On a phone the destinations move to a fixed
 * bottom bar — the same five the app's bottom nav has, in the same order — and
 * the header keeps only the wordmark and sign out. Cramming a wordmark, five
 * links and two actions into one row is what made the header unusable on a
 * small screen.
 */
const LINKS: { href: Route; label: string; icon: React.ReactNode }[] = [
  { href: '/dashboard' as Route, label: 'Home', icon: <IconHome /> },
  { href: '/jobs' as Route, label: 'Jobs', icon: <IconBriefcase /> },
  { href: '/messages' as Route, label: 'Messages', icon: <IconChat /> },
  { href: '/verify' as Route, label: 'Account', icon: <IconShield /> },
];

export function Nav() {
  const path = usePathname();
  const { user } = useSession();
  const active = (href: string) => path === href || path.startsWith(`${href}/`);

  return (
    <>
      <header className="sticky top-0 z-20 border-b border-border bg-canvas/90 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center gap-4 px-4 py-3 sm:px-5">
          <Wordmark href={'/dashboard' as Route} />

          {/* Desktop destinations. Hidden on phones, where the bottom bar
              carries them instead. */}
          <nav className="hidden flex-1 items-center gap-1 md:flex">
            {LINKS.map((l) => (
              <Link key={l.href} href={l.href}
                aria-current={active(l.href) ? 'page' : undefined}
                className={`rounded-[9px] px-3 py-2 text-sm font-medium transition ${
                  active(l.href) ? 'bg-teal-tint text-teal' : 'text-ink-muted hover:bg-backdrop'
                }`}>
                {l.label}
              </Link>
            ))}
          </nav>

          <div className="ml-auto flex items-center gap-3 md:ml-0">
            <span className="hidden max-w-[10rem] truncate text-sm font-medium text-ink-muted sm:block">
              {user?.displayName ?? ''}
            </span>
            <button onClick={() => void signOut()}
              className="rounded-[9px] px-2 py-1.5 text-xs font-semibold text-ink-faint hover:bg-backdrop hover:text-danger">
              Sign out
            </button>
          </div>
        </div>
      </header>

      {/* Phone destinations. Fixed, thumb-reachable, and matching the app's
          bottom bar so moving between surfaces is not a relearn. */}
      <nav className="fixed inset-x-0 bottom-0 z-20 grid grid-cols-4 border-t border-border bg-canvas/95 backdrop-blur md:hidden"
        style={{ paddingBottom: 'env(safe-area-inset-bottom)' }}>
        {LINKS.map((l) => (
          <Link key={l.href} href={l.href}
            aria-current={active(l.href) ? 'page' : undefined}
            className={`flex flex-col items-center gap-0.5 py-2.5 text-[10px] font-semibold transition ${
              active(l.href) ? 'text-teal' : 'text-ink-faint'
            }`}>
            {l.icon}
            {l.label}
          </Link>
        ))}
      </nav>
    </>
  );
}

/* Inline SVGs rather than an icon package: four glyphs is not worth 40 KB. */
const S = 'h-5 w-5';
function IconHome() {
  return (
    <svg className={S} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M3 10.5 12 3l9 7.5V20a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z" strokeLinejoin="round" />
    </svg>
  );
}
function IconBriefcase() {
  return (
    <svg className={S} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <rect x="3" y="7" width="18" height="13" rx="2" />
      <path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" strokeLinecap="round" />
    </svg>
  );
}
function IconChat() {
  return (
    <svg className={S} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M21 12a8 8 0 0 1-8 8H4l2-3a8 8 0 1 1 15-5z" strokeLinejoin="round" />
    </svg>
  );
}
function IconShield() {
  return (
    <svg className={S} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 3l7 3v6c0 4.5-3 8-7 9-4-1-7-4.5-7-9V6z" strokeLinejoin="round" />
      <path d="m9 12 2 2 4-4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
