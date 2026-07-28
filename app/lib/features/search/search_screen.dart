import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/services.dart';
import '../../app/session_controller.dart';
import '../../core/theme/tokens.dart';
import '../../core/theme/typography.dart';
import '../../core/widgets/f_avatar.dart';
import '../../core/widgets/f_field.dart';
import '../../core/widgets/f_pill.dart';
import '../../core/widgets/f_surface.dart';
import '../../data/models/job.dart';
import '../../data/models/public_profile.dart';
import '../../data/repositories/job_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/services/firestore_refs.dart';
import '../job/job_card.dart';
import '../job/job_detail_screen.dart';

/// Search jobs, skills or clients — the prefix search the design's search bar
/// implies, backed by the on-device `searchTerms` arrays so it needs no paid
/// search service.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _query = TextEditingController();
  List<Job> _jobs = const <Job>[];
  List<PublicProfile> _people = const <PublicProfile>[];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (q.trim().length < 2) {
      setState(() {
        _jobs = const <Job>[];
        _people = const <PublicProfile>[];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    // Resolve the repositories up front — reading them off `context` after
    // an await risks touching a disposed element.
    final JobRepository jobs0 = context.jobRepo;
    final UserRepository users0 = context.userRepo;
    try {
      final List<Job> jobs = await jobs0.search(q);
      final List<PublicProfile> people = await users0.search(q);
      if (!mounted) return;
      setState(() {
        _jobs = jobs;
        _people = people;
      });
    } on Object catch (e) {
      // Without this the throw escaped and left _loading true forever: the
      // screen became a spinner under a live text field, and every further
      // keystroke threw again. There was no way out but the back button.
      if (mounted) setState(() => _error = describeFirestoreError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool browsesListings =
        context.select<SessionController, bool>((s) => s.role.browsesListings);

    return Scaffold(
      backgroundColor: FColors.canvas,
      body: Column(
        children: <Widget>[
          Container(
            color: FColors.surface,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: <Widget>[
                  FBackChevron(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: FSpace.xl),
                  Expanded(
                    child: FField(
                      controller: _query,
                      hint: browsesListings
                          ? 'Search jobs, skills, or clients...'
                          : 'Search freelancers or listings...',
                      autofocus: true,
                      onChanged: _search,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading) const FLoading(),
          if (!_loading && _error != null)
            Expanded(child: FErrorState(message: _error!)),
          if (!_loading && _error == null)
            Expanded(
              child: (_jobs.isEmpty && _people.isEmpty)
                  ? FEmptyState(
                      icon: Icons.search_rounded,
                      title: _query.text.trim().length < 2
                          ? 'Search Felicek'
                          : 'No matches',
                      message: _query.text.trim().length < 2
                          ? 'Find listings, skills and people by name.'
                          : 'Try a different keyword.',
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      children: <Widget>[
                        if (_jobs.isNotEmpty) ...<Widget>[
                          const FSectionLabel('Listings'),
                          const SizedBox(height: FSpace.lg),
                          for (final Job job in _jobs) ...<Widget>[
                            JobCard(
                              job: job,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) =>
                                      JobDetailScreen(jobId: job.id),
                                ),
                              ),
                            ),
                            const SizedBox(height: FSpace.xl),
                          ],
                        ],
                        if (_people.isNotEmpty) ...<Widget>[
                          const SizedBox(height: FSpace.lg),
                          const FSectionLabel('People'),
                          const SizedBox(height: FSpace.lg),
                          for (final PublicProfile p in _people) ...<Widget>[
                            FCard(
                              radius: FRadius.card,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 13, vertical: 12),
                              child: Row(
                                children: <Widget>[
                                  FAvatar(
                                    size: 40,
                                    seed: p.uid,
                                    photoBase64: p.profilePhotoBase64,
                                    initials:
                                        FAvatar.initialsFor(p.displayName),
                                    verified: p.verified,
                                  ),
                                  const SizedBox(width: FSpace.xl),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: <Widget>[
                                        Text(p.displayName,
                                            style: FType.titleXs),
                                        Text(p.title, style: FType.captionSm),
                                      ],
                                    ),
                                  ),
                                  FRoleBadge(p.role.shortLabel),
                                ],
                              ),
                            ),
                            const SizedBox(height: FSpace.lg),
                          ],
                        ],
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
