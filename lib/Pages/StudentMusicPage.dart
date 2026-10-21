import 'package:flutter/material.dart';

import '../theme/GuideColors.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/MusicData.dart';
import '../utils/Snackbar.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideTiles.dart';
import '../widgets/GuideWait.dart';

/// A student's MUSIC progress, seen from the Guide app: the curriculum (as the HODs and Guides set it, live) with the
/// student's ticks. The student and any admin who can see the student (the usual scope) can tick and untick: no approval;
/// who ticked and when is shown subtly under each tick. The instruments the student added themselves ("Others") are read
/// only here.
class StudentMusicPage extends StatefulWidget {
  const StudentMusicPage({super.key, required this.studentUid, required this.studentName, this.canTick = true, this.store});

  final String studentUid;
  final String studentName;

  /// False when the viewer may look but not act (a student outside their scope); the rules refuse the write as well.
  final bool canTick;

  @visibleForTesting
  final FirestoreMusicStore? store;

  @override
  State<StudentMusicPage> createState() => _StudentMusicPageState();
}

class _StudentMusicPageState extends State<StudentMusicPage> {
  late final FirestoreMusicStore _store = widget.store ?? FirestoreMusicStore();
  late final Stream<List<MusicInstrument>> _curriculum = _store.curriculum();
  late final Stream<MusicProgress> _progress = _store.progress(widget.studentUid);
  final Set<String> _open = {};

