import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import '../services/firestore_refs.dart';

/// The in-app notification feed at `users/{uid}/notifications`.
class NotificationRepository {
  NotificationRepository(this._db);

  final Db _db;

  Stream<List<AppNotification>> watch(String uid, {int limit = 50}) => _db
      .notifications(uid)
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map(
        (JsonQuerySnap s) =>
            s.docs.map(AppNotification.fromDoc).toList(growable: false),
      );

  Stream<int> watchUnreadCount(String uid) => _db
      .notifications(uid)
      .where('read', isEqualTo: false)
      .limit(50)
      .snapshots()
      .map((JsonQuerySnap s) => s.docs.length);

  Future<void> markRead(String uid, String notificationId) =>
      _db.notifications(uid).doc(notificationId).set(
        <String, dynamic>{'read': true},
        SetOptions(merge: true),
      );

  Future<void> markAllRead(String uid) async {
    final JsonQuerySnap snap = await _db
        .notifications(uid)
        .where('read', isEqualTo: false)
        .limit(400)
        .get();
    if (snap.docs.isEmpty) return;
    // Firestore caps a batch at 500 writes.
    for (int i = 0; i < snap.docs.length; i += 400) {
      final WriteBatch batch = _db.firestore.batch();
      for (final QueryDocumentSnapshot<Json> doc
          in snap.docs.sublist(i, (i + 400).clamp(0, snap.docs.length))) {
        batch.set(doc.reference, <String, dynamic>{'read': true},
            SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  Future<void> delete(String uid, String notificationId) =>
      _db.notifications(uid).doc(notificationId).delete();

  /// Trims the feed so a long-lived account never grows without bound — the
  /// free tier has a 1 GiB storage ceiling and this is the only collection
  /// that grows purely from activity.
  Future<void> pruneOlderThan(String uid,
      {Duration age = const Duration(days: 30)}) async {
    final DateTime cutoff = DateTime.now().subtract(age);
    final JsonQuerySnap snap = await _db
        .notifications(uid)
        .where('createdAt', isLessThan: Timestamp.fromDate(cutoff))
        .limit(200)
        .get();
    if (snap.docs.isEmpty) return;
    final WriteBatch batch = _db.firestore.batch();
    for (final QueryDocumentSnapshot<Json> doc in snap.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}
