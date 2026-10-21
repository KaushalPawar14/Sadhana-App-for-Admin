import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'GuideDb.dart';

// MY MUSIC (Guide app side) - the curriculum the HODs and Guides edit, and a student's progress that any admin who can see
// the student may tick. The same data as the Student app's `utils/MusicData.dart`:
//  - `musicCurriculum/{instrumentId}`: one document per instrument (name, optional YouTube link, order, ordered checkpoints
//    `{id, title}`), every instrument and checkpoint with a STABLE id. Writable only by HODs and Guides (the rules).
//  - `musicProgress/{uid}`: `ticks` (checkpoint id -> who / when) and the student's own `others`. Progress is kept BY
//    CHECKPOINT ID, so a rename or a reorder keeps everyone's ticks, a deleted checkpoint stops counting, and a new one
//    makes a completed instrument incomplete again until it is ticked.

class MusicCheckpoint {
  const MusicCheckpoint({required this.id, required this.title});

  final String id;
  final String title;

  MusicCheckpoint copyWith({String? title}) => MusicCheckpoint(id: id, title: title ?? this.title);
}

class MusicInstrument {
  const MusicInstrument({required this.id, required this.name, this.link = '', this.order = 0, this.checkpoints = const []});

  final String id;
  final String name;
  final String link;
  final int order;
  final List<MusicCheckpoint> checkpoints;

  bool get hasLink => link.trim().isNotEmpty;

