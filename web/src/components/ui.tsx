import Link from 'next/link';
import type { Route } from 'next';

/**
 * The shared vocabulary, mirroring app/lib/core/widgets/*.dart.
 *
 * Kept deliberately small: these are the pieces that appear on almost every
 * screen. Anything used once belongs in the screen that uses it.
 */

export function Card({ children, className = '', as: As = 'div' }: {
  children: React.ReactNode; className?: string; as?: 'div' | 'section' | 'li';
}) {
  return (
    <As className={`rounded-card border border-border bg-surface p-4 ${className}`}>
      {children}
    </As>
  );
}

export function SectionLabel({ children }: { children: React.ReactNode }) {
  return (
    <h2 className="text-[11px] font-semibold uppercase tracking-wider text-ink-faint">
      {children}
    </h2>
  );
}

type PillTone = 'teal' | 'violet' | 'blue' | 'amber' | 'danger' | 'neutral';

const PILL: Record<PillTone, string> = {
  teal: 'bg-teal-tint text-teal',
  violet: 'bg-violet-tint text-violet',
  blue: 'bg-blue-tint text-blue',
  amber: 'bg-amber-tint text-amber',
  danger: 'bg-danger-tint text-danger',
  neutral: 'bg-backdrop text-ink-muted',
};

export function Pill({ children, tone = 'neutral' }: {
  children: React.ReactNode; tone?: PillTone;
}) {
  return (
    <span className={`inline-block rounded-[9px] px-2.5 py-1 text-[11px] font-semibold ${PILL[tone]}`}>
      {children}
    </span>
  );
}

export function Button({
  children, onClick, type = 'button', variant = 'primary', disabled, busy, className = '',
}: {
  children: React.ReactNode;
  onClick?: () => void;
  type?: 'button' | 'submit';
  variant?: 'primary' | 'secondary' | 'danger';
  disabled?: boolean;
  busy?: boolean;
  className?: string;
}) {
  const base = 'min-h-[44px] rounded-button px-5 py-3 text-sm font-bold transition '
    + 'disabled:cursor-not-allowed disabled:opacity-50';
  const tone = {
    primary: 'bg-ink-strong text-canvas hover:opacity-90',
    secondary: 'border border-border-strong bg-surface text-ink hover:bg-backdrop',
    danger: 'bg-danger text-white hover:opacity-90',
  }[variant];
  return (
    <button type={type} onClick={onClick} disabled={disabled || busy}
      className={`${base} ${tone} ${className}`}>
      {busy ? 'Working…' : children}
    </button>
  );
}

/**
 * Never renders a raw error object.
 *
 * The app leaked Firebase's own text to users twice; the fix there was to map
 * codes to sentences, and the same discipline applies here — callers pass a
 * sentence, not an exception.
 */
export function ErrorState({ message, retry }: { message: string; retry?: () => void }) {
  return (
    <div role="alert" className="rounded-card border border-danger/25 bg-danger-tint p-5 text-sm">
      <p className="text-danger">{message}</p>
      {retry && (
        <button onClick={retry} className="mt-3 text-xs font-bold text-teal-deep">
          Try again
        </button>
      )}
    </div>
  );
}

export function EmptyState({ title, message, action }: {
  title: string; message: string; action?: React.ReactNode;
}) {
  return (
    <div className="rounded-card border border-border bg-surface px-6 py-12 text-center">
      <p className="font-serif text-lg font-semibold">{title}</p>
      <p className="mx-auto mt-1.5 max-w-sm text-sm text-ink-muted">{message}</p>
      {action && <div className="mt-5">{action}</div>}
    </div>
  );
}

export function Loading({ label = 'Loading…' }: { label?: string }) {
  return (
    <div className="flex items-center justify-center gap-2 py-16 text-sm text-ink-muted">
      <span className="h-3.5 w-3.5 animate-spin rounded-full border-2 border-teal border-t-transparent" />
      {label}
    </div>
  );
}

export function Stat({ label, value, tone }: {
  label: string; value: string; tone?: 'teal' | 'violet' | 'blue';
}) {
  const colour = tone ? { teal: 'text-teal', violet: 'text-violet', blue: 'text-blue' }[tone] : '';
  return (
    <Card>
      <p className="text-[11px] font-semibold uppercase tracking-wide text-ink-faint">{label}</p>
      <p className={`mt-1 font-serif text-2xl font-semibold ${colour}`}>{value}</p>
    </Card>
  );
}

export function Wordmark({ href = '/' as Route }: { href?: Route }) {
  return (
    <Link href={href} className="flex items-center gap-2.5">
      <span className="flex h-8 w-8 items-center justify-center rounded-[8px] bg-ink-strong">
        <span className="h-3 w-3 rounded-full border-[2.5px] border-canvas" />
      </span>
      <span className="font-serif text-xl font-semibold">Felicek</span>
    </Link>
  );
}

/** Money, from cents. One place, so rounding cannot drift between screens. */
export const money = (cents: number) =>
  `$${(cents / 100).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;

/** Short relative time ("3m", "2h", "4d"). Mirrors Fmt.relative in the app. */
export function relative(d: Date) {
  const mins = Math.round((Date.now() - d.getTime()) / 60000);
  if (mins < 1) return 'now';
  if (mins < 60) return `${mins}m`;
  if (mins < 1440) return `${Math.round(mins / 60)}h`;
  return `${Math.round(mins / 1440)}d`;
}
