import Link from 'next/link';
import type { Route } from 'next';
import { isFirebaseConfigured } from '@/lib/firebase';

/**
 * Marketing landing page.
 *
 * Server-rendered with no client JavaScript, which is the whole reason this
 * app is Next.js rather than Flutter Web: this page has to be indexable.
 *
 * Structure follows Upwork — hero with a role split, category grid, how it
 * works, proof, and a closing call to action — while the visual language stays
 * Felicek's own tokens.
 */
export const metadata = {
  title: 'Felicek — Hire verified freelancers, or find verified work',
  description:
    'Every account is identity-verified and deposit-backed before it can post '
    + 'or bid. Escrow milestones, live skill challenges, and a flat 1% fee '
    + 'shown separately from processing.',
};

const CATEGORIES = [
  { name: 'Development & IT', blurb: 'Mobile, web, backend, DevOps' },
  { name: 'Design & Creative', blurb: 'Product, brand, illustration, motion' },
  { name: 'Writing & Translation', blurb: 'Technical, editorial, localisation' },
  { name: 'Sales & Marketing', blurb: 'Growth, SEO, paid, lifecycle' },
  { name: 'Finance & Accounting', blurb: 'Bookkeeping, modelling, audit prep' },
  { name: 'Admin & Support', blurb: 'Operations, research, assistance' },
];

const STEPS_CLIENT = [
  ['Post what you need', 'Scope, budget and milestones. Takes a few minutes.'],
  ['Compare verified bids', 'Every bidder has identity on file and a deposit behind them.'],
  ['Fund a milestone', 'Money sits in escrow, not with the freelancer.'],
  ['Release when satisfied', 'Approve a milestone and the funds move. Not before.'],
];

const STEPS_FREELANCER = [
  ['Verify once', 'Photo of your ID and a selfie, checked on your device.'],
  ['Bid on real work', 'No unverified clients, so no unpaid invoices to chase.'],
  ['Prove your skill', 'Optional challenges — your submission stays private to you.'],
  ['Get paid per milestone', 'Escrow-funded before you start, released as you deliver.'],
];

