/**
 * Firestore security rules tests for Felicek.
 *
 * These exist because the product's central promises are enforced in
 * `firestore.rules`, not in the Flutter client — a client can always be
 * bypassed. Each test below pins one of those promises:
 *
 *   1. No account is usable without identity + a cleared payment.
 *   2. A client can never mark its own payment as received.
 *   3. A job owner can never read a freelancer's full challenge submission.
 *   4. An applicant can never read the quiz answer key.
 *   5. Only chat participants can read or write a conversation.
 *
 * Run: npm test   (from firebase/tests)
 */

import { readFileSync } from 'node:fs';
import { after, before, describe, it } from 'node:test';
import assert from 'node:assert/strict';

import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  addDoc,
  collection,
  serverTimestamp,
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = 'demo-felicek';

/** A fully verified freelancer, as `users/{uid}` would look after KYC. */
const verifiedFreelancer = (uid) => ({
  email: `${uid}@example.com`,
  displayName: 'Verified Freelancer',
  role: 'freelancer',
  profilePhotoBase64: 'ZmFrZS1qcGVn',
  kyc: {
    idSubmitted: true,
    idDocumentType: 'passport',
    idReference: 'X1234567',
    depositPaid: true,
    depositAmountCents: 2000,
    paymentRef: 'pay_ok',
    stage: 'verified',
  },
});

const verifiedClient = (uid) => ({
  email: `${uid}@example.com`,
  displayName: 'Verified Client',
  role: 'client',
  kyc: {
    idSubmitted: true,
    idDocumentType: 'nid',
    idReference: '1990123456789',
    depositPaid: true,
    depositAmountCents: 5000,
    paymentRef: 'pay_ok_client',
    stage: 'verified',
  },
});

/** Identity submitted but no payment cleared — the "not yet" state. */
const unpaidClient = (uid) => ({
  email: `${uid}@example.com`,
  displayName: 'Unpaid Client',
  role: 'client',
  kyc: {
    idSubmitted: true,
    depositPaid: false,
    stage: 'idSubmitted',
  },
});

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv?.cleanup();
});

/** Seeds documents with rules disabled, the way a backend would. */
async function seed(fn) {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await fn(ctx.firestore());
  });
}

// ───────────────────────────────────────────────────────────────────────────

describe('users/{uid} — private account record', () => {
  it('the owner can read their own record', async () => {
    await seed((db) => setDoc(doc(db, 'users/alice'), verifiedFreelancer('alice')));
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(getDoc(doc(alice, 'users/alice')));
  });

  it("nobody else can read it — it holds the email, ID reference and balance", async () => {
    await seed((db) => setDoc(doc(db, 'users/alice'), verifiedFreelancer('alice')));
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(getDoc(doc(bob, 'users/alice')));
  });

  it('an unauthenticated reader is refused', async () => {
    await seed((db) => setDoc(doc(db, 'users/alice'), verifiedFreelancer('alice')));
    const anon = testEnv.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(anon, 'users/alice')));
  });

  it('a new account cannot be created already marked as paid', async () => {
    const carol = testEnv.authenticatedContext('carol', { email: 'carol@example.com' })
      .firestore();
    await assertFails(
      setDoc(doc(carol, 'users/carol'), {
        email: 'carol@example.com',
        displayName: 'Carol',
        role: 'freelancer',
        kyc: { idSubmitted: true, depositPaid: true, stage: 'verified' },
      }),
    );
  });
});

