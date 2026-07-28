import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import { milestoneCents } from '../schema.ts';
import type { Job, Proposal } from '../schema.ts';

/**
 * Mirrors EngagementRepository.milestoneCents. The web shows a fee breakdown
 * for the amount it is about to release, so if this parse disagrees with the
 * Dart one, a client is shown one figure and charged another.
 */
const job = (milestones: { label: string; amount: string }[]): Job => ({
  id: 'j1', ownerId: 'o', ownerName: 'Client', type: 'freelance',
  typeLabel: 'Freelance', title: 'T', milestones,
});
const proposal = (bidCents: number): Proposal => ({
  id: 'p1', jobId: 'j1', freelancerId: 'f', freelancerName: 'F',
  status: 'accepted', bidAmountCents: bidCents,
});

test('a dollar amount in the label is used', () => {
  const j = job([{ label: 'A', amount: '$450' }]);
  assert.equal(milestoneCents(j.milestones![0], j, proposal(100000)), 45000);
});

test('thousands separators and decimals parse', () => {
  const j = job([{ label: 'A', amount: '$1,234.56' }]);
  assert.equal(milestoneCents(j.milestones![0], j, proposal(0)), 123456);
});

test('an unparseable amount splits the bid evenly', () => {
  const j = job([
    { label: 'A', amount: 'TBD' },
    { label: 'B', amount: 'TBD' },
  ]);
  assert.equal(milestoneCents(j.milestones![0], j, proposal(90000)), 45000);
});

test('a zero or negative amount falls back rather than paying nothing', () => {
  const j = job([{ label: 'A', amount: '$0' }]);
  assert.equal(milestoneCents(j.milestones![0], j, proposal(50000)), 50000);
});

test('no milestones does not divide by zero', () => {
  const j = job([]);
  assert.equal(milestoneCents({ label: 'X', amount: '' }, j, proposal(7000)), 7000);
});
