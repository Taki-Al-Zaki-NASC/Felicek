import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import {
  checkReference, inspectGreyscale, MIN_SHARPNESS,
} from '../identity-check.ts';

/**
 * Mirrors app/test/identity_check_test.dart. Both surfaces screen the same
 * photo, so a threshold that drifts means it passes on one and fails on the
 * other — which looks like a bug to whoever hits it.
 */

/** Random noise reads as sharp; a flat field reads as blurred. */
function noise(w: number, h: number): Uint8ClampedArray {
  const g = new Uint8ClampedArray(w * h);
  let seed = 7;
  for (let i = 0; i < g.length; i++) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    g[i] = 40 + (seed % 180);
  }
  return g;
}

function flat(w: number, h: number, value: number): Uint8ClampedArray {
  return new Uint8ClampedArray(w * h).fill(value);
}

test('a sharp, well-exposed, large enough photo passes', () => {
  const r = inspectGreyscale(noise(200, 150), 200, 150, 1000, 700);
  assert.equal(r.passed, true, r.reasons.join(' | '));
});

test('a thumbnail is rejected for size', () => {
  const r = inspectGreyscale(noise(200, 150), 200, 150, 320, 200);
  assert.equal(r.passed, false);
  assert.match(r.reasons.join(), /too small/);
});

test('a flat frame is rejected as blurred', () => {
  const r = inspectGreyscale(flat(200, 150, 128), 200, 150, 1000, 700);
  assert.equal(r.passed, false);
  assert.ok(r.sharpness < MIN_SHARPNESS);
});

test('a dark frame says it is dark, not that it is blurred', () => {
  const r = inspectGreyscale(flat(200, 150, 8), 200, 150, 1000, 700);
  assert.match(r.reasons.join(), /dark/);
});

test('a blown-out frame says it is too bright', () => {
  const r = inspectGreyscale(flat(200, 150, 252), 200, 150, 1000, 700);
  assert.match(r.reasons.join(), /bright/);
});

test('the selfie wording differs from the document wording', () => {
  const blurred = flat(200, 150, 128);
  assert.match(inspectGreyscale(blurred, 200, 150, 1000, 700, true).reasons.join(), /Hold still/);
  assert.match(inspectGreyscale(blurred, 200, 150, 1000, 700, false).reasons.join(), /flat surface/);
});

test('a plausible passport number is accepted', () => {
  assert.equal(checkReference('passport', 'A1234567'), null);
});

test('spaces and dashes are tolerated rather than punished', () => {
  assert.equal(checkReference('nationalId', '1234 5678 9012'), null);
});

test('empty is refused', () => {
  assert.match(checkReference('passport', '   ')!, /Enter/);
});

test('a repeated single character is refused', () => {
  assert.match(checkReference('nationalId', '0000000000')!, /does not look like/);
});

test('punctuation is refused with a specific reason', () => {
  assert.match(checkReference('passport', 'A123!@#4')!, /letters and digits/);
});

test('an over-long passport number is refused', () => {
  assert.match(checkReference('passport', 'A12345678901')!, /6–9/);
});
