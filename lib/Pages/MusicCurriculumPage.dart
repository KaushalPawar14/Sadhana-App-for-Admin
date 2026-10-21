import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../utils/AdminProfile.dart';
import '../utils/MusicData.dart';
import '../utils/Snackbar.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideButtons.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideWait.dart';

/// The MUSIC CURRICULUM editor (HODs and Guides only; Enablers can only see and tick).
///
/// The instruments of "My Music": add one (name, optional YouTube link), reorder them by dragging, open one to rename it,
/// change or remove its link, delete it (with a confirmation: it disappears for everyone, the students' ticks are kept in
/// storage but no longer shown), and edit its checkpoints (add, rename, delete with a confirmation, reorder by dragging).
/// Every change is written at once and appears live in both apps. Renaming and reordering keep everyone's ticks (progress
/// is kept by checkpoint id); a deleted checkpoint stops counting; a new one makes a completed instrument incomplete again.
class MusicCurriculumPage extends StatefulWidget {
  const MusicCurriculumPage({super.key, this.store});

  @visibleForTesting
  final FirestoreMusicStore? store;

  /// Who may edit: the HOD and the Guides (the same rule as the server's rules).
  static bool mayEdit(AdminProfile? p) => p != null && (p.isHod || p.isGuide);

  @override
  State<MusicCurriculumPage> createState() => _MusicCurriculumPageState();
}

class _MusicCurriculumPageState extends State<MusicCurriculumPage> {
  late final FirestoreMusicStore _store = widget.store ?? FirestoreMusicStore();
  late Stream<List<MusicInstrument>> _stream = _store.curriculum();

  void _fail([String what = 'save that']) {
    if (mounted) showSnackbar(context, "Couldn't $what. Check your connection and try again.", Colors.red, Icons.error_outline);
  }

  Future<void> _add(List<MusicInstrument> all) async {
    final result = await showDialog<({String name, String link})>(context: context, builder: (_) => const _InstrumentDialog());
    if (result == null) return;
    try {
      final id = await _store.addInstrument(name: result.name, link: result.link, order: all.length);
      if (!mounted) return;
      await Navigator.push<void>(context, MaterialPageRoute(builder: (_) => MusicInstrumentEditorPage(instrumentId: id, store: _store)));
    } catch (_) {
      _fail();
    }
  }

