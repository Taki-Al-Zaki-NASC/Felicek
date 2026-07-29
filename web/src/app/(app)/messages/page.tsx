'use client';

import Link from 'next/link';
import type { Route } from 'next';
import { useSession } from '@/lib/session';
import { myChats, useCollection } from '@/lib/queries';
import type { ChatThread } from '@/lib/schema';
import { Card, EmptyState, ErrorState, Loading, Pill, relative } from '@/components/ui';

export default function Inbox() {
  const { user } = useSession();
  const { data, loading, error } = useCollection<ChatThread>(
    'chats', user ? myChats(user.uid) : [], [user?.uid]);

  if (!user || loading) return <Loading />;
  // Never render "no conversations" off a failed read — that reads as though
  // the threads were deleted.
  if (error) return <ErrorState message={error} />;

  return (
    <>
      <h1 className="font-serif text-2xl font-semibold sm:text-3xl">Messages</h1>
      <p className="mt-1 text-sm text-ink-muted">
        Conversations with clients and freelancers you are working with.
      </p>

      <div className="mt-6 space-y-2">
        {data.length === 0 ? (
          <EmptyState title="No conversations yet"
            message="Messaging opens when you are hired, or when a client reaches out about a proposal." />
        ) : data.map((t) => {
          const otherId = t.participants.find((p) => p !== user.uid) ?? '';
          const name = t.participantNames?.[otherId] ?? 'Felicek user';
          const unread = isUnread(t, user.uid);
          return (
            <Link key={t.id} href={`/messages/${t.id}` as Route} className="block">
              <Card className="transition hover:border-border-strong">
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-semibold">{name}</span>
                      {unread && <Pill tone="teal">New</Pill>}
                    </div>
                    {t.jobTitle && (
                      <p className="mt-0.5 text-xs text-ink-faint">{t.jobTitle}</p>
                    )}
                    <p className="mt-1 line-clamp-1 text-sm text-ink-muted">
                      {t.lastMessage ?? 'No messages yet'}
                    </p>
                  </div>
                  {t.lastMessageAt && (
                    <span className="whitespace-nowrap text-xs text-ink-faint">
                      {relative(t.lastMessageAt.toDate())}
                    </span>
                  )}
                </div>
              </Card>
            </Link>
          );
        })}
      </div>
    </>
  );
}

function isUnread(t: ChatThread, uid: string) {
  const last = t.lastMessageAt?.toDate();
  const seen = t.readUpTo?.[uid]?.toDate();
  if (!last) return false;
  return !seen || seen < last;
}
