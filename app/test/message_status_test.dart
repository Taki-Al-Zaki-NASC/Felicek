import 'package:felicek/data/models/message.dart';
import 'package:flutter_test/flutter_test.dart';

/// The receipt state machine is the part of messaging most likely to regress
/// silently — a wrong tick is invisible in a screenshot but obvious to a user.
void main() {
  const String me = 'user_me';
  const String them = 'user_them';

  final DateTime sent = DateTime(2026, 5, 1, 12, 0, 0);

  Message mine({
    DateTime? sentAt,
    bool pendingWrite = false,
    bool localFailure = false,
  }) =>
      Message(
        id: 'm1',
        senderId: me,
        senderName: 'Me',
        text: 'hello',
        sentAt: sentAt,
        clientSentAt: sent,
        pendingWrite: pendingWrite,
        localFailure: localFailure,
      );

  group('MessageStatus', () {
    test('a message from the other person is never pending on my side', () {
      final Message incoming = Message(
        id: 'm2',
        senderId: them,
        senderName: 'Them',
        text: 'hi',
        sentAt: sent,
        clientSentAt: sent,
      );
      expect(
        incoming.statusFor(
          myUid: me,
          otherDeliveredUpTo: null,
          otherReadUpTo: null,
        ),
        MessageStatus.read,
      );
    });

    test('queued offline writes read as sending', () {
      expect(
        mine(pendingWrite: true).statusFor(
          myUid: me,
          otherDeliveredUpTo: null,
          otherReadUpTo: null,
        ),
        MessageStatus.sending,
      );
    });

    test('a null server timestamp still reads as sending', () {
      expect(
        mine().statusFor(
            myUid: me, otherDeliveredUpTo: null, otherReadUpTo: null),
        MessageStatus.sending,
      );
    });

    test('a rejected write reads as failed and outranks everything else', () {
      expect(
        mine(sentAt: sent, localFailure: true).statusFor(
          myUid: me,
          otherDeliveredUpTo: sent,
          otherReadUpTo: sent,
        ),
        MessageStatus.failed,
      );
    });

    test('acknowledged by the server but no watermark yet reads as sent', () {
      expect(
        mine(sentAt: sent).statusFor(
          myUid: me,
          otherDeliveredUpTo: null,
          otherReadUpTo: null,
        ),
        MessageStatus.sent,
      );
    });

    test('a delivery watermark at or past sentAt reads as delivered', () {
      expect(
        mine(sentAt: sent).statusFor(
          myUid: me,
          otherDeliveredUpTo: sent,
          otherReadUpTo: null,
        ),
        MessageStatus.delivered,
      );
    });

    test('a stale delivery watermark does not count', () {
      expect(
        mine(sentAt: sent).statusFor(
          myUid: me,
          otherDeliveredUpTo: sent.subtract(const Duration(seconds: 1)),
          otherReadUpTo: null,
        ),
        MessageStatus.sent,
      );
    });

    test('a read watermark outranks a delivery watermark', () {
      expect(
        mine(sentAt: sent).statusFor(
          myUid: me,
          otherDeliveredUpTo: sent,
          otherReadUpTo: sent.add(const Duration(minutes: 5)),
        ),
        MessageStatus.read,
      );
    });
  });

  group('Message editing window', () {
    test('the author may edit within 15 minutes', () {
      final Message m = mine(sentAt: sent);
      expect(m.canEdit(me, now: sent.add(const Duration(minutes: 14))), isTrue);
    });

    test('the window closes after 15 minutes', () {
      final Message m = mine(sentAt: sent);
      expect(
          m.canEdit(me, now: sent.add(const Duration(minutes: 16))), isFalse);
    });

    test('nobody else may edit', () {
      expect(mine(sentAt: sent).canEdit(them, now: sent), isFalse);
    });

    test('a deleted message cannot be edited or re-deleted', () {
      final Message deleted = mine(sentAt: sent).copyWith(deletedAt: sent);
      expect(deleted.canEdit(me, now: sent), isFalse);
      expect(deleted.canDelete(me), isFalse);
      expect(deleted.displayText, 'This message was deleted');
    });
  });

  group('Ordering', () {
    test('falls back to the client clock while the server value is missing',
        () {
      expect(mine().orderedAt, sent);
    });

    test('prefers the server timestamp once it lands', () {
      final DateTime serverTime = sent.add(const Duration(seconds: 3));
      expect(mine(sentAt: serverTime).orderedAt, serverTime);
    });
  });
}
