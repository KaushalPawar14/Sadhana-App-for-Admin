import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/LeaderboardData.dart';
import '../widgets/GuideEntry.dart';
import '../widgets/GuideGhost.dart';
import '../widgets/GuideMeta.dart';
import '../widgets/GuideStates.dart';
import '../widgets/GuideSurface.dart';

/// The competition leaderboard, for guides.
///
/// Students compete in one of two categories: FOLK, or Hostel & Localite (those two
/// residences compete together). Each category is ranked by gender too, so there
/// are four rankings; this screen shows ONE at a time, with a clear selector for the
/// category (FOLK / Hostel & Localite) and the period (this week / this month).
///
/// Always inside the admin's own scope: a Guide sees his team's boys (and the
/// unassigned boys), an Enabler his own students (and the unassigned of his
/// gender), a HOD everyone - the HOD also picks Boys or Girls, everyone else is
/// fixed to the gender of their role. See `LeaderboardData` for the queries.
class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({super.key});

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  String _category = kCategoryFolk;
  late String _gender;
  LeaderboardPeriod _period = LeaderboardPeriod.weekly;

  GuideLoad _load = GuideLoad.loading;
  List<LeaderboardEntry> _entries = const [];

  /// Bumped on every request, so a slow answer for an old selection is ignored.
  int _request = 0;

  bool get _isHod => AdminProfileProvider.viewerIsHod;

  @override
  void initState() {
    super.initState();
    // Non-HOD admins are fixed to the gender of their role; a HOD starts on Boys.
    _gender = AdminProfileProvider.instance.profile?.gender ?? 'male';
    _fetch();
  }

  Future<void> _fetch() async {
    final request = ++_request;
    setState(() => _load = GuideLoad.loading);
    try {
      final entries = await LeaderboardData.instance.ranking(
        category: _category,
        gender: _gender,
        period: _period,
      );
      if (!mounted || request != _request) return;
      setState(() {
        _entries = entries;
        _load = entries.isEmpty ? GuideLoad.empty : GuideLoad.content;
      });
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _load = GuideLoad.error);
    }
  }

  void _pick({String? category, String? gender, LeaderboardPeriod? period}) {
    if ((category == null || category == _category) &&
        (gender == null || gender == _gender) &&
        (period == null || period == _period)) {
      return;
    }
    _category = category ?? _category;
    _gender = gender ?? _gender;
    _period = period ?? _period;
    _fetch();
  }

  Widget _chips(String label, List<Widget> chips) {
    final t = context.gText;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: t.label),
          Wrap(spacing: 8, runSpacing: 0, children: chips),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final g = context.g;
    final boys = _gender == 'male';
    return GuideScaffold(
      body: Column(
        children: [
          const GuideTopBar(title: 'Leaderboard'),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                GuideSpace.pagePadding, 6, GuideSpace.pagePadding, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _chips('Category', [
                  GuideChoiceChip(
                    label: 'FOLK',
                    selected: _category == kCategoryFolk,
                    onSelected: (_) => _pick(category: kCategoryFolk),
                  ),
                  GuideChoiceChip(
                    label: 'Hostel & Localite',
                    selected: _category == kCategoryHostelLocalite,
                    onSelected: (_) => _pick(category: kCategoryHostelLocalite),
                  ),
                ]),
                if (_isHod)
                  _chips('Group', [
                    GuideChoiceChip(
                      label: 'Boys',
                      selected: boys,
                      onSelected: (_) => _pick(gender: 'male'),
                    ),
                    GuideChoiceChip(
                      label: 'Girls',
                      selected: !boys,
                      onSelected: (_) => _pick(gender: 'female'),
                    ),
                  ]),
                _chips('Period', [
                  for (final p in LeaderboardPeriod.values)
                    GuideChoiceChip(
                      label: p.label,
                      selected: _period == p,
                      onSelected: (_) => _pick(period: p),
                    ),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 4),
                  child: Text(
                    '${categoryLabel(_category)} · ${boys ? 'Boys' : 'Girls'} · ${_period.label.toLowerCase()}. '
                    'Only students in your own group are listed.',
                    style: t.caption.copyWith(color: g.mutedText),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  GuideSpace.pagePadding, 8, GuideSpace.pagePadding, 28),
              child: GuideStateView(
                state: _load,
                ghost: const GuideGhostList(rows: 6, rowHeight: 64, padding: EdgeInsets.zero),
                emptyMessage: 'No scores yet for this group ${_period == LeaderboardPeriod.weekly ? 'this week' : 'this month'}.',
                onRetry: _fetch,
                content: Column(
                  children: [
                    for (var i = 0; i < _entries.length; i++)
                      GuideEntry(
                        index: i,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _Row(rank: i + 1, entry: _entries[i]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.rank, required this.entry});

  final int rank;
  final LeaderboardEntry entry;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final g = context.g;
    final top = rank <= 3;
    return GuideCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: top ? g.brass.withValues(alpha: .18) : g.chipBackground,
            ),
            child: Text('$rank',
                style: t.bodyStrong.copyWith(color: top ? g.brass : g.mutedText)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name, style: t.cardTitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (entry.days > 0)
                  Text('${entry.days} ${entry.days == 1 ? 'day' : 'days'} reported', style: t.caption),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(entry.score.toStringAsFixed(2), style: t.bodyStrong),
        ],
      ),
    );
  }
}