describe('paymentIntents — the money guarantee', () => {
  it('a user may create a pending intent for themselves', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      setDoc(doc(alice, 'paymentIntents/pi_1'), {
        uid: 'alice',
        purpose: 'trustDeposit',
        amountCents: 2000,
        status: 'pending',
      }),
    );
  });

  it('a user may NOT create an intent already marked paid', async () => {
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      setDoc(doc(alice, 'paymentIntents/pi_2'), {
        uid: 'alice',
        purpose: 'trustDeposit',
        amountCents: 2000,
        status: 'paid',
      }),
    );
  });

  it('a user may NOT flip their own pending intent to paid', async () => {
    await seed((db) =>
      setDoc(doc(db, 'paymentIntents/pi_3'), {
        uid: 'alice',
        purpose: 'trustDeposit',
        amountCents: 2000,
        status: 'pending',
      }),
    );
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(updateDoc(doc(alice, 'paymentIntents/pi_3'), { status: 'paid' }));
  });

  it("a user may not create an intent in someone else's name", async () => {
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      setDoc(doc(bob, 'paymentIntents/pi_4'), {
        uid: 'alice',
        purpose: 'trustDeposit',
        amountCents: 2000,
        status: 'pending',
      }),
    );
  });

  it('a user cannot read another user\'s intent', async () => {
    await seed((db) =>
      setDoc(doc(db, 'paymentIntents/pi_5'), {
        uid: 'alice',
        purpose: 'trustDeposit',
        amountCents: 2000,
        status: 'pending',
      }),
    );
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(getDoc(doc(bob, 'paymentIntents/pi_5')));
  });
});

describe('users.kyc.depositPaid — cannot be self-granted', () => {
  it('refuses to flip depositPaid with no matching paid intent', async () => {
    await seed((db) =>
      setDoc(doc(db, 'users/dave'), {
        email: 'dave@example.com',
        displayName: 'Dave',
        role: 'client',
        kyc: { idSubmitted: true, depositPaid: false, stage: 'idSubmitted' },
      }),
    );
    const dave = testEnv.authenticatedContext('dave', { email: 'dave@example.com' })
      .firestore();
    await assertFails(
      setDoc(
        doc(dave, 'users/dave'),
        {
          email: 'dave@example.com',
          displayName: 'Dave',
          role: 'client',
          kyc: {
            idSubmitted: true,
            depositPaid: true,
            depositAmountCents: 5000,
            paymentRef: 'made_up_ref',
            stage: 'verified',
          },
        },
      ),
    );
  });

  it('allows it once a matching intent is genuinely paid', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users/erin'), {
        email: 'erin@example.com',
        displayName: 'Erin',
        role: 'client',
        kyc: { idSubmitted: true, depositPaid: false, stage: 'idSubmitted' },
      });
      // Written by the gateway webhook via the Admin SDK, which bypasses rules.
      await setDoc(doc(db, 'paymentIntents/pi_erin'), {
        uid: 'erin',
        purpose: 'postingBalance',
        amountCents: 5000,
        status: 'paid',
      });
    });
    const erin = testEnv.authenticatedContext('erin', { email: 'erin@example.com' })
      .firestore();
    await assertSucceeds(
      setDoc(doc(erin, 'users/erin'), {
        email: 'erin@example.com',
        displayName: 'Erin',
        role: 'client',
        kyc: {
          idSubmitted: true,
          depositPaid: true,
          depositAmountCents: 5000,
          paymentRef: 'pi_erin',
          stage: 'verified',
        },
      }),
    );
  });

  it('refuses an amount that does not match the paid intent', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users/frank'), {
        email: 'frank@example.com',
        displayName: 'Frank',
        role: 'client',
        kyc: { idSubmitted: true, depositPaid: false, stage: 'idSubmitted' },
      });
      await setDoc(doc(db, 'paymentIntents/pi_frank'), {
        uid: 'frank',
        purpose: 'postingBalance',
        amountCents: 100, // paid $1, claiming $50
        status: 'paid',
      });
    });
    const frank = testEnv.authenticatedContext('frank', { email: 'frank@example.com' })
      .firestore();
    await assertFails(
      setDoc(doc(frank, 'users/frank'), {
        email: 'frank@example.com',
        displayName: 'Frank',
        role: 'client',
        kyc: {
          idSubmitted: true,
          depositPaid: true,
          depositAmountCents: 5000,
          paymentRef: 'pi_frank',
          stage: 'verified',
        },
      }),
    );
  });

  it("refuses to borrow someone else's paid intent", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users/grace'), {
        email: 'grace@example.com',
        displayName: 'Grace',
        role: 'client',
        kyc: { idSubmitted: true, depositPaid: false, stage: 'idSubmitted' },
      });
      await setDoc(doc(db, 'paymentIntents/pi_someone_else'), {
        uid: 'erin',
        purpose: 'postingBalance',
        amountCents: 5000,
        status: 'paid',
      });
    });
    const grace = testEnv.authenticatedContext('grace', { email: 'grace@example.com' })
      .firestore();
    await assertFails(
      setDoc(doc(grace, 'users/grace'), {
        email: 'grace@example.com',
        displayName: 'Grace',
        role: 'client',
        kyc: {
          idSubmitted: true,
          depositPaid: true,
          depositAmountCents: 5000,
          paymentRef: 'pi_someone_else',
          stage: 'verified',
        },
      }),
    );
  });
});

