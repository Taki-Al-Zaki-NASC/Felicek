# Firestore rules tests

The product's central promises are enforced in `../firestore.rules`, not in the
Flutter client — a client can be decompiled, patched or replaced, so anything
that only the app checks isn't really enforced at all.

These tests pin those promises against the real Firestore emulator:

1. **No account is usable without identity and a cleared payment.** A client
   cannot publish a job or submit a proposal until both are true.
2. **A client can never mark its own payment as received.** It may create a
   `pending` payment intent and nothing more; `depositPaid` only flips when a
   matching intent already says `paid`, with a matching uid and amount — and
   only a gateway webhook using the Admin SDK can write that.
3. **A job owner can never read a freelancer's full challenge submission.**
   They see the score and a truncated preview; the full text lives in a
   subcollection only its author can read.
4. **An applicant can never read the quiz answer key.**
5. **Only chat participants can read or write a conversation**, nobody can
   forge a message from someone else, and messages cannot be hard-deleted.

## Running

```bash
npm install
npm test
```

`firebase emulators:exec` starts a throwaway Firestore emulator, runs the
tests against it, and shuts it down. No Firebase project, no login, no
network — the `demo-` project id makes the emulator refuse to contact
production.

Java 11+ is required (the Firestore emulator is a JVM binary).

## Adding a test

Follow the existing shape: seed with `seed()` (rules disabled, the way a
backend would write), then act as a specific user via
`testEnv.authenticatedContext('uid')` and wrap the operation in
`assertSucceeds` / `assertFails`.

When you loosen a rule, add the test that proves the thing you *didn't* mean
to loosen is still refused. That negative test is the point.
