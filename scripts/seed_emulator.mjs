/**
 * Seeds the Firebase emulator suite with demo accounts and listings so the
 * app has something to show on first run.
 *
 * Talks to the emulators' REST APIs directly — no Admin SDK dependency, no
 * service-account key, nothing to install beyond Node. Only ever points at
 * 127.0.0.1, and refuses to run against a non-"demo-" project.
 *
 * Invoked by scripts/dev_emulator.sh; standalone use:
 *   firebase emulators:exec --project demo-felicek --only auth,firestore \
 *     "node scripts/seed_emulator.mjs"
 */

const PROJECT = process.env.GCLOUD_PROJECT || 'demo-felicek';
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1:9099';
const FS_HOST = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const PASSWORD = 'felicek123';

if (!PROJECT.startsWith('demo-')) {
  console.error(
    `Refusing to seed project "${PROJECT}" — this script is emulator-only and ` +
      'expects a project id starting with "demo-".',
  );
  process.exit(1);
}

const authBase = `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1`;
const fsBase = `http://${FS_HOST}/v1/projects/${PROJECT}/databases/(default)/documents`;

// ── Firestore REST value encoding ─────────────────────────────────────────

const ts = (d) => ({ timestampValue: d.toISOString() });

function encode(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (typeof value === 'string') return { stringValue: value };
  if (value instanceof Date) return ts(value);
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(encode) } };
  }
  if (typeof value === 'object') {
    if ('timestampValue' in value || 'stringValue' in value) return value;
    return { mapValue: { fields: encodeFields(value) } };
  }
  throw new Error(`Cannot encode ${typeof value}`);
}

const encodeFields = (obj) =>
  Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, encode(v)]));