describe('jobs — posting requires a verified account', () => {
  it('a verified client can publish', async () => {
    await seed((db) => setDoc(doc(db, 'users/vclient'), verifiedClient('vclient')));
    const client = testEnv.authenticatedContext('vclient').firestore();
    await assertSucceeds(
      setDoc(doc(client, 'jobs/job_ok'), {
        ownerId: 'vclient',
        ownerName: 'Verified Client',
        type: 'freelance',
        typeLabel: 'Freelance',
        title: 'Design an onboarding flow',
        status: 'open',
      }),
    );
  });

  it('an identity-only, unpaid client cannot publish', async () => {
    await seed((db) => setDoc(doc(db, 'users/uclient'), unpaidClient('uclient')));
    const client = testEnv.authenticatedContext('uclient').firestore();
    await assertFails(
      setDoc(doc(client, 'jobs/job_blocked'), {
        ownerId: 'uclient',
        ownerName: 'Unpaid Client',
        type: 'freelance',
        typeLabel: 'Freelance',
        title: 'Design an onboarding flow',
        status: 'open',
      }),
    );
  });

  it('a verified freelancer with no photo cannot publish', async () => {
    await seed((db) =>
      setDoc(doc(db, 'users/nophoto'), {
        ...verifiedFreelancer('nophoto'),
        profilePhotoBase64: '',
      }),
    );
    const f = testEnv.authenticatedContext('nophoto').firestore();
    await assertFails(
      setDoc(doc(f, 'jobs/job_nophoto'), {
        ownerId: 'nophoto',
        ownerName: 'No Photo',
        type: 'freelance',
        typeLabel: 'Freelance',
        title: 'Anything at all',
        status: 'open',
      }),
    );
  });

  it('listings are world-readable', async () => {
    await seed((db) =>
      setDoc(doc(db, 'jobs/job_public'), {
        ownerId: 'vclient',
        title: 'Public listing',
        status: 'open',
      }),
    );
    const anyone = testEnv.authenticatedContext('random').firestore();
    await assertSucceeds(getDoc(doc(anyone, 'jobs/job_public')));
  });

  it('a non-owner cannot edit a listing', async () => {
    await seed((db) =>
      setDoc(doc(db, 'jobs/job_owned'), {
        ownerId: 'vclient',
        title: 'Owned listing',
        status: 'open',
      }),
    );
    const other = testEnv.authenticatedContext('intruder').firestore();
    await assertFails(updateDoc(doc(other, 'jobs/job_owned'), { title: 'Hijacked' }));
  });

  it('a non-owner may still bump the view counter', async () => {
    await seed((db) =>
      setDoc(doc(db, 'jobs/job_views'), {
        ownerId: 'vclient',
        title: 'Counted listing',
        status: 'open',
        views: 0,
      }),
    );
    const viewer = testEnv.authenticatedContext('viewer').firestore();
    await assertSucceeds(updateDoc(doc(viewer, 'jobs/job_views'), { views: 1 }));
  });
});

