import 'package:cloud_firestore/cloud_firestore.dart';

typedef Json = Map<String, dynamic>;
typedef JsonDoc = DocumentSnapshot<Json>;
typedef JsonQuery = Query<Json>;
typedef JsonQuerySnap = QuerySnapshot<Json>;

/// Every Firestore path in the app, in one place.
///
/// ```
/// users/{uid}                              — private record, owner-only
/// users/{uid}/transactions/{txId}
/// users/{uid}/notifications/{notificationId}
/// profiles/{uid}                           — public mirror, world-readable
/// jobs/{jobId}
/// jobs/{jobId}/challengeKey/answer         — owner-only, never freelancer-readable
/// proposals/{proposalId}
/// proposals/{proposalId}/submission/full   — freelancer-only full challenge answer
/// paymentIntents/{ref}                     — client creates 'pending'; only a
///                                             server webhook may set 'paid'
/// calls/{callId}                           — WebRTC signaling (offer/answer/ICE)
/// chats/{chatId}
/// chats/{chatId}/messages/{messageId}
/// meta/config          — remote flags read by the updater and the app shell
/// ```
class Db {
  Db(this.firestore);

  final FirebaseFirestore firestore;

  static const String usersPath = 'users';
  static const String profilesPath = 'profiles';
  static const String jobsPath = 'jobs';
  static const String proposalsPath = 'proposals';
  static const String chatsPath = 'chats';
  static const String messagesPath = 'messages';
  static const String transactionsPath = 'transactions';
  static const String notificationsPath = 'notifications';
  static const String metaPath = 'meta';
  static const String paymentIntentsPath = 'paymentIntents';
  static const String callsPath = 'calls';
  static const String challengeKeyPath = 'challengeKey';
  static const String submissionPath = 'submission';

  CollectionReference<Json> get users => firestore.collection(usersPath);

  DocumentReference<Json> user(String uid) => users.doc(uid);

  CollectionReference<Json> get profiles => firestore.collection(profilesPath);

  DocumentReference<Json> profile(String uid) => profiles.doc(uid);

  CollectionReference<Json> transactions(String uid) =>
      user(uid).collection(transactionsPath);

  CollectionReference<Json> notifications(String uid) =>
      user(uid).collection(notificationsPath);

  CollectionReference<Json> get jobs => firestore.collection(jobsPath);

  DocumentReference<Json> job(String jobId) => jobs.doc(jobId);

  CollectionReference<Json> get proposals =>
      firestore.collection(proposalsPath);

  DocumentReference<Json> proposal(String id) => proposals.doc(id);

  CollectionReference<Json> get chats => firestore.collection(chatsPath);

  DocumentReference<Json> chat(String chatId) => chats.doc(chatId);

  CollectionReference<Json> messages(String chatId) =>
      chat(chatId).collection(messagesPath);

  DocumentReference<Json> message(String chatId, String messageId) =>
      messages(chatId).doc(messageId);

  DocumentReference<Json> get config =>
      firestore.collection(metaPath).doc('config');

  CollectionReference<Json> get paymentIntents =>
      firestore.collection(paymentIntentsPath);

  DocumentReference<Json> paymentIntent(String ref) => paymentIntents.doc(ref);

  CollectionReference<Json> get calls => firestore.collection(callsPath);

  DocumentReference<Json> call(String callId) => calls.doc(callId);

  /// Owner-only answer key for a listing's quiz challenge — never readable by
  /// an applicant, even after they've been graded.
  DocumentReference<Json> challengeKey(String jobId) =>
      job(jobId).collection(challengeKeyPath).doc('answer');

  /// A freelancer's full challenge submission (code/design/quiz answers).
  /// Readable only by that freelancer — the job owner only ever sees the
  /// score and short summary stored on the [Proposal] document itself.
  DocumentReference<Json> proposalSubmission(String proposalId) =>
      proposal(proposalId).collection(submissionPath).doc('full');

  /// A client-generated id, used so a retried write lands on the same document.
  String newId(CollectionReference<Json> collection) => collection.doc().id;
}

/// Turns a Firestore exception into a sentence a person can act on.
String describeFirestoreError(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'You do not have access to that. Try signing in again.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'You appear to be offline. This will sync once you reconnect.';
      case 'not-found':
        return 'That item no longer exists.';
      case 'already-exists':
        return 'That already exists.';
      case 'resource-exhausted':
        return 'The service is busy right now. Please try again in a moment.';
      case 'failed-precondition':
        return 'That action is not available yet.';
      case 'cancelled':
        return 'The request was cancelled.';
      default:
        return error.message ?? 'Something went wrong. Please try again.';
    }
  }
  return 'Something went wrong. Please try again.';
}
