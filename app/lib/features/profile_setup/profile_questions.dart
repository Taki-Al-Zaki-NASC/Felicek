import '../../data/models/user_role.dart';

/// One question in "Build Your Profile".
class ProfileQuestion {
  const ProfileQuestion({
    required this.key,
    required this.label,
    required this.placeholder,
    this.multiline = false,
    this.numeric = false,
  });

  final String key;
  final String label;
  final String placeholder;
  final bool multiline;
  final bool numeric;
}

/// The role-specific question sets, taken verbatim from the design.
const Map<UserRole, List<ProfileQuestion>> profileQuestionsByRole =
    <UserRole, List<ProfileQuestion>>{
  UserRole.freelancer: <ProfileQuestion>[
    ProfileQuestion(
      key: 'fullName',
      label: 'Full name',
      placeholder: 'e.g. Sadia Rahman',
    ),
    ProfileQuestion(
      key: 'title',
      label: 'Professional title',
      placeholder: 'e.g. Flutter Developer & UI Engineer',
    ),
    ProfileQuestion(
      key: 'bio',
      label: 'Short bio',
      placeholder: 'Tell clients what you do best',
      multiline: true,
    ),
    ProfileQuestion(
      key: 'skills',
      label: 'Primary skills',
      placeholder: 'e.g. Flutter, Firebase, UI/UX',
    ),
    ProfileQuestion(
      key: 'rate',
      label: 'Hourly rate (USD)',
      placeholder: 'e.g. 28',
      numeric: true,
    ),
    ProfileQuestion(
      key: 'location',
      label: 'Location',
      placeholder: 'e.g. Dhaka, Bangladesh',
    ),
  ],
  UserRole.client: <ProfileQuestion>[
    ProfileQuestion(
      key: 'fullName',
      label: 'Full name / Company name',
      placeholder: 'e.g. FinNova Capital',
    ),
    ProfileQuestion(
        key: 'title', label: 'Industry', placeholder: 'e.g. Fintech'),
    ProfileQuestion(
      key: 'bio',
      label: 'What are you usually hiring for?',
      placeholder: 'Briefly describe your typical projects',
      multiline: true,
    ),
    ProfileQuestion(
      key: 'location',
      label: 'Location',
      placeholder: 'e.g. Remote-first',
    ),
  ],
  UserRole.agency: <ProfileQuestion>[
    ProfileQuestion(
      key: 'fullName',
      label: 'Agency name',
      placeholder: 'e.g. DevCraft Studio',
    ),
    ProfileQuestion(
      key: 'title',
      label: 'Specialization',
      placeholder: 'e.g. Backend & Cloud Infrastructure',
    ),
    ProfileQuestion(
      key: 'bio',
      label: 'Short agency description',
      placeholder: 'What makes your team stand out?',
      multiline: true,
    ),
    ProfileQuestion(
      key: 'skills',
      label: 'Team size',
      placeholder: 'e.g. 8 engineers',
    ),
    ProfileQuestion(
      key: 'location',
      label: 'Location',
      placeholder: 'e.g. Multi-seat, remote',
    ),
  ],
  UserRole.startup: <ProfileQuestion>[
    ProfileQuestion(
      key: 'fullName',
      label: 'Startup name',
      placeholder: 'e.g. Nimbus Labs',
    ),
    ProfileQuestion(
      key: 'title',
      label: 'Funding stage',
      placeholder: 'e.g. Pre-Seed',
    ),
    ProfileQuestion(
      key: 'bio',
      label: 'What are you hiring for?',
      placeholder: 'Describe the role and equity terms',
      multiline: true,
    ),
    ProfileQuestion(
      key: 'location',
      label: 'Location',
      placeholder: 'e.g. Remote, Founded 2025',
    ),
  ],
};