  Future<void> _reorder(List<MusicInstrument> all, int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final ids = [for (final i in all) i.id];
    ids.insert(newIndex, ids.removeAt(oldIndex));
    try {
      await _store.reorderInstruments(ids);
    } catch (_) {
      _fail();
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    if (!MusicCurriculumPage.mayEdit(AdminProfileProvider.current)) {
      return GuideScaffold(
        appBar: const GuideAppBar(title: Text('Music curriculum')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('Only HODs and Guides can edit the music curriculum.', key: const ValueKey('music-not-allowed'), textAlign: TextAlign.center, style: TextStyle(color: g.mutedText, fontSize: 14, height: 1.5)),
          ),
        ),
      );
    }
    return GuideScaffold(
      appBar: const GuideAppBar(title: Text('Music curriculum')),
      body: StreamBuilder<List<MusicInstrument>>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Couldn't load the curriculum.", textAlign: TextAlign.center, style: TextStyle(color: g.mutedText)),
                    const SizedBox(height: 12),
                    GuideSecondaryButton(label: 'Try again', onPressed: () => setState(() => _stream = _store.curriculum())),
                  ],
                ),
              ),
            );
          }
          if (!snap.hasData) return const GuideWait();
          final all = snap.data!;
          return ListView(
            key: const ValueKey('music-curriculum-list'),
            padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 32),
            children: [
              Text(
                'The instruments students see in My Music. Drag to reorder; open one to edit its checkpoints. Changes appear for everyone at once.',
                style: t.body.copyWith(height: 1.5, color: g.mutedText),
              ),
              const SizedBox(height: 16),
              GuidePrimaryButton(key: const ValueKey('music-add-instrument'), label: 'Add instrument', icon: Icons.add_rounded, onPressed: () => _add(all)),
              const SizedBox(height: 16),
              if (all.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text('No instruments yet.', key: const ValueKey('music-curriculum-empty'), textAlign: TextAlign.center, style: TextStyle(color: g.mutedText)),
                )
              else
                ReorderableListView.builder(
                  key: const ValueKey('music-instrument-reorder'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: all.length,
                  onReorder: (o, n) => _reorder(all, o, n),
                  itemBuilder: (context, i) {
                    final inst = all[i];
                    return Padding(
                      key: ValueKey('music-row-${inst.id}'),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GuideCard(
                        padding: EdgeInsets.zero,
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                key: ValueKey('music-open-${inst.id}'),
                                borderRadius: BorderRadius.circular(GuideShape.cardRadius),
                                onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => MusicInstrumentEditorPage(instrumentId: inst.id, store: _store))),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(inst.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${inst.checkpoints.length} checkpoint${inst.checkpoints.length == 1 ? '' : 's'}${inst.hasLink ? ' · has a link' : ''}',
                                        style: TextStyle(fontSize: 12, color: g.mutedText),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            ReorderableDragStartListener(
                              index: i,
                              child: Container(
                                key: ValueKey('music-drag-${inst.id}'),
                                width: GuideShape.touchTarget,
                                height: GuideShape.touchTarget,
                                alignment: Alignment.center,
                                child: Icon(Icons.drag_handle_rounded, color: g.mutedText),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}

/// One instrument: its name, its link, its checkpoints (reorder by dragging) and Delete.
class MusicInstrumentEditorPage extends StatefulWidget {
  const MusicInstrumentEditorPage({super.key, required this.instrumentId, this.store});

  final String instrumentId;

  @visibleForTesting
  final FirestoreMusicStore? store;

  @override
  State<MusicInstrumentEditorPage> createState() => _MusicInstrumentEditorPageState();
}

class _MusicInstrumentEditorPageState extends State<MusicInstrumentEditorPage> {
  late final FirestoreMusicStore _store = widget.store ?? FirestoreMusicStore();
  late final Stream<MusicInstrument?> _stream = _store.instrument(widget.instrumentId);

  void _fail() {
    if (mounted) showSnackbar(context, "Couldn't save that. Check your connection and try again.", Colors.red, Icons.error_outline);
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      _fail();
    }
  }

  Future<String?> _ask({required String title, String initial = '', String hint = '', String label = '', bool link = false}) =>
      showDialog<String>(context: context, builder: (_) => _TextDialog(title: title, initial: initial, hint: hint, label: label, isLink: link));

  Future<bool> _confirm({required String title, required String body, required String action, required Key key}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => GuideDialog(
        key: key,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(key: const ValueKey('music-confirm-yes'), style: TextButton.styleFrom(foregroundColor: ctx.g.danger), onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    final t = context.gText;
    return GuideScaffold(
      appBar: const GuideAppBar(title: Text('Edit instrument')),
      body: StreamBuilder<MusicInstrument?>(
        stream: _stream,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) return const GuideWait();
          final inst = snap.data;
          if (inst == null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('This instrument was deleted.', key: const ValueKey('music-instrument-gone'), textAlign: TextAlign.center, style: TextStyle(color: g.mutedText)),
              ),
            );
          }
          return ListView(
            key: const ValueKey('music-editor-list'),
            padding: const EdgeInsets.fromLTRB(GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 40),
            children: [
              GuideCard(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Column(
                  children: [
                    _FieldRow(
                      label: 'Name',
                      value: inst.name,
                      editKey: const ValueKey('music-edit-name'),
                      onEdit: () async {
                        final v = await _ask(title: 'Rename instrument', initial: inst.name, label: 'Name');
                        if (v != null) await _run(() => _store.updateInstrument(inst.id, name: v));
                      },
                    ),
                    Divider(height: 1, color: g.border),
                    _FieldRow(
                      label: 'YouTube link',
                      value: inst.hasLink ? inst.link : 'No link',
                      muted: !inst.hasLink,
                      editKey: const ValueKey('music-edit-link'),
                      onEdit: () async {
                        final v = await _ask(title: 'YouTube link', initial: inst.link, hint: 'https://…', label: 'Link', link: true);
                        if (v != null) await _run(() => _store.updateInstrument(inst.id, link: v));
                      },
                      extra: inst.hasLink
                          ? IconButton(
                              key: const ValueKey('music-remove-link'),
                              tooltip: 'Remove the link',
                              constraints: const BoxConstraints(minWidth: GuideShape.touchTarget, minHeight: GuideShape.touchTarget),
                              icon: Icon(Icons.link_off_rounded, color: g.mutedText),
                              onPressed: () => _run(() => _store.updateInstrument(inst.id, link: '')),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text('Checkpoints', style: t.sectionTitle),
              const SizedBox(height: 4),
              Text('Drag to reorder. Renaming or reordering keeps everyone\'s ticks.', style: TextStyle(fontSize: 12, color: g.mutedText)),
              const SizedBox(height: 10),
              if (inst.checkpoints.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('No checkpoints yet.', key: const ValueKey('music-no-checkpoints'), style: TextStyle(color: g.mutedText)),
                )
              else
                ReorderableListView.builder(
                  key: const ValueKey('music-checkpoint-reorder'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: inst.checkpoints.length,
                  onReorder: (o, n) {
                    if (n > o) n -= 1;
                    final ids = [for (final c in inst.checkpoints) c.id];
                    ids.insert(n, ids.removeAt(o));
                    // the new order of the ids; anything another admin added meanwhile stays (at the end), anything deleted goes
                    _run(() => _store.editCheckpoints(inst.id, (cur) {
                          final byId = {for (final c in cur) c.id: c};
                          return [for (final id in ids) if (byId.containsKey(id)) byId.remove(id)!, ...byId.values];
                        }));
                  },
                  itemBuilder: (context, i) {
                    final c = inst.checkpoints[i];
                    return Padding(
                      key: ValueKey('music-cp-row-${c.id}'),
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GuideCard(
                        padding: const EdgeInsets.fromLTRB(4, 2, 2, 2),
                        child: Row(
                          children: [
                            ReorderableDragStartListener(
                              index: i,
                              child: Container(
                                key: ValueKey('music-cp-drag-${c.id}'),
                                width: GuideShape.touchTarget,
                                height: GuideShape.touchTarget,
                                alignment: Alignment.center,
                                child: Icon(Icons.drag_handle_rounded, color: g.mutedText),
                              ),
                            ),
                            Expanded(child: Text('${i + 1}. ${c.title}', key: ValueKey('music-cp-title-${c.id}'), style: const TextStyle(fontSize: 14, height: 1.35))),
                            IconButton(
                              key: ValueKey('music-cp-edit-${c.id}'),
                              tooltip: 'Rename',
                              constraints: const BoxConstraints(minWidth: GuideShape.touchTarget, minHeight: GuideShape.touchTarget),
                              icon: Icon(Icons.edit_outlined, size: 20, color: g.text),
                              onPressed: () async {
                                final v = await _ask(title: 'Rename checkpoint', initial: c.title, label: 'Checkpoint');
                                if (v != null) {
                                  await _run(() => _store.editCheckpoints(inst.id, (cur) => [for (final x in cur) x.id == c.id ? x.copyWith(title: v) : x]));
                                }
                              },
                            ),
                            IconButton(
                              key: ValueKey('music-cp-delete-${c.id}'),
                              tooltip: 'Delete',
                              constraints: const BoxConstraints(minWidth: GuideShape.touchTarget, minHeight: GuideShape.touchTarget),
                              icon: Icon(Icons.delete_outline_rounded, size: 20, color: g.text),
                              onPressed: () async {
                                final yes = await _confirm(
                                  key: const ValueKey('music-delete-checkpoint-dialog'),
                                  title: 'Delete this checkpoint?',
                                  body: '"${c.title}" no longer counts for anyone. Ticks already given are kept in storage but not shown.',
                                  action: 'Delete',
                                );
                                if (yes) await _run(() => _store.editCheckpoints(inst.id, (cur) => [for (final x in cur) if (x.id != c.id) x]));
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 6),
              GuideSecondaryButton(
                key: const ValueKey('music-add-cp'),
                label: 'Add checkpoint',
                icon: Icons.add_rounded,
                expand: true,
                onPressed: () async {
                  final v = await _ask(title: 'Add checkpoint', label: 'Checkpoint');
                  if (v != null) await _run(() => _store.editCheckpoints(inst.id, (cur) => [...cur, MusicCheckpoint(id: newMusicId('cp'), title: v)]));
                },
              ),
              const SizedBox(height: 28),
              GuideSecondaryButton(
                key: const ValueKey('music-delete-instrument'),
                label: 'Delete instrument',
                icon: Icons.delete_outline_rounded,
                expand: true,
                onPressed: () async {
                  final yes = await _confirm(
                    key: const ValueKey('music-delete-instrument-dialog'),
                    title: 'Delete ${inst.name}?',
                    body: 'It disappears for everyone. Students\' ticks are kept in storage but no longer shown.',
                    action: 'Delete',
                  );
                  if (!yes) return;
                  try {
                    await _store.deleteInstrument(inst.id);
                    if (mounted) Navigator.pop(context);
                  } catch (_) {
                    _fail();
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value, required this.onEdit, required this.editKey, this.muted = false, this.extra});

  final String label;
  final String value;
  final bool muted;
  final VoidCallback onEdit;
  final Key editKey;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 11, color: g.mutedText, fontWeight: FontWeight.w700, letterSpacing: .4)),
                const SizedBox(height: 2),
                Text(value, style: TextStyle(fontSize: 14, color: muted ? g.mutedText : g.text, height: 1.35)),
              ],
            ),
          ),
        ),
        if (extra != null) extra!,
        IconButton(
          key: editKey,
          tooltip: 'Edit $label',
          constraints: const BoxConstraints(minWidth: GuideShape.touchTarget, minHeight: GuideShape.touchTarget),
          icon: Icon(Icons.edit_outlined, size: 20, color: g.text),
          onPressed: onEdit,
        ),
      ],
    );
  }
}

/// A one-field dialog (name / checkpoint / link). A link must be empty or a full web address.
class _TextDialog extends StatefulWidget {
  const _TextDialog({required this.title, required this.initial, required this.hint, required this.label, required this.isLink});

  final String title;
  final String initial;
  final String hint;
  final String label;
  final bool isLink;

  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final v = _c.text.trim();
    if (widget.isLink) {
      if (v.isNotEmpty && !(v.startsWith('https://') || v.startsWith('http://'))) {
        setState(() => _error = 'Please enter a full web link (https://…)');
        return;
      }
    } else if (v.isEmpty) {
      setState(() => _error = 'Please write something');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return GuideDialog(
      key: const ValueKey('music-text-dialog'),
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('music-text-field'),
        controller: _c,
        autofocus: true,
        keyboardType: widget.isLink ? TextInputType.url : TextInputType.text,
        textCapitalization: widget.isLink ? TextCapitalization.none : TextCapitalization.sentences,
        maxLength: widget.isLink ? 300 : 120,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(labelText: widget.label, hintText: widget.hint.isEmpty ? null : widget.hint, errorText: _error, counterText: ''),
      ),
      actions: [
        TextButton(key: const ValueKey('music-text-cancel'), onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        GuidePrimaryButton(key: const ValueKey('music-text-save'), label: 'Save', expand: false, onPressed: _save),
      ],
    );
  }
}

/// Add an instrument: a name and an optional YouTube link.
class _InstrumentDialog extends StatefulWidget {
  const _InstrumentDialog();

  @override
  State<_InstrumentDialog> createState() => _InstrumentDialogState();
}

class _InstrumentDialogState extends State<_InstrumentDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _link = TextEditingController();
  String? _nameError;
  String? _linkError;

  @override
  void dispose() {
    _name.dispose();
    _link.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final link = _link.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'Please write the instrument name' : null;
      _linkError = link.isNotEmpty && !(link.startsWith('https://') || link.startsWith('http://')) ? 'Please enter a full web link (https://…)' : null;
    });
    if (_nameError != null || _linkError != null) return;
    Navigator.pop(context, (name: name, link: link));
  }

  @override
  Widget build(BuildContext context) {
    return GuideDialog(
      key: const ValueKey('music-instrument-dialog'),
      title: const Text('Add instrument'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const ValueKey('music-new-name'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            maxLength: 60,
            decoration: InputDecoration(labelText: 'Name', errorText: _nameError, counterText: ''),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('music-new-link'),
            controller: _link,
            keyboardType: TextInputType.url,
            maxLength: 300,
            decoration: InputDecoration(labelText: 'YouTube link (optional)', hintText: 'https://…', errorText: _linkError, counterText: ''),
          ),
        ],
      ),
      actions: [
        TextButton(key: const ValueKey('music-new-cancel'), onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        GuidePrimaryButton(key: const ValueKey('music-new-save'), label: 'Add', expand: false, onPressed: _save),
      ],
    );
  }
}
