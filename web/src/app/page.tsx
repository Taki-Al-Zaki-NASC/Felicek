import { isFirebaseConfigured } from '@/lib/firebase';

/**
 * Server-rendered on purpose. Public job listings being indexable is the
 * whole reason this is Next.js rather than Flutter Web, so the marketing
 * surface has to render without JavaScript.
 */
export default function Home() {
  return (
    <main className="mx-auto max-w-5xl px-5 py-14">
      <div className="flex items-center gap-3">
        <span className="flex h-9 w-9 items-center justify-center rounded-[9px] bg-ink-strong">
          <span className="h-3.5 w-3.5 rounded-full border-[2.5px] border-canvas" />
        </span>
        <span className="font-serif text-2xl font-semibold">Felicek</span>
      </div>

      <section className="mt-8 rounded-[22px] border border-border bg-canvas px-8 py-14 text-center">
        <h1 className="font-serif text-4xl font-semibold leading-tight tracking-tight sm:text-5xl">
          Verified talent.
          <br />
          Zero spam. Fair fees, always.
        </h1>
        <p className="mx-auto mt-4 max-w-lg text-ink-muted">
          Every account is identity-verified and deposit-backed before it can
          post or bid. Escrow-funded milestones, live skill challenges, and a
          flat 1% platform fee shown separately from processing — never blended.
        </p>

        {!isFirebaseConfigured && (
          <p className="mx-auto mt-8 max-w-lg rounded-field border border-amber/30 bg-amber-tint px-4 py-3 text-sm text-ink">
            Firebase is not configured for this build. Copy{' '}
            <code className="rounded bg-backdrop px-1.5 py-0.5 text-xs">.env.example</code>{' '}
            to <code className="rounded bg-backdrop px-1.5 py-0.5 text-xs">.env.local</code>{' '}
            and fill it from the Web app registered in{' '}
            <strong>felicek-9b728</strong>.
          </p>
        )}
      </section>
    </main>
  );
}
