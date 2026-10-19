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
  Map<BestField, List<LeaderboardEntry>> _fields = const {};

  /// Bumped on every request, so a slow answer for an old selection is ignored.
  int _request = 0;

  /// The weekly Best performer winners for the viewed gender (both categories).
  Future<Map<String, BestPerformerSet>>? _best;
  String? _bestGender;

  bool get _isHod => AdminProfileProvider.viewerIsHod;

  @override
  void initState() {
    super.initState();
    // Non-HOD admins are fixed to the gender of their role; a HOD starts on Boys.
    _gender = AdminProfileProvider.instance.profile?.gender ?? 'male';
    _fetch();
    _fetchBest();
  }

  void _fetchBest() {
    _bestGender = _gender;
    _best = LeaderboardData.instance.bestPerformers(gender: _gender);
  }

  Future<void> _fetch() async {
    final request = ++_request;
    setState(() => _load = GuideLoad.loading);
    try {
      final both = await Future.wait<Object>([
        LeaderboardData.instance.ranking(category: _category, gender: _gender, period: _period),
        LeaderboardData.instance.fieldBests(category: _category, gender: _gender, period: _period),
      ]);
      final entries = both[0] as List<LeaderboardEntry>;
      final fields = both[1] as Map<BestField, List<LeaderboardEntry>>;
      if (!mounted || request != _request) return;
      setState(() {
        _fields = fields;
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
    if (_bestGender != _gender) setState(_fetchBest);
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GuideStateView(
                    state: _load,
                    ghost: const GuideGhostList(rows: 6, rowHeight: 64, padding: EdgeInsets.zero),
                    emptyMessage: leaderboardEmptyMessage(category: _category, gender: _gender, period: _period),
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
                  if (_load == GuideLoad.content && _fields.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _FieldBests(fields: _fields, period: _period),
                  ],
                  const SizedBox(height: 22),
                  _BestSection(
                    future: _best,
                    boys: boys,
                    onRetry: () => setState(_fetchBest),
                  ),
                ],
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

/// "Best by field": the best five of Chanting, Reading, Hearing and (FOLK only) Service for the period, by each
/// field's own points (no multipliers).
class _FieldBests extends StatelessWidget {
  const _FieldBests({required this.fields, required this.period});

  final Map<BestField, List<LeaderboardEntry>> fields;
  final LeaderboardPeriod period;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final g = context.g;
    String pts(double p) => '${p == p.roundToDouble() ? p.toInt() : p.toStringAsFixed(1)} pts';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('BEST BY FIELD · ${period.label.toUpperCase()}', style: t.label),
        const SizedBox(height: 8),
        for (final f in BestField.values)
          if (fields.containsKey(f))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GuideCard(
                key: ValueKey('field-${f.name}'),
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(f.title, style: t.cardTitle),
                    const SizedBox(height: 6),
                    if (fields[f]!.isEmpty)
                      Text('No points here yet.', style: t.caption.copyWith(color: g.mutedText))
                    else
                      for (var i = 0; i < fields[f]!.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              SizedBox(width: 24, child: Text('${i + 1}', style: t.bodyStrong.copyWith(color: g.mutedText))),
                              Expanded(child: Text(fields[f]![i].name, style: t.body)),
                              Text(pts(fields[f]![i].score), style: t.bodyStrong),
                            ],
                          ),
                        ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// "Best performer": the two weekly winners of each category, for the viewed gender, in
/// the latest finalised week. A winner in the admin's own group is marked.
class _BestSection extends StatelessWidget {
  const _BestSection({required this.future, required this.boys, required this.onRetry});

  final Future<Map<String, BestPerformerSet>>? future;
  final bool boys;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final g = context.g;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('BEST PERFORMER', style: t.label),
        const SizedBox(height: 2),
        Text(
          "The week's two winners — ${boys ? 'boys' : 'girls'}, decided every Sunday.",
          style: t.caption.copyWith(color: g.mutedText),
        ),
        const SizedBox(height: 10),
        FutureBuilder<Map<String, BestPerformerSet>>(
          future: future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const GuideGhostArea(child: GuideGhostBlock(height: 120));
            }
            if (snap.hasError) {
              return GuideCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Expanded(child: Text("Couldn't load the winners just now.", style: t.small)),
                    TextButton(onPressed: onRetry, child: const Text('Retry')),
                  ],
                ),
              );
            }
            final data = snap.data ?? const <String, BestPerformerSet>{};
            if (data.isEmpty) {
              return GuideCard(
                padding: const EdgeInsets.all(14),
                child: Text('No winners yet — the first ones appear after the weekly results.', style: t.small),
              );
            }
            return Column(
              children: [
                for (final category in [kCategoryFolk, kCategoryHostelLocalite])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CategoryWinners(category: category, set: data[category]),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _CategoryWinners extends StatelessWidget {
  const _CategoryWinners({required this.category, required this.set});

  final String category;
  final BestPerformerSet? set;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    return GuideCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(categoryLabel(category), style: t.cardTitle),
          const SizedBox(height: 8),
          _WinnerLine(label: 'Most improved', winner: set?.mostImproved),
          const SizedBox(height: 8),
          _WinnerLine(label: 'Commitment keeper', winner: set?.commitmentKeeper),
        ],
      ),
    );
  }
}

class _WinnerLine extends StatelessWidget {
  const _WinnerLine({required this.label, required this.winner});

  final String label;
  final BestWinnerInfo? winner;

  @override
  Widget build(BuildContext context) {
    final t = context.gText;
    final g = context.g;
    final w = winner;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.caption),
        if (w == null)
          Text('No winner this week.', style: t.small)
        else ...[
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              Text(w.name, style: t.bodyStrong),
              if (w.inScope)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: g.brass.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('In your group', style: t.pill.copyWith(color: g.brass)),
                ),
            ],
          ),
          if (w.reason.isNotEmpty) Text(w.reason, style: t.small),
        ],
      ],
    );
  }
}
