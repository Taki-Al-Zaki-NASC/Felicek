import { strict as assert } from 'node:assert';
import { test } from 'node:test';
import {
  channelOf, decodeRef, encodeRef, endedHere, funnel, outcomeOf,
  type FunnelOrder, type FunnelVisit,
} from '../attribution.ts';

test('a page reference survives a round trip', () => {
  const ref = { pageId: '10159876543210', campaign: 'july-launch' };
  const decoded = decodeRef(encodeRef(ref));
  assert.deepEqual(decoded, ref);
});

test('a campaign named in Bangla does not throw', () => {
  // btoa refuses anything above Latin-1, and sellers here name campaigns in
  // Bangla. An exception while building a share link would be absurd.
  const ref = { pageId: '123', campaign: 'জুলাই অফার' };
  assert.deepEqual(decodeRef(encodeRef(ref)), ref);
});

test('a reference without a campaign round trips as null', () => {
  assert.deepEqual(decodeRef(encodeRef({ pageId: '123', campaign: null })),
    { pageId: '123', campaign: null });
});

test('a mangled reference decodes to null instead of a wrong page', () => {
  const good = encodeRef({ pageId: '123', campaign: 'a' });
  assert.equal(decodeRef(good.slice(0, -1)), null, 'truncated checksum');
  assert.equal(decodeRef(`${good}x`), null, 'trailing junk');
  assert.equal(decodeRef('not-a-ref'), null);
  assert.equal(decodeRef(''), null);
  assert.equal(decodeRef(null), null);
  assert.equal(decodeRef(undefined), null);
});

test('fbclid identifies Facebook even with no referrer at all', () => {
  // Facebook's in-app browser frequently strips the referrer. Without this,
  // a seller's best channel reads as "direct" and looks like their worst.
  assert.equal(channelOf({ referrer: null, query: { fbclid: 'IwY2xjaw' } }), 'facebook');
  assert.equal(channelOf({ query: new URLSearchParams('fbclid=abc') }), 'facebook');
  assert.equal(channelOf({ query: { igshid: 'abc' } }), 'instagram');
});

test('the referrer names the app the buyer came from', () => {
  assert.equal(channelOf({ referrer: 'https://m.facebook.com/' }), 'facebook');
  assert.equal(channelOf({ referrer: 'https://l.facebook.com/l.php?u=x' }), 'facebook');
  assert.equal(channelOf({ referrer: 'https://www.messenger.com/t/123' }), 'messenger');
  assert.equal(channelOf({ referrer: 'https://m.me/somepage' }), 'messenger');
  assert.equal(channelOf({ referrer: 'https://www.instagram.com/' }), 'instagram');
  assert.equal(channelOf({ referrer: 'https://news.example.com/' }), 'other');
  assert.equal(channelOf({ referrer: 'not a url' }), 'other');
  assert.equal(channelOf({}), 'direct');
});

test('a visit with no order got nowhere', () => {
  assert.equal(outcomeOf(null), 'opened_only');
  assert.equal(outcomeOf(undefined), 'opened_only');
});

const order = (over: Partial<FunnelOrder> = {}): FunnelOrder => ({
  visitId: 'v1', pageId: 'page1', status: 'delivered', claimedTrxId: 'ABC1234567', ...over,
});

test('an outcome reflects how far the buyer actually got', () => {
  assert.equal(outcomeOf(order({ status: 'delivered' })), 'delivered');
  assert.equal(outcomeOf(order({ status: 'paid' })), 'paid_pending');
  assert.equal(outcomeOf(order({ status: 'review' })), 'in_review');
  assert.equal(outcomeOf(order({ status: 'failed' })), 'failed_verification');
  assert.equal(outcomeOf(order({ status: 'verifying' })), 'failed_verification');
  assert.equal(
    outcomeOf(order({ status: 'awaiting_payment', claimedTrxId: null })),
    'abandoned_at_claim',
  );
});

test('a payment waiting on a human has not ended', () => {
  // Counting a review as a completion is how a dashboard shows a conversion
  // rate the seller's bank balance disagrees with.
  assert.equal(endedHere('delivered'), true);
  assert.equal(endedHere('paid_pending'), true);
  assert.equal(endedHere('in_review'), false);
  assert.equal(endedHere('failed_verification'), false);
  assert.equal(endedHere('opened_only'), false);
});

const visit = (id: string, over: Partial<FunnelVisit> = {}): FunnelVisit => ({
  id, pageId: 'page1', campaign: 'july', channel: 'facebook', at: 0, ...over,
});

test('the funnel shows where people leave', () => {
  const visits = [visit('v1'), visit('v2'), visit('v3'), visit('v4'), visit('v5')];
  const orders = [
    order({ visitId: 'v1', status: 'delivered' }),
    order({ visitId: 'v2', status: 'paid' }),
    order({ visitId: 'v3', status: 'failed' }),
    order({ visitId: 'v4', status: 'awaiting_payment', claimedTrxId: null }),
    // v5 opened the link and did nothing at all.
  ];
  const f = funnel(visits, orders);
  assert.deepEqual(f.stages.map((s) => [s.key, s.count]), [
    ['opened', 5], ['started', 3], ['verified', 2], ['delivered', 1],
  ]);
  assert.equal(f.openedOnly, 1);
  assert.equal(f.stages[1].keptFromPrevious, 3 / 5);
});

test('each page reports its own conversion', () => {
  const f = funnel(
    [visit('v1', { pageId: 'A' }), visit('v2', { pageId: 'A' }), visit('v3', { pageId: 'B' })],
    [order({ visitId: 'v1', status: 'delivered' })],
  );
  const a = f.pages.find((p) => p.pageId === 'A');
  assert.equal(a?.opened, 2);
  assert.equal(a?.completed, 1);
  assert.equal(a?.conversion, 0.5);
  assert.equal(f.pages.find((p) => p.pageId === 'B')?.conversion, 0);
});

test('a visit with no page is reported as direct rather than dropped', () => {
  const f = funnel([visit('v1', { pageId: null, channel: 'direct' })], []);
  assert.equal(f.pages[0].pageId, 'direct');
  assert.equal(f.byChannel[0].channel, 'direct');
});

test('an empty funnel is zeroes, never NaN', () => {
  const f = funnel([], []);
  assert.deepEqual(f.stages.map((s) => s.count), [0, 0, 0, 0]);
  assert.deepEqual(f.stages.map((s) => s.keptFromPrevious), [1, 0, 0, 0]);
  assert.deepEqual(f.pages, []);
});