describe('challenge privacy — the owner-blind guarantee', () => {
  it('the job owner CANNOT read the quiz answer key of… wait, they own it', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'jobs/job_quiz'), { ownerId: 'vclient', status: 'open' });
      await setDoc(doc(db, 'jobs/job_quiz/challengeKey/answer'), {
        correctIndexes: [0, 2, 1],
      });
    });
    const owner = testEnv.authenticatedContext('vclient').firestore();
    await assertSucceeds(getDoc(doc(owner, 'jobs/job_quiz/challengeKey/answer')));
  });

  it('an applicant CANNOT read the quiz answer key', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'jobs/job_quiz2'), { ownerId: 'vclient', status: 'open' });
      await setDoc(doc(db, 'jobs/job_quiz2/challengeKey/answer'), {
        correctIndexes: [0, 2, 1],
      });
    });
    const applicant = testEnv.authenticatedContext('alice').firestore();
    await assertFails(getDoc(doc(applicant, 'jobs/job_quiz2/challengeKey/answer')));
  });

  it('the freelancer can read their own full submission', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'proposals/job_x__alice'), {
        jobId: 'job_x',
        jobOwnerId: 'vclient',
        freelancerId: 'alice',
      });
      await setDoc(doc(db, 'proposals/job_x__alice/submission/full'), {
        fullAnswer: 'const secret = "my entire solution";',
      });
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(getDoc(doc(alice, 'proposals/job_x__alice/submission/full')));
  });

  it('the JOB OWNER cannot read the full submission', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'proposals/job_y__alice'), {
        jobId: 'job_y',
        jobOwnerId: 'vclient',
        freelancerId: 'alice',
      });
      await setDoc(doc(db, 'proposals/job_y__alice/submission/full'), {
        fullAnswer: 'const secret = "my entire solution";',
      });
    });
    const owner = testEnv.authenticatedContext('vclient').firestore();
    await assertFails(getDoc(doc(owner, 'proposals/job_y__alice/submission/full')));
  });

  it('a rival applicant cannot read someone else\'s submission', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'proposals/job_z__alice'), {
        jobId: 'job_z',
        jobOwnerId: 'vclient',
        freelancerId: 'alice',
      });
      await setDoc(doc(db, 'proposals/job_z__alice/submission/full'), {
        fullAnswer: 'secret',
      });
    });
    const rival = testEnv.authenticatedContext('bob').firestore();
    await assertFails(getDoc(doc(rival, 'proposals/job_z__alice/submission/full')));
  });

  it('the owner CAN read the proposal summary (score and preview)', async () => {
    await seed((db) =>
      setDoc(doc(db, 'proposals/job_w__alice'), {
        jobId: 'job_w',
        jobOwnerId: 'vclient',
        freelancerId: 'alice',
        challenge: { score: 80, answerPreview: 'Implemented the bottom sheet…' },
      }),
    );
    const owner = testEnv.authenticatedContext('vclient').firestore();
    await assertSucceeds(getDoc(doc(owner, 'proposals/job_w__alice')));
  });
});