  Future<void> _tick(String checkpointId, bool ticked) async {
    final me = AdminProfileProvider.current;
    if (me == null || !widget.canTick) return;
    try {
      await _store.setTick(widget.studentUid, checkpointId, ticked, by: me.id, byName: me.displayName);
    } catch (_) {
      if (mounted) showSnackbar(context, "Couldn't save that tick. Check your connection and try again.", Colors.red, Icons.error_outline);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return GuideScaffold(
      appBar: GuideAppBar(title: Text('${widget.studentName} · Music')),
      body: StreamBuilder<List<MusicInstrument>>(
        stream: _curriculum,
        builder: (context, cur) {
          if (cur.hasError) {
            return Center(child: Padding(padding: const EdgeInsets.all(32), child: Text("Couldn't load the music curriculum.", textAlign: TextAlign.center, style: TextStyle(color: g.mutedText))));
          }
          if (!cur.hasData) return const GuideWait();
          final instruments = cur.data!;
          return StreamBuilder<MusicProgress>(
            stream: _progress,
            builder: (context, prog) {
              final progress = prog.data ?? MusicProgress.empty;
              return ListView(
                key: const ValueKey('student-music-list'),
                padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 32),
                children: [
                  Text(
                    widget.canTick ? 'Tick a checkpoint when ${widget.studentName} has learned it. The student can tick too.' : 'You can see this progress but not change it.',
                    key: const ValueKey('student-music-intro'),
                    style: context.gText.body.copyWith(height: 1.5, color: g.mutedText),
                  ),
                  const SizedBox(height: 14),
                  if (instruments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text('No instruments have been set up yet.', key: const ValueKey('student-music-empty'), textAlign: TextAlign.center, style: TextStyle(color: g.mutedText)),
                    ),
                  for (final inst in instruments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _InstrumentCard(
                        key: ValueKey('student-music-instrument-${inst.id}'),
                        instrument: inst,
                        progress: progress,
                        expanded: _open.contains(inst.id),
                        canTick: widget.canTick,
                        onToggle: () => setState(() => _open.contains(inst.id) ? _open.remove(inst.id) : _open.add(inst.id)),
                        onTick: _tick,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text('Others', style: context.gText.sectionTitle),
                  const SizedBox(height: 4),
                  Text('Instruments ${widget.studentName} added.', style: TextStyle(fontSize: 12, color: g.mutedText)),
                  const SizedBox(height: 8),
                  if (progress.others.isEmpty)
                    Text('None.', key: const ValueKey('student-music-others-empty'), style: TextStyle(color: g.mutedText))
                  else
                    for (final o in progress.others)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GuideCard(
                          key: ValueKey('student-music-other-${o.id}'),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(child: Text(o.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                decoration: BoxDecoration(color: g.chipBackground, borderRadius: BorderRadius.circular(20)),
                                child: Text(o.level.label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: g.mutedText)),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _InstrumentCard extends StatelessWidget {
  const _InstrumentCard({super.key, required this.instrument, required this.progress, required this.expanded, required this.canTick, required this.onToggle, required this.onTick});

  final MusicInstrument instrument;
  final MusicProgress progress;
  final bool expanded;
  final bool canTick;
  final VoidCallback onToggle;
  final Future<void> Function(String checkpointId, bool ticked) onTick;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final total = instrument.checkpoints.length;
    final done = progress.done(instrument);
    final completed = progress.completed(instrument);
    return GuideCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: ValueKey('student-music-header-${instrument.id}'),
            borderRadius: BorderRadius.circular(GuideShape.cardRadius),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(instrument.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                      if (completed)
                        Container(
                          key: const ValueKey('student-music-completed'),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(color: g.success.withValues(alpha: .16), borderRadius: BorderRadius.circular(20)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_rounded, size: 14, color: g.success),
                              const SizedBox(width: 3),
                              Text('Completed', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: g.success)),
                            ],
                          ),
                        ),
                      Icon(expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: g.mutedText),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(total == 0 ? 'No checkpoints yet' : '$done of $total', key: ValueKey('student-music-count-${instrument.id}'), style: TextStyle(fontSize: 12, color: g.mutedText)),
                  const SizedBox(height: 8),
                  GuideProgressBar(value: total == 0 ? 0 : done / total, height: 6),
                ],
              ),
            ),
          ),
          GuideAnimatedSize(
            child: expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Column(
                      children: [
                        for (final c in instrument.checkpoints) _CheckpointRow(key: ValueKey('student-music-cp-${c.id}'), checkpoint: c, tick: progress.ticks[c.id], canTick: canTick, onChanged: (v) => onTick(c.id, v)),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  const _CheckpointRow({super.key, required this.checkpoint, required this.tick, required this.canTick, required this.onChanged});

  final MusicCheckpoint checkpoint;
  final MusicTick? tick;
  final bool canTick;
  final ValueChanged<bool> onChanged;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// "Student · 12 Oct" / "You · 12 Oct" / "Madhava Das · 12 Oct": who ticked it and when, shown subtly.
  String? _by(String? myId) {
    final t = tick;
    if (t == null) return null;
    final who = t.byStudent ? 'Student' : (t.by == myId ? 'You' : (t.byName.isEmpty ? 'An admin' : t.byName));
    final at = t.at;
    return at == null ? who : '$who · ${at.day} ${_months[at.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final ticked = tick != null;
    final by = _by(AdminProfileProvider.current?.id);
    return Semantics(
      checked: ticked,
      label: checkpoint.title,
      excludeSemantics: true,
      onTap: canTick ? () => onChanged(!ticked) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: canTick ? () => onChanged(!ticked) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: GuideShape.touchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                AnimatedContainer(
                  key: ValueKey('student-music-box-${checkpoint.id}'),
                  duration: GuideMotion.of(context, const Duration(milliseconds: 130)),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: ticked ? g.success : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                    border: ticked ? null : Border.all(color: g.mutedText.withValues(alpha: .6), width: 1.6),
                  ),
                  child: ticked ? Icon(Icons.check_rounded, size: 17, color: GuideColors.onPastel) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(checkpoint.title, style: const TextStyle(fontSize: 14, height: 1.35)),
                      if (by != null) Text(by, key: ValueKey('student-music-by-${checkpoint.id}'), style: TextStyle(fontSize: 11, color: g.mutedText)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Music" row on a student's profile: how many instruments are completed, opens the progress page.
class StudentMusicCard extends StatelessWidget {
  const StudentMusicCard({super.key, required this.studentUid, required this.studentName, this.canTick = true, this.store});

  final String studentUid;
  final String studentName;
  final bool canTick;

  @visibleForTesting
  final FirestoreMusicStore? store;

  @override
  Widget build(BuildContext context) {
    final s = store ?? FirestoreMusicStore();
    return StreamBuilder<List<MusicInstrument>>(
      stream: s.curriculum(),
      builder: (context, cur) => StreamBuilder<MusicProgress>(
        stream: s.progress(studentUid),
        builder: (context, prog) {
          final instruments = cur.data ?? const <MusicInstrument>[];
          final progress = prog.data ?? MusicProgress.empty;
          final completed = instruments.where(progress.completed).length;
          final subtitle = !cur.hasData
              ? 'Instruments and checkpoints'
              : instruments.isEmpty
                  ? 'No instruments set up yet'
                  : '$completed of ${instruments.length} instrument${instruments.length == 1 ? '' : 's'} completed';
          return GuideNavCard(
            key: const ValueKey('student-music-card'),
            pastel: GuidePastel.mauve,
            icon: Icons.music_note_outlined,
            title: 'Music',
            description: subtitle,
            onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => StudentMusicPage(studentUid: studentUid, studentName: studentName, canTick: canTick, store: store))),
          );
        },
      ),
    );
  }
}
