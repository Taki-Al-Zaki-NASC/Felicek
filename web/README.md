# Felicek Web

Next.js 15 (App Router) + TypeScript + Tailwind, against the **same** Firebase
project as the Android app (`felicek-9b728`) — same Auth users, same Firestore
documents, same security rules.

```bash
cp .env.example .env.local   # fill from Firebase → Add app → Web
npm install && npm run dev
```

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

Scaffold only. Built so far: project config, design tokens, a Firebase module
that degrades to a readable message instead of a blank page, and a landing
page. Not built: auth, dashboards, jobs, proposals, messaging, KYC, escrow.