describe('proposals — bidding requires a verified account', () => {
  it('a verified freelancer can bid', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users/alice'), verifiedFreelancer('alice'));
      await setDoc(doc(db, 'jobs/job_bid'), { ownerId: 'vclient', status: 'open' });
    });
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      setDoc(doc(alice, 'proposals/job_bid__alice'), {
        jobId: 'job_bid',
        jobOwnerId: 'vclient',
        freelancerId: 'alice',
        bidAmountCents: 43000,
        status: 'submitted',
      }),
    );
  });

  it('an unverified freelancer cannot bid', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users/hank'), {
        email: 'hank@example.com',
        displayName: 'Hank',
        role: 'freelancer',
        kyc: { idSubmitted: true, depositPaid: false, stage: 'idSubmitted' },
      });
      await setDoc(doc(db, 'jobs/job_bid2'), { ownerId: 'vclient', status: 'open' });
    });
    const hank = testEnv.authenticatedContext('hank').firestore();
    await assertFails(
      setDoc(doc(hank, 'proposals/job_bid2__hank'), {
        jobId: 'job_bid2',
        jobOwnerId: 'vclient',
        freelancerId: 'hank',
        status: 'submitted',
      }),
    );
  });

  it('a third party can read neither side of a proposal', async () => {
    await seed((db) =>
      setDoc(doc(db, 'proposals/job_p__alice'), {
        jobId: 'job_p',
        jobOwnerId: 'vclient',
        freelancerId: 'alice',
      }),
    );
    const nosy = testEnv.authenticatedContext('nosy').firestore();
    await assertFails(getDoc(doc(nosy, 'proposals/job_p__alice')));
  });
});

describe('chats and messages', () => {
  const chatId = 'alice__bob';

  async function seedChat() {
    await seed((db) =>
      setDoc(doc(db, `chats/${chatId}`), {
        participantIds: ['alice', 'bob'],
        participants: {
          alice: { displayName: 'Alice' },
          bob: { displayName: 'Bob' },
        },
      }),
    );
  }

  it('a participant can read the thread', async () => {
    await seedChat();
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(getDoc(doc(alice, `chats/${chatId}`)));
  });

  it('an outsider cannot read the thread', async () => {
    await seedChat();
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertFails(getDoc(doc(mallory, `chats/${chatId}`)));
  });

  it('an outsider cannot read messages', async () => {
    await seedChat();
    await seed((db) =>
      setDoc(doc(db, `chats/${chatId}/messages/m1`), {
        senderId: 'alice',
        text: 'private',
        clientSentAt: Timestamp.now(),
      }),
    );
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertFails(getDoc(doc(mallory, `chats/${chatId}/messages/m1`)));
  });

  it('a participant can send a message', async () => {
    await seedChat();
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      addDoc(collection(alice, `chats/${chatId}/messages`), {
        senderId: 'alice',
        senderName: 'Alice',
        text: 'hello',
        type: 'text',
        sentAt: serverTimestamp(),
        clientSentAt: Timestamp.now(),
      }),
    );
  });

  it('a participant cannot forge a message from the other person', async () => {
    await seedChat();
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      addDoc(collection(alice, `chats/${chatId}/messages`), {
        senderId: 'bob',
        senderName: 'Bob',
        text: 'I agree to anything',
        type: 'text',
        sentAt: serverTimestamp(),
        clientSentAt: Timestamp.now(),
      }),
    );
  });

  it('a wildly skewed client clock is refused', async () => {
    await seedChat();
    const alice = testEnv.authenticatedContext('alice').firestore();
    const lastYear = Timestamp.fromDate(new Date(Date.now() - 365 * 24 * 3600 * 1000));
    await assertFails(
      addDoc(collection(alice, `chats/${chatId}/messages`), {
        senderId: 'alice',
        senderName: 'Alice',
        text: 'backdated to the top of the thread',
        type: 'text',
        sentAt: serverTimestamp(),
        clientSentAt: lastYear,
      }),
    );
  });

  it("a participant cannot edit the other person's message", async () => {
    await seedChat();
    await seed((db) =>
      setDoc(doc(db, `chats/${chatId}/messages/m2`), {
        senderId: 'bob',
        text: 'original',
        clientSentAt: Timestamp.now(),
      }),
    );
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      updateDoc(doc(alice, `chats/${chatId}/messages/m2`), { text: 'tampered' }),
    );
  });

  it('a participant CAN respond to the other person\'s offer', async () => {
    await seedChat();
    await seed((db) =>
      setDoc(doc(db, `chats/${chatId}/messages/m3`), {
        senderId: 'bob',
        type: 'offer',
        text: 'Milestone 1',
        offer: { amountCents: 45000, milestone: 'Milestone 1', accepted: false, declined: false },
        clientSentAt: Timestamp.now(),
      }),
    );
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      updateDoc(doc(alice, `chats/${chatId}/messages/m3`), {
        offer: { amountCents: 45000, milestone: 'Milestone 1', accepted: true, declined: false },
      }),
    );
  });

  it('messages can never be hard-deleted', async () => {
    await seedChat();
    await seed((db) =>
      setDoc(doc(db, `chats/${chatId}/messages/m4`), {
        senderId: 'alice',
        text: 'on the record',
        clientSentAt: Timestamp.now(),
      }),
    );
    const alice = testEnv.authenticatedContext('alice').firestore();
    const { deleteDoc } = await import('firebase/firestore');
    await assertFails(deleteDoc(doc(alice, `chats/${chatId}/messages/m4`)));
  });
});

