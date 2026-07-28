import 'package:cloud_firestore/cloud_firestore.dart';

/// A seat on an agency's team, stored at `users/{agencyUid}/seats/{seatId}`.
///
/// The design showed a static roster of names. A seat here is a real invite:
/// the agency records a teammate's email and role, and the seat stays
/// `Invited` until that person actually signs up with that address — at which
/// point [displayName] and [accepted] fill in. Showing a name before someone
/// has joined would imply a team member who isn't there.
class TeamSeat {
  const TeamSeat({
    required this.id,
    required this.email,
    required this.role,
    this.displayName,
    this.memberUid,
    this.accepted = false,
    this.invitedAt,
    this.acceptedAt,
  });

  factory TeamSeat.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final Map<String, dynamic> d = doc.data() ?? <String, dynamic>{};
    return TeamSeat(
      id: doc.id,
      email: d['email'] as String? ?? '',
      role: d['role'] as String? ?? 'Team member',
      displayName: d['displayName'] as String?,
      memberUid: d['memberUid'] as String?,
      accepted: d['accepted'] as bool? ?? false,
      invitedAt: (d['invitedAt'] as Timestamp?)?.toDate(),
      acceptedAt: (d['acceptedAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String email;
  final String role;

  /// Filled in once the invited person has an account.
  final String? displayName;
  final String? memberUid;
  final bool accepted;
  final DateTime? invitedAt;
  final DateTime? acceptedAt;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'email': email.toLowerCase().trim(),
        'role': role,
        'displayName': displayName,
        'memberUid': memberUid,
        'accepted': accepted,
      };
}