  static MusicInstrument? fromDoc(String id, Map<String, dynamic>? d) {
    if (d == null) return null;
    final name = (d['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;
    final raw = d['checkpoints'];
    final cps = <MusicCheckpoint>[
      if (raw is List)
        for (final c in raw)
          if (c is Map && (c['id'] ?? '').toString().isNotEmpty && (c['title'] ?? '').toString().trim().isNotEmpty)
            MusicCheckpoint(id: c['id'].toString(), title: c['title'].toString().trim()),
    ];
    final order = d['order'];
    return MusicInstrument(id: id, name: name, link: (d['link'] ?? '').toString().trim(), order: order is num ? order.toInt() : 0, checkpoints: cps);
  }

  static List<Map<String, Object?>> checkpointsToMaps(List<MusicCheckpoint> list) => [for (final c in list) {'id': c.id, 'title': c.title}];
}

/// Who ticked a checkpoint and when ("student" = the student, otherwise an admin's id).
class MusicTick {
  const MusicTick({required this.by, required this.byName, this.at});

  final String by;
  final String byName;
  final DateTime? at;

  bool get byStudent => by == 'student';
}

enum MusicLevel { basic, intermediate, expert }

extension MusicLevelX on MusicLevel {
  String get label => switch (this) { MusicLevel.basic => 'Basic', MusicLevel.intermediate => 'Intermediate', MusicLevel.expert => 'Expert' };
  static MusicLevel fromKey(Object? k) => MusicLevel.values.firstWhere((l) => l.name == k, orElse: () => MusicLevel.basic);
}

/// An instrument the student added themselves ("Others"); the guide only reads these.
class OtherInstrument {
  const OtherInstrument({required this.id, required this.name, required this.level});

  final String id;
  final String name;
  final MusicLevel level;
}

class MusicProgress {
  const MusicProgress({this.ticks = const {}, this.others = const []});

  final Map<String, MusicTick> ticks;
  final List<OtherInstrument> others;

  static const MusicProgress empty = MusicProgress();

  /// How many of [instrument]'s CURRENT checkpoints are ticked.
  int done(MusicInstrument instrument) => instrument.checkpoints.where((c) => ticks.containsKey(c.id)).length;

  bool completed(MusicInstrument instrument) => instrument.checkpoints.isNotEmpty && done(instrument) == instrument.checkpoints.length;

  static MusicProgress fromDoc(Map<String, dynamic>? d) {
    if (d == null) return empty;
    final ticks = <String, MusicTick>{};
    final rawTicks = d['ticks'];
    if (rawTicks is Map) {
      rawTicks.forEach((k, v) {
        if (v is! Map) return;
        final at = v['at'];
        ticks[k.toString()] = MusicTick(by: (v['by'] ?? 'student').toString(), byName: (v['byName'] ?? '').toString(), at: at is Timestamp ? at.toDate() : null);
      });
    }
    final others = <OtherInstrument>[];
    final rawOthers = d['others'];
    if (rawOthers is List) {
      for (final o in rawOthers) {
        if (o is Map && (o['id'] ?? '').toString().isNotEmpty && (o['name'] ?? '').toString().trim().isNotEmpty) {
          others.add(OtherInstrument(id: o['id'].toString(), name: o['name'].toString().trim(), level: MusicLevelX.fromKey(o['level'])));
        }
      }
    }
    return MusicProgress(ticks: ticks, others: others);
  }
}

/// A new stable id (`prefix` + time + random), for an instrument or a checkpoint added later.
String newMusicId(String prefix) => '$prefix-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

/// Where the curriculum and the progress live. The app uses [FirestoreMusicStore]; tests use the same class on a fake
/// database.
class FirestoreMusicStore {
  FirestoreMusicStore([FirebaseFirestore? firestore]) : _db = firestore ?? GuideDb.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _curriculum => _db.collection('musicCurriculum');

  // ------------------------------------------------------------------------------------------------- the curriculum
  /// The instruments in the HODs' order, live.
  Stream<List<MusicInstrument>> curriculum() => _curriculum.snapshots().map((snap) {
        final list = [
          for (final d in snap.docs)
            if (MusicInstrument.fromDoc(d.id, d.data()) case final i?) i,
        ];
        list.sort((a, b) {
          final byOrder = a.order.compareTo(b.order);
          return byOrder != 0 ? byOrder : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        return list;
      });

  /// One instrument, live (null once it is deleted).
  Stream<MusicInstrument?> instrument(String id) => _curriculum.doc(id).snapshots().map((s) => MusicInstrument.fromDoc(s.id, s.data()));

  /// Adds an instrument at the end of the list; returns its stable id.
  Future<String> addInstrument({required String name, String link = '', required int order}) async {
    final id = newMusicId('i');
    await _curriculum.doc(id).set({
      'name': name.trim(),
      'link': link.trim(),
      'order': order,
      'checkpoints': <Object?>[],
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  /// Renames and/or changes (or removes, with '') the link.
  Future<void> updateInstrument(String id, {String? name, String? link}) => _curriculum.doc(id).update({
        if (name != null) 'name': name.trim(),
        if (link != null) 'link': link.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  /// Deletes the instrument for everyone. The students' ticks stay in storage (kept by checkpoint id) but are no longer shown.
  Future<void> deleteInstrument(String id) => _curriculum.doc(id).delete();

  /// Writes the order of the instruments (the order of [ids] becomes 0, 1, 2 ...).
  Future<void> reorderInstruments(List<String> ids) async {
    final batch = _db.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update(_curriculum.doc(ids[i]), {'order': i, 'updatedAt': FieldValue.serverTimestamp()});
    }
    await batch.commit();
  }

  /// Changes the checkpoints of one instrument: [change] gets the list as it is NOW in the database (a transaction, so two
  /// admins editing at once never overwrite each other) and returns the new list.
  Future<void> editCheckpoints(String id, List<MusicCheckpoint> Function(List<MusicCheckpoint> current) change) {
    final ref = _curriculum.doc(id);
    return _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = MusicInstrument.fromDoc(id, snap.data())?.checkpoints ?? const <MusicCheckpoint>[];
      tx.update(ref, {'checkpoints': MusicInstrument.checkpointsToMaps(change([...current])), 'updatedAt': FieldValue.serverTimestamp()});
    });
  }

  // ------------------------------------------------------------------------------------------------ the progress
  Stream<MusicProgress> progress(String uid) => _db.collection('musicProgress').doc(uid).snapshots().map((s) => MusicProgress.fromDoc(s.data()));

  /// Ticks / unticks a checkpoint for the student. [by] is the admin's id; [byName] is shown subtly next to the tick.
  Future<void> setTick(String uid, String checkpointId, bool ticked, {required String by, required String byName}) async {
    final ref = _db.collection('musicProgress').doc(uid);
    if (ticked) {
      await ref.set({
        'uid': uid,
        'ticks': {
          checkpointId: {'by': by, 'byName': byName, 'at': FieldValue.serverTimestamp()},
        },
      }, SetOptions(merge: true));
    } else {
      try {
        await ref.update({'ticks.$checkpointId': FieldValue.delete()});
      } on FirebaseException catch (e) {
        if (e.code != 'not-found') rethrow;
      }
    }
  }
}
