import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import {
  DEFAULT_EMAIL_BODY, MAX_ATTEMPTS, TEMPLATE_TOKENS, freshSteps, fulfil, markStep,
  nextStep, poolAfterIssue, renderTemplate, retryDelayMs, statusFor,
} from '../delivery.ts';
import type { Product, StepName, StepRecord } from '../schema.ts';

const NOW = 1_800_000_000_000;

const done = (steps: Record<StepName, StepRecord>, ...names: StepName[]) =>
  names.reduce((s, n) => markStep(s, n, 'done', NOW), steps);

test('the pipeline runs in order', () => {
  let steps = freshSteps();
  assert.equal(nextStep(steps), 'verify');
  steps = markStep(steps, 'verify', 'done', NOW);
  assert.equal(nextStep(steps), 'invoice');
  steps = markStep(steps, 'invoice', 'done', NOW);
  assert.equal(nextStep(steps), 'fulfil');
  steps = markStep(steps, 'fulfil', 'done', NOW);
  assert.equal(nextStep(steps), 'email');
  steps = markStep(steps, 'email', 'done', NOW);
  assert.equal(nextStep(steps), null);
});

test('a completed step is never the next step, so a retry cannot repeat it', () => {
  // This is the whole reason for a machine rather than a line of awaits: a
  // failed email must not re-issue the licence key that already went out.
  const steps = done(freshSteps(), 'verify', 'invoice', 'fulfil');
  assert.equal(nextStep(steps), 'email');
  assert.equal(nextStep(markStep(steps, 'email', 'failed', NOW)), 'email',
    'a failure inside the budget is retried');
});

test('a skipped step is treated as finished', () => {
  const steps = markStep(done(freshSteps(), 'verify', 'invoice'), 'fulfil', 'skipped', NOW);
  assert.equal(nextStep(steps), 'email');
});

test('a step out of attempts stops the pipeline instead of hammering it', () => {
  // A wrong SMTP password should surface to the seller, not become ten
  // thousand queued sends.
  let steps = done(freshSteps(), 'verify', 'invoice', 'fulfil');
  for (let i = 0; i < MAX_ATTEMPTS; i++) steps = markStep(steps, 'email', 'failed', NOW, 'nope');
  assert.equal(steps.email.attempts, MAX_ATTEMPTS);
  assert.equal(nextStep(steps), null);
});

test('attempts count tries, not failures', () => {
  const steps = markStep(markStep(freshSteps(), 'verify', 'failed', NOW), 'verify', 'done', NOW);
  assert.equal(steps.verify.attempts, 2);
  assert.equal(steps.verify.state, 'done');
});

test('marking a step does not mutate the record it was given', () => {
  const before = freshSteps();
  markStep(before, 'verify', 'done', NOW);
  assert.equal(before.verify.state, 'pending');
});

test('paid and delivered are different facts', () => {
  // An order whose email bounced is paid and not delivered. Collapsing the two
  // hides exactly the orders that need a human.
  const paidSteps = done(freshSteps(), 'verify', 'invoice', 'fulfil');
  assert.equal(statusFor(paidSteps, true), 'paid');
  assert.equal(statusFor(done(paidSteps, 'email'), true), 'delivered');
  assert.equal(statusFor(markStep(paidSteps, 'email', 'failed', NOW), true), 'paid');
});

test('an unpaid order is verifying until verification actually fails', () => {
  assert.equal(statusFor(freshSteps(), false), 'verifying');
  assert.equal(statusFor(markStep(freshSteps(), 'verify', 'failed', NOW), false), 'failed');
});

test('backoff climbs and then stops climbing', () => {
  assert.equal(retryDelayMs(0), 30_000);
  assert.equal(retryDelayMs(1), 120_000);
  assert.equal(retryDelayMs(4), 7_200_000);
  assert.equal(retryDelayMs(99), 7_200_000, 'capped, not unbounded');
  assert.equal(retryDelayMs(-1), 30_000);
});

/* ------------------------------------------------------------- templates */

test('placeholders are filled from the supplied values', () => {
  const r = renderTemplate('Hi {{buyer_name}}, your {{product}} is ready.',
    { buyer_name: 'Rafi', product: 'Flutter Course' });
  assert.equal(r.text, 'Hi Rafi, your Flutter Course is ready.');
  assert.deepEqual(r.missing, []);
});

test('a mistyped placeholder is reported, not posted to the buyer', () => {
  // The buyer's copy reads a little short; the seller sees the typo in the
  // editor. Nobody receives an email containing a literal {{dowload_link}}.
  const r = renderTemplate('Here: {{dowload_link}}', { download_link: 'https://x' });
  assert.equal(r.text, 'Here: ');
  assert.deepEqual(r.missing, ['dowload_link']);
});

test('placeholder matching tolerates spacing and case, and repeats once in missing', () => {
  const r = renderTemplate('{{ Buyer_Name }} {{buyer_name}} {{nope}} {{nope}}',
    { buyer_name: 'Rafi' });
  assert.equal(r.text, 'Rafi Rafi  ');
  assert.deepEqual(r.missing, ['nope']);
});

test('the shipped template only uses tokens that exist', () => {
  const used = [...DEFAULT_EMAIL_BODY.matchAll(/\{\{\s*([a-z0-9_]+)\s*\}\}/gi)]
    .map((m) => m[1].toLowerCase());
  assert.ok(used.length > 0);
  for (const token of used) {
    assert.ok(TEMPLATE_TOKENS.includes(token), `${token} is not a real token`);
  }
});

/* ------------------------------------------------------------ fulfilment */

const product = (over: Partial<Product['delivery']>): Pick<Product, 'delivery'> =>
  ({ delivery: { kind: 'link', payload: '', keys: [], keysIssued: 0, ...over } });

test('a link product hands over its link', () => {
  const f = fulfil(product({ kind: 'link', payload: 'https://drive.example/course' }));
  assert.equal(f.ok, true);
  if (!f.ok) return;
  assert.equal(f.payload, 'https://drive.example/course');
  assert.equal(f.manual, false);
});

test('a link product with nothing configured fails loudly rather than sending an empty email', () => {
  const f = fulfil(product({ kind: 'link', payload: '' }));
  assert.equal(f.ok, false);
  if (f.ok) return;
  assert.equal(f.reason, 'not_configured');
});

test('a key product issues one key and reports what is left', () => {
  const f = fulfil(product({ kind: 'key', keys: ['K-1', 'K-2', 'K-3'] }));
  assert.equal(f.ok, true);
  if (!f.ok) return;
  assert.equal(f.payload, 'K-1');
  assert.equal(f.keysLeft, 2);
});

test('running out of keys is a stated reason, not a blank delivery', () => {
  const f = fulfil(product({ kind: 'key', keys: [] }));
  assert.equal(f.ok, false);
  if (f.ok) return;
  assert.equal(f.reason, 'out_of_stock');
  assert.match(f.message, /run out/);
});

test('fulfilment computes the next pool rather than mutating one', () => {
  // A key popped outside a transaction is a key handed to two buyers the first
  // time two people pay at once.
  const keys = ['K-1', 'K-2'];
  fulfil(product({ kind: 'key', keys }));
  assert.deepEqual(keys, ['K-1', 'K-2']);
  assert.deepEqual(poolAfterIssue(keys), ['K-2']);
  assert.deepEqual(poolAfterIssue([]), []);
});

test('a manual product succeeds with nothing to hand over', () => {
  const f = fulfil(product({ kind: 'manual' }));
  assert.equal(f.ok, true);
  if (!f.ok) return;
  assert.equal(f.manual, true);
});