export default function Home() {
  return (
    <div className="min-h-screen bg-canvas">
      <header className="border-b border-border">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-4 sm:px-6">
          <span className="flex items-center gap-2.5">
            <span className="flex h-8 w-8 items-center justify-center rounded-[8px] bg-ink-strong">
              <span className="h-3 w-3 rounded-full border-[2.5px] border-canvas" />
            </span>
            <span className="font-serif text-xl font-semibold">Felicek</span>
          </span>
          <nav className="flex items-center gap-2 sm:gap-4">
            <Link href={'/signin' as Route}
              className="rounded-[9px] px-3 py-2 text-sm font-semibold text-ink-muted hover:bg-backdrop">
              Sign in
            </Link>
            <Link href={'/signup' as Route}
              className="rounded-button bg-ink-strong px-4 py-2.5 text-sm font-bold text-canvas hover:opacity-90">
              Join
            </Link>
          </nav>
        </div>
      </header>

      <main>
        {/* Hero */}
        <section className="mx-auto max-w-6xl px-4 pb-14 pt-12 sm:px-6 sm:pb-20 sm:pt-20">
          <div className="grid items-center gap-10 lg:grid-cols-2 lg:gap-14">
            <div>
              <span className="inline-block rounded-[9px] bg-teal-tint px-3 py-1.5 text-xs font-semibold text-teal">
                Every account verified before it can post or bid
              </span>
              <h1 className="mt-5 font-serif text-4xl font-semibold leading-[1.1] tracking-tight sm:text-5xl lg:text-[3.4rem]">
                Hire people who are
                <br className="hidden sm:block" /> actually who they say.
              </h1>
              <p className="mt-5 max-w-xl text-base text-ink-muted sm:text-lg">
                Identity checks and a refundable deposit are required to join —
                on both sides. Work is funded into escrow before it starts, and
                the fee is a flat 1%, itemised separately from card processing.
              </p>

              <div className="mt-8 flex flex-col gap-3 sm:flex-row">
                <Link href={'/signup' as Route}
                  className="rounded-button bg-ink-strong px-6 py-3.5 text-center text-sm font-bold text-canvas hover:opacity-90">
                  Post a job
                </Link>
                <Link href={'/jobs' as Route}
                  className="rounded-button border border-border-strong bg-surface px-6 py-3.5 text-center text-sm font-bold hover:bg-backdrop">
                  Find work
                </Link>
              </div>

              <dl className="mt-10 grid max-w-md grid-cols-3 gap-4 border-t border-border pt-6">
                {[['1%', 'flat platform fee'], ['$0', 'to browse or bid'], ['100%', 'accounts verified']]
                  .map(([big, small]) => (
                    <div key={small}>
                      <dt className="font-serif text-2xl font-semibold text-teal">{big}</dt>
                      <dd className="mt-0.5 text-xs text-ink-muted">{small}</dd>
                    </div>
                  ))}
              </dl>
            </div>

            {/* Two doors, the way Upwork splits its audience. */}
            <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-1">
              <RoleCard
                tone="teal"
                title="I need work done"
                points={[
                  'Bids only from verified freelancers',
                  '$50 posting balance, spent into escrow',
                  'Release milestone by milestone',
                ]}
                cta="Post a job"
              />
              <RoleCard
                tone="violet"
                title="I'm looking for work"
                points={[
                  'No unverified clients to chase',
                  '$20 refundable trust bond to join',
                  'Your challenge submissions stay private',
                ]}
                cta="Find work"
              />
            </div>
          </div>
        </section>

        {/* Categories */}
        <section className="border-y border-border bg-surface py-14 sm:py-18">
          <div className="mx-auto max-w-6xl px-4 sm:px-6">
            <h2 className="font-serif text-2xl font-semibold sm:text-3xl">
              Browse by category
            </h2>
            <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
              {CATEGORIES.map((c) => (
                <Link key={c.name} href={'/jobs' as Route}
                  className="rounded-card border border-border p-4 transition hover:border-teal hover:bg-teal-tint/40">
                  <p className="font-semibold">{c.name}</p>
                  <p className="mt-1 text-sm text-ink-muted">{c.blurb}</p>
                </Link>
              ))}
            </div>
          </div>
        </section>

        {/* How it works, per side */}
        <section className="mx-auto max-w-6xl px-4 py-14 sm:px-6 sm:py-20">
          <h2 className="font-serif text-2xl font-semibold sm:text-3xl">How it works</h2>
          <div className="mt-8 grid gap-10 lg:grid-cols-2 lg:gap-14">
            <Steps title="If you're hiring" steps={STEPS_CLIENT} tone="teal" />
            <Steps title="If you're freelancing" steps={STEPS_FREELANCER} tone="violet" />
          </div>
        </section>

        {/* The three claims worth making, because they are enforced rather
            than promised — each maps to a rule in firestore.rules. */}
        <section className="border-y border-border bg-surface py-14 sm:py-20">
          <div className="mx-auto max-w-6xl px-4 sm:px-6">
            <h2 className="font-serif text-2xl font-semibold sm:text-3xl">
              Enforced, not promised
            </h2>
            <p className="mt-2 max-w-2xl text-sm text-ink-muted">
              These are security rules on the database, not settings in an admin
              panel. The app cannot bypass them, and neither can we.
            </p>
            <div className="mt-7 grid gap-4 md:grid-cols-3">
              <Claim
                title="No unverified account can act"
                body="Posting and bidding require identity on file and a cleared
                      deposit. An account cannot mark its own payment as paid."
              />
              <Claim
                title="Your work stays yours"
                body="Challenge submissions are readable only by their author.
                      A client sees a score and a short preview — never your
                      full code or design."
              />
              <Claim
                title="Deliverables are held until paid"
                body="Files arrive watermarked. The clean original is unreadable
                      to the client until the milestone is released."
              />
            </div>
          </div>
        </section>

        {/* Close */}
        <section className="mx-auto max-w-3xl px-4 py-16 text-center sm:px-6 sm:py-24">
          <h2 className="font-serif text-3xl font-semibold sm:text-4xl">
            Start with a verified account.
          </h2>
          <p className="mx-auto mt-3 max-w-lg text-ink-muted">
            Browsing and bidding cost nothing. The deposit is yours — refundable
            for freelancers, spendable into escrow for clients.
          </p>
          <Link href={'/signup' as Route}
            className="mt-8 inline-block rounded-button bg-ink-strong px-7 py-4 text-sm font-bold text-canvas hover:opacity-90">
            Create your account
          </Link>

          {!isFirebaseConfigured && (
            <p className="mx-auto mt-10 max-w-lg rounded-field border border-amber/30 bg-amber-tint px-4 py-3 text-left text-sm">
              This deployment has no Firebase configuration, so sign-in will not
              work. Copy <code className="rounded bg-backdrop px-1.5 py-0.5 text-xs">.env.example</code>{' '}
              to <code className="rounded bg-backdrop px-1.5 py-0.5 text-xs">.env.local</code>{' '}
              and fill it from the Web app registered in <strong>felicek-9b728</strong>.
            </p>
          )}
        </section>
      </main>

      <footer className="border-t border-border py-8">
        <div className="mx-auto flex max-w-6xl flex-col items-center gap-3 px-4 text-sm text-ink-faint sm:flex-row sm:justify-between sm:px-6">
          <span>© Felicek</span>
          <span className="flex gap-5">
            <Link href={'/jobs' as Route} className="hover:text-ink">Find work</Link>
            <Link href={'/signin' as Route} className="hover:text-ink">Sign in</Link>
          </span>
        </div>
      </footer>
    </div>
  );
}

