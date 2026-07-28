import { collection, getDocs, query, where, writeBatch } from 'firebase/firestore';
import { firebase } from './firebase';

/**
 * Hands over the clean originals for a chat.
 *
 * The watermark on a preview is presentation; this is the enforcement. Rules
 * keep `chats/{id}/deliverables/{msgId}` unreadable to the recipient until
 * `released` is true, and only the sender can write there — so the recipient
 * cannot flip it themselves.
 */
export async function releaseDeliverables(chatId: string) {
  const fb = firebase();
  if (!fb) return;
  const pending = await getDocs(query(
    collection(fb.db, 'chats', chatId, 'deliverables'),
    where('released', '==', false),
  ));
  if (pending.empty) return;
  const batch = writeBatch(fb.db);
  for (const d of pending.docs) batch.update(d.ref, { released: true });
  await batch.commit();
}
