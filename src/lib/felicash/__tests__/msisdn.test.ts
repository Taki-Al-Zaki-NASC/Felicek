import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import {
  formatBd, isValidBd, maskMsisdn, normalizeBd, operatorOf, sameMsisdn,
} from '../msisdn.ts';

test('every shape a buyer types collapses to one canonical number', () => {
  // These are not hypothetical variants — this is what arrives from a form,
  // a paste out of Messenger, and the bKash SMS itself.
  for (const input of [
    '01712345678',
    '+8801712345678',
    '8801712345678',
    '+880 1712-345678',
    '0171 234 5678',
    '1712345678',
    ' 01712345678 ',
  ]) {
    assert.equal(normalizeBd(input), '01712345678', input);
  }
});

test('a number that is not a BD mobile is null, never echoed back', () => {
  // Returning the input unchanged would let "+88 017-1234-5678" become a
  // lookup key that matches nothing, forever.
  assert.equal(normalizeBd('01212345678'), null, 'no such operator prefix');
  assert.equal(normalizeBd('0171234567'), null, 'one digit short');
  assert.equal(normalizeBd('017123456789'), null, 'one digit long');
  assert.equal(normalizeBd('+14155550123'), null, 'not Bangladesh');
  assert.equal(normalizeBd(''), null);
  assert.equal(normalizeBd(null), null);
  assert.equal(normalizeBd('hello'), null);
});

test('every live operator prefix is accepted', () => {
  for (const prefix of ['013', '014', '015', '016', '017', '018', '019']) {
    assert.equal(isValidBd(`${prefix}12345678`), true, prefix);
  }
  assert.equal(operatorOf('01712345678'), 'Grameenphone');
  assert.equal(operatorOf('01812345678'), 'Robi');
  assert.equal(operatorOf('01412345678'), 'Banglalink');
  assert.equal(operatorOf('nonsense'), null);
});

test('two numbers written differently are the same number', () => {
  assert.equal(sameMsisdn('+8801712345678', '01712345678'), true);
  assert.equal(sameMsisdn('01712345678', '01812345678'), false);
});

test('an unparseable number never compares equal to anything', () => {
  // Including to another unparseable one — otherwise two failed parses would
  // settle an order against each other.
  assert.equal(sameMsisdn(null, null), false);
  assert.equal(sameMsisdn('junk', 'junk'), false);
  assert.equal(sameMsisdn('01712345678', null), false);
});

test('masking leaves enough to recognise your own number', () => {
  assert.equal(maskMsisdn('01712345678'), '017****5678');
  assert.equal(maskMsisdn('+8801812345678'), '018****5678');
  assert.equal(maskMsisdn('junk'), '—');
});

test('the readable form is the one people say out loud', () => {
  assert.equal(formatBd('01712345678'), '+880 1712-345678');
  assert.equal(formatBd(null), '—');
});