function RoleCard({ tone, title, points, cta }: {
  tone: 'teal' | 'violet'; title: string; points: string[]; cta: string;
}) {
  const accent = tone === 'teal'
    ? 'border-teal/30 bg-teal-tint'
    : 'border-violet/30 bg-violet-tint';
  const text = tone === 'teal' ? 'text-teal' : 'text-violet';
  return (
    <div className={`rounded-card-lg border p-5 ${accent}`}>
      <h3 className="font-serif text-lg font-semibold">{title}</h3>
      <ul className="mt-3 space-y-2">
        {points.map((p) => (
          <li key={p} className="flex gap-2 text-sm">
            <span className={`mt-0.5 font-bold ${text}`} aria-hidden>✓</span>
            <span>{p}</span>
          </li>
        ))}
      </ul>
      <Link href={'/signup' as Route}
        className={`mt-4 inline-block text-sm font-bold ${text}`}>
        {cta} →
      </Link>
    </div>
  );
}

function Steps({ title, steps, tone }: {
  title: string; steps: string[][]; tone: 'teal' | 'violet';
}) {
  const chip = tone === 'teal' ? 'bg-teal text-white' : 'bg-violet text-white';
  return (
    <div>
      <h3 className="font-serif text-lg font-semibold">{title}</h3>
      <ol className="mt-4 space-y-4">
        {steps.map(([label, detail], i) => (
          <li key={label} className="flex gap-3.5">
            <span className={`flex h-7 w-7 shrink-0 items-center justify-center rounded-full text-xs font-bold ${chip}`}>
              {i + 1}
            </span>
            <span>
              <span className="block font-semibold">{label}</span>
              <span className="mt-0.5 block text-sm text-ink-muted">{detail}</span>
            </span>
          </li>
        ))}
      </ol>
    </div>
  );
}

function Claim({ title, body }: { title: string; body: string }) {
  return (
    <div className="rounded-card border border-border p-5">
      <h3 className="font-semibold">{title}</h3>
      <p className="mt-1.5 text-sm text-ink-muted">{body}</p>
    </div>
  );
}