async function put(path, data) {
  const res = await fetch(`${fsBase}/${path}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json', Authorization: 'Bearer owner' },
    body: JSON.stringify({ fields: encodeFields(data) }),
  });
  if (!res.ok) {
    throw new Error(`Firestore write ${path} failed: ${res.status} ${await res.text()}`);
  }
}

async function createUser(email) {
  const res = await fetch(`${authBase}/accounts:signUp?key=fake-api-key`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: PASSWORD, returnSecureToken: true }),
  });
  const body = await res.json();
  if (!res.ok) {
    // Re-running the seed against a live emulator is fine.
    if (body?.error?.message === 'EMAIL_EXISTS') {
      const sign = await fetch(
        `${authBase}/accounts:signInWithPassword?key=fake-api-key`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email, password: PASSWORD, returnSecureToken: true }),
        },
      );
      return (await sign.json()).localId;
    }
    throw new Error(`Auth signUp failed for ${email}: ${JSON.stringify(body)}`);
  }
  return body.localId;
}

// ── Demo data ─────────────────────────────────────────────────────────────

const now = new Date();
const hoursAgo = (h) => new Date(now.getTime() - h * 3600 * 1000);

/** A fully cleared KYC block — identity on file and a deposit reconciled. */
const clearedKyc = (docType, ref, amountCents, payRef) => ({
  idSubmitted: true,
  idDocumentType: docType,
  idReference: ref,
  birthCertSubmitted: false,
  depositPaid: true,
  depositMethod: 'bKash',
  depositAmountCents: amountCents,
  depositReleased: false,
  paymentRef: payRef,
  stage: 'verified',
  submittedAt: hoursAgo(72),
  verifiedAt: hoursAgo(71),
});

const searchTerms = (name, skills, title) => {
  const out = new Set();
  for (const src of [name, title, ...skills]) {
    for (const w of String(src).toLowerCase().split(/[^a-z0-9+#.]+/)) {
      if (w.length < 2) continue;
      out.add(w);
      for (let i = 2; i <= Math.min(w.length, 8); i++) out.add(w.slice(0, i));
    }
  }
  return [...out].slice(0, 120);
};

const PEOPLE = [
  {
    email: 'sadia@felicek.test',
    displayName: 'Sadia R.',
    role: 'freelancer',
    title: 'Flutter Developer & UI Engineer',
    bio: 'I build polished, production-ready Flutter apps for fintech and logistics startups. 5 years of experience, focused on clean architecture and pixel-perfect UI.',
    location: 'Dhaka, Bangladesh',
    skills: ['Flutter', 'Dart', 'Firebase', 'UI/UX', 'REST APIs'],
    hourlyRate: 28,
    trustScore: 98,
    jobSuccess: 98,
    jobsDone: 14,
    totalEarnedCents: 1840000,
    walletBalanceCents: 124050,
    kyc: clearedKyc('passport', 'BX1234567', 2000, 'seed_pay_sadia'),
    // A 1x1 JPEG — enough to satisfy the mandatory-photo rule for a demo.
    profilePhotoBase64:
      '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAABAAAAAAAAAAAAAAAAAAAACf/EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AKp//2Q==',
  },
  {
    email: 'finnova@felicek.test',
    displayName: 'FinNova Capital',
    role: 'client',
    title: 'Fintech',
    bio: 'We post short, well-scoped freelance projects and pay via pre-funded escrow. Looking for reliable freelancers for ongoing fintech app work.',
    location: 'Remote-first',
    skills: ['Product Design', 'Mobile Dev', 'Content'],
    trustScore: 100,
    jobSuccess: 100,
    jobsDone: 6,
    postingBalanceCents: 5000,
    kyc: clearedKyc('nid', '1990123456789', 5000, 'seed_pay_finnova'),
  },
  {
    email: 'devcraft@felicek.test',
    displayName: 'DevCraft Studio',
    role: 'agency',
    title: 'Backend & Cloud Infrastructure',
    bio: 'A full-service dev agency specializing in backend rebuilds, cloud infrastructure, and long-term SaaS engagements with shared escrow management.',
    location: 'Multi-seat, remote',
    skills: ['Node.js', 'AWS', 'PostgreSQL', 'DevOps'],
    teamSize: '8 engineers',
    trustScore: 96,
    jobSuccess: 96,
    jobsDone: 37,
    postingBalanceCents: 5000,
    kyc: clearedKyc('govid', 'AG-55512', 5000, 'seed_pay_devcraft'),
  },
  {
    email: 'nimbus@felicek.test',
    displayName: 'Nimbus Labs',
    role: 'startup',
    title: 'Pre-Seed',
    bio: 'A verified pre-seed startup offering fast-track, milestone-based roles with equity upside for founding team members.',
    location: 'Remote, Founded 2025',
    skills: ['Flutter', 'Growth', 'Firebase'],
    trustScore: 92,
    jobSuccess: 92,
    jobsDone: 4,
    postingBalanceCents: 5000,
    kyc: clearedKyc('driving', 'DL-99120', 5000, 'seed_pay_nimbus'),
  },
];

const JOBS = [
  {
    key: 'finnova',
    id: 'seed_job_onboarding',
    type: 'freelance',
    typeLabel: 'Freelance',
    title: 'Design a Flutter Onboarding Flow',
    summary: 'Need 5 polished onboarding screens for a fintech app, dark theme, Material 3.',
    scope:
      'Design and hand off 5 onboarding screens for an early-stage fintech app. Deliverables include Figma source files and exported assets, following Material 3 dark theme guidelines.',
    budget: '$450',
    budgetValue: 450,
    skills: ['Flutter', 'UI/UX', 'Figma'],
    milestones: [
      { label: 'Wireframes approved', amount: '$100', released: false },
      { label: 'High-fidelity screens', amount: '$250', released: false },
      { label: 'Final handoff + assets', amount: '$100', released: false },
    ],
    challenge: {
      enabled: true,
      mode: 'writtenPrompt',
      prompt:
        'Recreate this bottom-sheet component spec in Flutter within 4 minutes — tests widget composition speed.',
      durationSeconds: 240,
      questions: [],
    },
    views: 214,
    shortlisted: 3,
    proposalsCount: 0,
    weeklyApplicants: [3, 5, 2, 6, 8, 4, 7],
    createdAt: hoursAgo(2),
  },
  {
    key: 'devcraft',
    id: 'seed_job_backend',
    type: 'agency',
    typeLabel: 'Agency',
    title: 'Full Backend Rebuild for Logistics SaaS',
    summary: 'Multi-month engagement, need a 3-person team for API + infra rebuild.',
    scope:
      'Rebuild the backend of a logistics SaaS product currently on legacy infrastructure. Includes API redesign, database migration, and AWS deployment pipeline.',
    budget: '$12,000',
    budgetValue: 12000,
    skills: ['Node.js', 'PostgreSQL', 'AWS'],
    milestones: [
      { label: 'Architecture proposal', amount: '$2,000', released: false },
      { label: 'Core API migration', amount: '$6,000', released: false },
      { label: 'Go-live + handover', amount: '$4,000', released: false },
    ],
    challenge: { enabled: false, mode: 'writtenPrompt', prompt: '', durationSeconds: 240, questions: [] },
    views: 98,
    shortlisted: 2,
    proposalsCount: 0,
    weeklyApplicants: [1, 2, 1, 2, 3, 2, 1],
    createdAt: hoursAgo(6),
  },
  {
    key: 'nimbus',
    id: 'seed_job_founding',
    type: 'startup',
    typeLabel: 'Startup · Equity',
    title: 'Founding Mobile Engineer (Equity + Micro-milestones)',
    summary: 'Pre-seed startup looking for a founding engineer, part equity + part milestone pay.',
    scope:
      'Join as founding mobile engineer for a verified pre-seed startup. Fast-track hiring: first milestone paid within 5 days of acceptance.',
    budget: '0.5% Equity + $2,000',
    budgetValue: 2000,
    equity: '0.5%',
    skills: ['Flutter', 'Firebase', 'Growth'],
    milestones: [
      { label: 'MVP core screens', amount: '$800', released: false },
      { label: 'Auth + payments', amount: '$700', released: false },
      { label: 'Public beta launch', amount: '$500', released: false },
    ],
    // A quiz listing, so the owner-blind grading path has demo data.
    challenge: {
      enabled: true,
      mode: 'quiz',
      prompt: '',
      durationSeconds: 300,
      questions: [
        {
          prompt: 'Which widget rebuilds only its subtree when a Listenable fires?',
          options: ['setState', 'AnimatedBuilder', 'MediaQuery', 'Scaffold'],
        },
        {
          prompt: 'What does Firestore return for an unresolved serverTimestamp locally?',
          options: ['The device clock', 'null', 'Epoch zero', 'It throws'],
        },
      ],
    },
    // The answer key goes in the owner-only subcollection, never on the job.
    quizAnswerKey: [1, 1],
    views: 156,
    shortlisted: 4,
    proposalsCount: 0,
    weeklyApplicants: [2, 4, 3, 5, 6, 4, 5],
    createdAt: hoursAgo(26),
  },
];

// ── Run ───────────────────────────────────────────────────────────────────

async function main() {
  console.log(`Seeding ${PROJECT} (auth ${AUTH_HOST}, firestore ${FS_HOST})…`);
  const uids = {};

  for (const p of PEOPLE) {
    const uid = await createUser(p.email);
    uids[p.role] = uid;

    const terms = searchTerms(p.displayName, p.skills, p.title);
    const shared = {
      displayName: p.displayName,
      role: p.role,
      title: p.title,
      bio: p.bio,
      location: p.location,
      skills: p.skills,
      hourlyRate: p.hourlyRate ?? null,
      trustScore: p.trustScore,
      jobSuccess: p.jobSuccess,
      jobsDone: p.jobsDone,
      totalEarnedCents: p.totalEarnedCents ?? 0,
      profilePhotoBase64: p.profilePhotoBase64 ?? null,
      searchTerms: terms,
      updatedAt: now,
    };

    await put(`users/${uid}`, {
      ...shared,
      email: p.email,
      teamSize: p.teamSize ?? null,
      kyc: p.kyc,
      notificationPrefs: {
        newMessages: true,
        proposalUpdates: true,
        jobMatches: true,
        payouts: true,
        calls: true,
        productNews: false,
      },
      walletBalanceCents: p.walletBalanceCents ?? 0,
      postingBalanceCents: p.postingBalanceCents ?? 0,
      profileComplete: true,
      onboarded: true,
      blockedUserIds: [],
      createdAt: hoursAgo(96),
    });

    await put(`profiles/${uid}`, {
      ...shared,
      verified: true,
      lastSeenAt: hoursAgo(1),
      createdAt: hoursAgo(96),
    });

    // A reconciled payment intent, so the deposit above has a real receipt
    // behind it — the same shape the gateway webhook writes.
    await put(`paymentIntents/${p.kyc.paymentRef}`, {
      uid,
      purpose: p.role === 'freelancer' ? 'trustDeposit' : 'postingBalance',
      amountCents: p.kyc.depositAmountCents,
      status: 'paid',
      method: 'bKash',
      gatewayTransactionId: `demo_${p.kyc.paymentRef}`,
      metadata: { role: p.role },
      createdAt: hoursAgo(72),
      updatedAt: hoursAgo(71),
    });

    console.log(`  · ${p.email}  (${p.role})  uid=${uid}`);
  }

  for (const j of JOBS) {
    const ownerId = uids[j.key === 'finnova' ? 'client' : j.key === 'devcraft' ? 'agency' : 'startup'];
    const owner = PEOPLE.find((p) => p.email.startsWith(j.key));
    const { key, id, quizAnswerKey, ...job } = j;

    await put(`jobs/${id}`, {
      ...job,
      ownerId,
      ownerName: owner.displayName,
      escrowFunded: true,
      trustScore: owner.trustScore,
      status: 'open',
      ownerStatusLabel: 'Active now',
      avgBid: '—',
      searchTerms: searchTerms(job.title, job.skills, job.summary),
      updatedAt: now,
    });

    if (quizAnswerKey) {
      // Owner-only subcollection — an applicant can never read this.
      await put(`jobs/${id}/challengeKey/answer`, { correctIndexes: quizAnswerKey });
    }
    console.log(`  · job ${id} — ${job.title}`);
  }

  console.log('\nSeed complete. Sign in with any address above / password felicek123.');
}

main().catch((e) => {
  console.error('\nSeeding failed:', e.message);
  process.exit(1);
});
