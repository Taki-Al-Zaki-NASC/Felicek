/// What a role's mandatory deposit is *for*.
enum DepositKind {
  /// Freelancers: a refundable trust bond, released after the first
  /// successfully completed job. Not spendable.
  trustBond,

  /// Clients, agencies and startups: a pre-funded job-posting balance. Not a
  /// charge — it is their money, spent on escrow when they hire, withdrawable
  /// if they never do.
  postingBalance,
}

/// The four account types the product ships with. Everything downstream —
/// which home screen renders, what has to be paid before the account opens,
/// whether a profile photo is mandatory — keys off this.
enum UserRole {
  freelancer(
    key: 'freelancer',
    label: 'Freelancer',
    shortLabel: 'Freelancer',
    description: 'Find verified gigs, take skill challenges',
    depositCents: 2000,
    depositKind: DepositKind.trustBond,
    requiresProfilePhoto: true,
  ),
  client(
    key: 'client',
    label: 'Individual Client',
    shortLabel: 'Client',
    description: 'Post jobs, hire with escrow protection',
    depositCents: 5000,
    depositKind: DepositKind.postingBalance,
    requiresProfilePhoto: false,
  ),
  agency(
    key: 'agency',
    label: 'Agency',
    shortLabel: 'Agency',
    description: 'Multi-seat team, bulk listings, shared escrow',
    depositCents: 5000,
    depositKind: DepositKind.postingBalance,
    requiresProfilePhoto: false,
  ),
  startup(
    key: 'startup',
    label: 'Startup',
    shortLabel: 'Startup',
    description: 'Fast-track hiring, equity-based roles',
    depositCents: 5000,
    depositKind: DepositKind.postingBalance,
    requiresProfilePhoto: false,
  );

  const UserRole({
    required this.key,
    required this.label,
    required this.shortLabel,
    required this.description,
    required this.depositCents,
    required this.depositKind,
    required this.requiresProfilePhoto,
  });

  final String key;
  final String label;
  final String shortLabel;
  final String description;

  /// Every account pays before it opens — no role can skip this.
  final int depositCents;
  final DepositKind depositKind;

  /// Individual freelancers must show their face before they can bid; a
  /// faceless "verified" freelancer is exactly the trust gap this product
  /// exists to close.
  final bool requiresProfilePhoto;

  static UserRole fromKey(String? key) => UserRole.values.firstWhere(
        (UserRole r) => r.key == key,
        orElse: () => UserRole.freelancer,
      );

  double get depositAmount => depositCents / 100;

  /// Freelancers browse listings; everyone else gets the posting dashboard.
  bool get browsesListings => this == UserRole.freelancer;

  /// Roles that receive proposals rather than send them.
  bool get reviewsProposals => this != UserRole.freelancer;

  /// The line that explains the deposit on the verification screen.
  String get depositExplanation => switch (depositKind) {
        DepositKind.trustBond =>
          'A refundable trust bond. It is held, never spent, and is released '
              'to your wallet after your first successfully completed job.',
        DepositKind.postingBalance =>
          'This is not a fee. It becomes your posting balance — the money you '
              'fund escrow with when you hire. Withdraw it any time you have '
              'no open listings.',
      };

  String get depositHeading => switch (depositKind) {
        DepositKind.trustBond => 'Security Deposit',
        DepositKind.postingBalance => 'Job Posting Balance',
      };

  /// The listing type this role publishes.
  String get publishesListingType => switch (this) {
        UserRole.freelancer => 'freelance',
        UserRole.client => 'freelance',
        UserRole.agency => 'agency',
        UserRole.startup => 'startup',
      };

  /// The tag shown on listings this role publishes.
  String get publishesTypeLabel => switch (this) {
        UserRole.freelancer => 'Freelance',
        UserRole.client => 'Freelance',
        UserRole.agency => 'Agency',
        UserRole.startup => 'Startup · Equity',
      };
}

/// The identity documents the verification partner accepts.
enum IdDocumentType {
  nationalId(
      'nid', 'National ID (NID)', 'Encrypted · never shown to other users'),
  passport('passport', 'Passport', 'Machine-readable passport number'),
  drivingLicence(
      'driving', "Driver's Licence", 'Government-issued licence number'),
  governmentId('govid', 'Other Government ID', 'Any national photo ID card'),
  birthCertificate(
    'birth',
    'Birth Certificate',
    'Optional secondary document',
  );

  const IdDocumentType(this.key, this.label, this.hint);

  final String key;
  final String label;
  final String hint;

  static IdDocumentType fromKey(String? key) =>
      IdDocumentType.values.firstWhere(
        (IdDocumentType t) => t.key == key,
        orElse: () => IdDocumentType.nationalId,
      );

  /// Everything except the birth certificate counts as primary ID.
  static List<IdDocumentType> get primary => IdDocumentType.values
      .where((IdDocumentType t) => t != IdDocumentType.birthCertificate)
      .toList(growable: false);

  /// Rough length sanity check before the number is accepted.
  int get minLength => switch (this) {
        IdDocumentType.passport => 6,
        IdDocumentType.nationalId => 10,
        IdDocumentType.drivingLicence => 6,
        IdDocumentType.governmentId => 5,
        IdDocumentType.birthCertificate => 6,
      };
}
