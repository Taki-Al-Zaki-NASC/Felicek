'use client';

import { use, useEffect, useRef, useState } from 'react';
import {
  collection, doc, limit, onSnapshot, orderBy, query,
} from 'firebase/firestore';
import { firebase } from '@/lib/firebase';
import { useSession } from '@/lib/session';
import type { ChatThread, Message } from '@/lib/schema';
import { describeError, markRead, sendMessage } from '@/lib/mutations';
import { Button, ErrorState, Loading, Pill, relative } from '@/components/ui';

/**
 * A conversation.
 *
 * Messages render straight from the live snapshot, so a sent message appears
 * from the local cache before the round trip completes — the same
 * offline-first behaviour the app relies on.
 */
export default function Thread({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const { user } = useSession();
  const [thread, setThread] = useState<ChatThread | null>(null);
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const bottom = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const fb = firebase();
    if (!fb) { setError('Firebase is not configured.'); setLoading(false); return; }

    const stopThread = onSnapshot(
      doc(fb.db, 'chats', id),
      (snap) => setThread(snap.exists() ? ({ id: snap.id, ...snap.data() } as ChatThread) : null),
      (e) => setError(describeError(e)),
    );

    const stopMessages = onSnapshot(
      query(
        collection(fb.db, 'chats', id, 'messages'),
        orderBy('clientSentAt', 'desc'),
        limit(200),
      ),
      (snap) => {
        setMessages(snap.docs
          .map((d) => ({ id: d.id, ...d.data() }) as Message)
          .reverse());
        setLoading(false);
      },
      (e) => { setError(describeError(e)); setLoading(false); },
    );

    return () => { stopThread(); stopMessages(); };
  }, [id]);

  // One watermark write per visit rather than one per message.
  useEffect(() => {
    if (user && messages.length) void markRead(id, user.uid).catch(() => {});
  }, [id, user, messages.length]);

  useEffect(() => {
    bottom.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.length]);

  if (!user) return <Loading />;

  const otherId = thread?.participants.find((p) => p !== user.uid) ?? '';
  const otherName = thread?.participantNames?.[otherId] ?? 'Felicek user';

  async function send(e: React.FormEvent) {
    e.preventDefault();
    const text = draft.trim();
    if (!text || sending || !user) return;
    setDraft('');           // optimistic: the field clears immediately
    setSending(true);
    try {
      await sendMessage({
        chatId: id, senderId: user.uid, senderName: user.displayName, text,
      });
      setError(null);
    } catch (err) {
      setError(describeError(err));
      setDraft(text);       // put it back rather than losing what they typed
    } finally {
      setSending(false);
    }
  }

  return (
    <div className="mx-auto flex h-[calc(100dvh-13rem)] max-w-3xl flex-col md:h-[calc(100dvh-9rem)]">
      <header className="flex items-baseline justify-between border-b border-border pb-3">
        <div>
          <h1 className="font-serif text-xl font-semibold">{otherName}</h1>
          {thread?.jobTitle && (
            <p className="text-xs text-ink-faint">{thread.jobTitle}</p>
          )}
        </div>
      </header>

      <div className="flex-1 space-y-2 overflow-y-auto py-5">
        {loading ? <Loading />
          : messages.length === 0 ? (
            <p className="py-10 text-center text-sm text-ink-muted">
              No messages yet. Say hello.
            </p>
          ) : messages.map((m) => {
            const mine = m.senderId === user.uid;
            const at = (m.sentAt ?? m.clientSentAt)?.toDate();
            return (
              <div key={m.id} className={`flex ${mine ? 'justify-end' : 'justify-start'}`}>
                <div className={`max-w-[85%] rounded-card sm:max-w-[75%] px-3.5 py-2.5 ${
                  mine ? 'bg-ink-strong text-canvas' : 'border border-border bg-surface'
                }`}>
                  {m.imageBase64 && (
                    <div className="mb-2">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={`data:image/jpeg;base64,${m.imageBase64}`}
                        alt={m.attachmentName ?? 'Shared image'}
                        className="max-h-72 rounded-field" />
                      {m.watermarked && (
                        <span className="mt-1 block">
                          <Pill tone="amber">Preview — clean file on release</Pill>
                        </span>
                      )}
                    </div>
                  )}
                  {m.text && <p className="whitespace-pre-wrap text-sm">{m.text}</p>}
                  {at && (
                    <p className={`mt-1 text-[10px] ${mine ? 'text-canvas/60' : 'text-ink-faint'}`}>
                      {relative(at)}
                    </p>
                  )}
                </div>
              </div>
            );
          })}
        <div ref={bottom} />
      </div>

      {error && <div className="pb-3"><ErrorState message={error} /></div>}

      <form onSubmit={send} className="flex gap-2 border-t border-border pt-3">
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Write a message"
          className="flex-1 rounded-field border border-border bg-surface px-3.5 py-3 text-base outline-none focus:border-teal sm:text-sm"
        />
        <Button type="submit" disabled={!draft.trim()} busy={sending}>Send</Button>
      </form>
    </div>
  );
}