describe('profiles — the public mirror', () => {
  it('anyone signed in can read a public profile', async () => {
    await seed((db) =>
      setDoc(doc(db, 'profiles/alice'), { displayName: 'Alice', role: 'freelancer', verified: true }),
    );
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(getDoc(doc(bob, 'profiles/alice')));
  });

  it("nobody can edit someone else's profile", async () => {
    await seed((db) =>
      setDoc(doc(db, 'profiles/alice'), { displayName: 'Alice', verified: false }),
    );
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(updateDoc(doc(bob, 'profiles/alice'), { displayName: 'Not Alice' }));
  });

  it('a user cannot self-award the verified badge', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users/ivan'), {
        email: 'ivan@example.com',
        role: 'client',
        kyc: { idSubmitted: false, depositPaid: false, stage: 'none' },
      });
      await setDoc(doc(db, 'profiles/ivan'), { displayName: 'Ivan', verified: false });
    });
    const ivan = testEnv.authenticatedContext('ivan').firestore();
    await assertFails(updateDoc(doc(ivan, 'profiles/ivan'), { verified: true }));
  });

  it('a genuinely verified user can set the badge', async () => {
    await seed(async (db) => {
      await setDoc(doc(db, 'users/vclient2'), verifiedClient('vclient2'));
      await setDoc(doc(db, 'profiles/vclient2'), { displayName: 'VC2', verified: false });
    });
    const vc = testEnv.authenticatedContext('vclient2').firestore();
    await assertSucceeds(updateDoc(doc(vc, 'profiles/vclient2'), { verified: true }));
  });
});

describe('calls — WebRTC signaling', () => {
  it('the callee can read the call document', async () => {
    await seed((db) =>
      setDoc(doc(db, 'calls/c1'), { callerId: 'alice', calleeId: 'bob', status: 'ringing' }),
    );
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(getDoc(doc(bob, 'calls/c1')));
  });

  it('an uninvolved user cannot read the call document', async () => {
    await seed((db) =>
      setDoc(doc(db, 'calls/c2'), { callerId: 'alice', calleeId: 'bob', status: 'ringing' }),
    );
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertFails(getDoc(doc(mallory, 'calls/c2')));
  });

  it('a user cannot place a call in someone else\'s name', async () => {
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertFails(
      setDoc(doc(mallory, 'calls/c3'), {
        callerId: 'alice',
        calleeId: 'bob',
        status: 'ringing',
      }),
    );
  });
});

