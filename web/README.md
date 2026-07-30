# Felicek Web

Next.js 15 (App Router) + TypeScript + Tailwind, against the **same** Firebase
project as the Android app (`felicek-9b728`) — same Auth users, same Firestore
documents, same security rules.

```bash
cp .env.example .env.local   # fill from Firebase → Add app → Web
npm install && npm run dev
```

To put it online, see [DEPLOY.md](DEPLOY.md) — Vercel or Cloudflare Pages, both
free tier. The step people miss is **Root Directory: `web`**, since the app is
not at the repository root.

## Why Next.js rather than Flutter Web

Flutter Web would have reused every model, repository and rule already written.
It was not chosen because public job listings need to be indexable, and a
Flutter Web build renders to canvas — invisible to search engines. For a
marketplace, discoverable listings are the product.

The cost of that decision is real: the data layer is re-implemented in
TypeScript. The mitigation is that `firestore.rules` is shared and already
tested (65 tests), so the *security* model cannot drift even though the client
code is duplicated.

## Structural reference

Upwork, per the brief: client/freelancer dashboards, job posting, proposal
workflow, search filters, workspace views. The visual language stays Felicek —
`tailwind.config.ts` carries the exact tokens from
`app/lib/core/theme/tokens.dart`.

## Status

Built and building clean (`npm run typecheck && npm run build && npm test`):

| | |
|---|---|
| Auth | Sign in, sign up with role selection, session gate, 12s stall watchdog |
| Dashboards | Role-aware — client sees listings/escrow, freelancer sees bids/open work |
| Jobs | Browse with search + skill filters, post a job, detail split by role |
| Proposals | Submit, withdraw, shortlist; owner sees score + preview only |
| Messaging | Inbox and live threads, watermark-aware attachments (read-only) |
| KYC | Document + selfie capture with on-device screening, deposit status |
| Escrow | Hire (funds escrow), release milestones, ledger lines, trust-bond unlock |

**Not built yet:** profile setup/editing, sending attachments from the web,
and web deposit checkout (which needs the payment webhook — the client cannot
mark its own payment cleared, by design).

27 tests run in Node with no test framework dependency
(`node --experimental-strip-types`). They copy their assertions from the Dart
suites on purpose — the two stacks compute fees and screen photos
independently, so identical pinned numbers are the only thing stopping them
drifting apart.