describe('notifications', () => {
  it('another user may drop a correctly-shaped notification', async () => {
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertSucceeds(
      addDoc(collection(bob, 'users/alice/notifications'), {
        kind: 'message',
        title: 'Bob',
        body: 'Hello there',
        read: false,
        chatId: 'alice__bob',
        jobId: null,
        proposalId: null,
        actorId: 'bob',
        actorName: 'Bob',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('a notification cannot arrive pre-read', async () => {
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      addDoc(collection(bob, 'users/alice/notifications'), {
        kind: 'message',
        title: 'Bob',
        body: 'Sneaky',
        read: true,
        chatId: null,
        jobId: null,
        proposalId: null,
        actorId: 'bob',
        actorName: 'Bob',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it('extra fields are rejected', async () => {
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(
      addDoc(collection(bob, 'users/alice/notifications'), {
        kind: 'message',
        title: 'Bob',
        body: 'Hi',
        read: false,
        injectedPayload: 'nope',
        createdAt: serverTimestamp(),
      }),
    );
  });

  it("nobody can read another user's notification feed", async () => {
    await seed((db) =>
      setDoc(doc(db, 'users/alice/notifications/n1'), {
        kind: 'message',
        title: 'X',
        body: 'Y',
        read: false,
      }),
    );
    const bob = testEnv.authenticatedContext('bob').firestore();
    await assertFails(getDoc(doc(bob, 'users/alice/notifications/n1')));
  });
});

describe('reviews', () => {
  async function seedEngagement() {
    await seed(async (db) => {
      await setDoc(doc(db, 'jobs/job_done'), {
        ownerId: 'vclient',
        title: 'Completed engagement',
        status: 'closed',
        hiredProposalId: 'job_done__alice',
        hiredFreelancerId: 'alice',
      });
    });
  }

  it('the client can review the freelancer they hired', async () => {
    await seedEngagement();
    const client = testEnv.authenticatedContext('vclient').firestore();
    await assertSucceeds(
      setDoc(doc(client, 'reviews/job_done__vclient'), {
        jobId: 'job_done',
        jobTitle: 'Completed engagement',
        authorId: 'vclient',
        authorName: 'Verified Client',
        subjectId: 'alice',
        rating: 5,
        comment: 'Great work.',
        amountCents: 43000,
      }),
    );
  });

  it('the freelancer can review the client back', async () => {
    await seedEngagement();
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertSucceeds(
      setDoc(doc(alice, 'reviews/job_done__alice'), {
        jobId: 'job_done',
        jobTitle: 'Completed engagement',
        authorId: 'alice',
        authorName: 'Alice',
        subjectId: 'vclient',
        rating: 4,
        comment: 'Clear brief, paid on time.',
        amountCents: 43000,
      }),
    );
  });

  it('an uninvolved user cannot review the engagement', async () => {
    await seedEngagement();
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertFails(
      setDoc(doc(mallory, 'reviews/job_done__mallory'), {
        jobId: 'job_done',
        jobTitle: 'Completed engagement',
        authorId: 'mallory',
        authorName: 'Mallory',
        subjectId: 'alice',
        rating: 1,
        comment: 'Never worked with them.',
        amountCents: 0,
      }),
    );
  });

  it('nobody can review themselves', async () => {
    await seedEngagement();
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      setDoc(doc(alice, 'reviews/job_done__alice'), {
        jobId: 'job_done',
        jobTitle: 'Completed engagement',
        authorId: 'alice',
        authorName: 'Alice',
        subjectId: 'alice',
        rating: 5,
        comment: 'I am great.',
        amountCents: 0,
      }),
    );
  });

  it('a review id must match its author — no writing as someone else', async () => {
    await seedEngagement();
    const alice = testEnv.authenticatedContext('alice').firestore();
    await assertFails(
      setDoc(doc(alice, 'reviews/job_done__vclient'), {
        jobId: 'job_done',
        jobTitle: 'Completed engagement',
        authorId: 'alice',
        authorName: 'Alice',
        subjectId: 'vclient',
        rating: 5,
        amountCents: 0,
      }),
    );
  });

  it('an out-of-range rating is refused', async () => {
    await seedEngagement();
    const client = testEnv.authenticatedContext('vclient').firestore();
    await assertFails(
      setDoc(doc(client, 'reviews/job_done__vclient'), {
        jobId: 'job_done',
        jobTitle: 'Completed engagement',
        authorId: 'vclient',
        authorName: 'Verified Client',
        subjectId: 'alice',
        rating: 99,
        amountCents: 0,
      }),
    );
  });

  it('reviews are publicly readable', async () => {
    await seed((db) =>
      setDoc(doc(db, 'reviews/job_done__vclient'), {
        jobId: 'job_done',
        authorId: 'vclient',
        subjectId: 'alice',
        rating: 5,
      }),
    );
    const anyone = testEnv.authenticatedContext('random').firestore();
    await assertSucceeds(getDoc(doc(anyone, 'reviews/job_done__vclient')));
  });

  it('reviews cannot be deleted', async () => {
    await seed((db) =>
      setDoc(doc(db, 'reviews/job_done__vclient'), {
        jobId: 'job_done',
        authorId: 'vclient',
        subjectId: 'alice',
        rating: 5,
      }),
    );
    const client = testEnv.authenticatedContext('vclient').firestore();
    const { deleteDoc } = await import('firebase/firestore');
    await assertFails(deleteDoc(doc(client, 'reviews/job_done__vclient')));
  });
});

describe('agency team seats', () => {
  it('the agency can create a seat', async () => {
    const agency = testEnv.authenticatedContext('devcraft').firestore();
    await assertSucceeds(
      setDoc(doc(agency, 'users/devcraft/seats/rafiq@example.com'), {
        email: 'rafiq@example.com',
        role: 'Backend Lead',
        accepted: false,
      }),
    );
  });

  it('a stranger cannot create a seat on someone else\'s agency', async () => {
    const mallory = testEnv.authenticatedContext('mallory').firestore();
    await assertFails(
      setDoc(doc(mallory, 'users/devcraft/seats/mallory@example.com'), {
        email: 'mallory@example.com',
        role: 'CTO',
        accepted: true,
      }),
    );
  });

  it('the invited person can claim their own seat', async () => {
    await seed((db) =>
      setDoc(doc(db, 'users/devcraft/seats/rafiq@example.com'), {
        email: 'rafiq@example.com',
        role: 'Backend Lead',
        accepted: false,
      }),
    );
    const rafiq = testEnv
      .authenticatedContext('rafiq', { email: 'rafiq@example.com' })
      .firestore();
    await assertSucceeds(
      updateDoc(doc(rafiq, 'users/devcraft/seats/rafiq@example.com'), {
        memberUid: 'rafiq',
        displayName: 'Rafiq H.',
        accepted: true,
      }),
    );
  });

  it("someone else's seat cannot be claimed", async () => {
    await seed((db) =>
      setDoc(doc(db, 'users/devcraft/seats/rafiq@example.com'), {
        email: 'rafiq@example.com',
        role: 'Backend Lead',
        accepted: false,
      }),
    );
    const mallory = testEnv
      .authenticatedContext('mallory', { email: 'mallory@example.com' })
      .firestore();
    await assertFails(
      updateDoc(doc(mallory, 'users/devcraft/seats/rafiq@example.com'), {
        memberUid: 'mallory',
        displayName: 'Mallory',
        accepted: true,
      }),
    );
  });

  it('the invited person cannot rewrite the seat role', async () => {
    await seed((db) =>
      setDoc(doc(db, 'users/devcraft/seats/rafiq@example.com'), {
        email: 'rafiq@example.com',
        role: 'Backend Lead',
        accepted: false,
      }),
    );
    const rafiq = testEnv
      .authenticatedContext('rafiq', { email: 'rafiq@example.com' })
      .firestore();
    await assertFails(
      updateDoc(doc(rafiq, 'users/devcraft/seats/rafiq@example.com'), {
        role: 'Owner',
        accepted: true,
        memberUid: 'rafiq',
      }),
    );
  });
});
