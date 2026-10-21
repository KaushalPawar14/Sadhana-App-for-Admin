import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/BoysDetails.dart';
import 'package:folk_guide_app/Pages/MusicCurriculumPage.dart';
import 'package:folk_guide_app/Pages/StudentMusicPage.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/GuideDb.dart';
import 'package:folk_guide_app/utils/MusicData.dart';

import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

// MY MUSIC in the Guide app: the curriculum editor (HODs and Guides only; Enablers can only see and tick), live and by stable
// ids; and a student's progress page where the student and any admin who can see them tick (who and when shown subtly).

AdminProfile profile(String id, String role, {String team = ''}) => AdminProfile.fromMap({
      'id': id,
      'displayName': '$id Das',
      'role': role,
      'teamGuide': team,
      'email': '$id@x.org',
      'notificationPrefs': {},
      'notificationTypes': [],
      'admins': [],
    });

const roles = <String, String>{'H': 'HOD', 'G': 'GUIDE', 'M1': 'MALE_ENABLER', 'F1': 'FEMALE_ENABLER'};

Map<String, Object?> instr(String name, List<(String, String)> cps, {String link = '', int order = 0}) => {
      'name': name,
      'link': link,
      'order': order,
      'checkpoints': [for (final (id, title) in cps) {'id': id, 'title': title}],
    };

Future<FakeFirebaseFirestore> world() async {
  final db = FakeFirebaseFirestore();
  await db.doc('musicCurriculum/kartal').set(instr('Kartal', [('k1', 'Hold it properly'), ('k2', 'Slow beat'), ('k3', 'Fast beat')], link: 'https://youtu.be/kartal', order: 0));
  await db.doc('musicCurriculum/harmonium').set(instr('Harmonium', [('h1', 'Learn the keys'), ('h2', 'Play Sa Re Ga Ma')], order: 1));
  await db.doc('musicCurriculum/womper').set(instr('Womper', [('w1', 'Learning Womper')], order: 2));
  await db.doc('musicProgress/s1').set({
    'uid': 's1',
    'ticks': {
      'k1': {'by': 'student', 'byName': '', 'at': Timestamp.fromDate(DateTime(2026, 10, 12))},
      'k2': {'by': 'G', 'byName': 'G Das', 'at': Timestamp.fromDate(DateTime(2026, 10, 14))},
      'h1': {'by': 'M1', 'byName': 'M1 Das', 'at': Timestamp.fromDate(DateTime(2026, 10, 15))},
      'h2': {'by': 'student', 'byName': ''},
    },
    'others': [
      {'id': 'o1', 'name': 'Flute', 'level': 'intermediate'},
    ],
  });
  return db;
}

Future<FakeFirebaseFirestore> open(WidgetTester tester, Widget screen, {String who = 'H', FakeFirebaseFirestore? db, double scale = 1.0, bool dark = false}) async {
  await prepareApp(tester, seeded: false);
  final fs = db ?? await world();
  GuideDb.useForTests(fs);
  AdminProfileProvider.instance.debugSet(profile(who, roles[who]!, team: who == 'M1' ? 'G' : ''));
  await pumpScreen(tester, screen, scale: scale, dark: dark);
  await settle(tester);
  return fs;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await letDataArrive(tester, frames: 5);
  }
}

Future<void> reveal(WidgetTester tester, Finder f, {String list = 'student-music-list'}) async {
  if (f.evaluate().isEmpty) {
    final scrollable = find.byType(Scrollable).first;
    try {
      await tester.scrollUntilVisible(f, 200, scrollable: scrollable, maxScrolls: 40);
    } catch (_) {
      await tester.scrollUntilVisible(f, -200, scrollable: scrollable, maxScrolls: 40);
    }
  } else {
    await tester.ensureVisible(f);
  }
  await tester.pump();
}

Future<void> tap(WidgetTester tester, String key) async {
  final f = find.byKey(ValueKey(key));
  await reveal(tester, f);
  await tester.tap(f);
  await settle(tester);
}

Future<void> fill(WidgetTester tester, String key, String text) async {
  await tester.enterText(find.byKey(ValueKey(key)), text);
  await tester.pump();
}

Future<Map<String, dynamic>> doc(FakeFirebaseFirestore db, String path) async => (await db.doc(path).get()).data() ?? {};
List<String> cpIds(Map<String, dynamic> d) => [for (final c in (d['checkpoints'] as List)) (c as Map)['id'].toString()];
List<String> cpTitles(Map<String, dynamic> d) => [for (final c in (d['checkpoints'] as List)) (c as Map)['title'].toString()];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  tearDown(() {
    GuideDb.useForTests(null);
    AdminProfileProvider.instance.debugSet(null);
  });

  // ------------------------------------------------------------------------------------------------ who may edit
  group('only HODs and Guides edit the curriculum', () {
    test('mayEdit by role: HOD and Guide yes; Male and Female Enabler no; nobody no', () {
      expect(MusicCurriculumPage.mayEdit(profile('H', 'HOD')), isTrue);
      expect(MusicCurriculumPage.mayEdit(profile('G', 'GUIDE')), isTrue);
      expect(MusicCurriculumPage.mayEdit(profile('M1', 'MALE_ENABLER')), isFalse);
      expect(MusicCurriculumPage.mayEdit(profile('F1', 'FEMALE_ENABLER')), isFalse);
      expect(MusicCurriculumPage.mayEdit(null), isFalse);
    });

    for (final who in ['H', 'G']) {
      testWidgets('${roles[who]}: the "Music curriculum" card is in the Tasks tab and opens the editor', (tester) async {
        await open(tester, const Scaffold(body: AdminControlPage()), who: who);
        await tester.scrollUntilVisible(find.byKey(const ValueKey('music-curriculum-card')), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Music curriculum'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('music-curriculum-card')));
        await settle(tester);
        expect(find.byType(MusicCurriculumPage), findsOneWidget);
        expect(find.byKey(const ValueKey('music-add-instrument')), findsOneWidget);
      });
    }

    for (final who in ['M1', 'F1']) {
      testWidgets('${roles[who]}: the card is hidden in the Tasks tab, and the editor itself refuses', (tester) async {
        await open(tester, const Scaffold(body: AdminControlPage()), who: who);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -2000));
        await settle(tester);
        expect(find.byKey(const ValueKey('music-curriculum-card')), findsNothing);
        expect(find.text('Music curriculum'), findsNothing);
        await open(tester, const MusicCurriculumPage(), who: who);
        expect(find.byKey(const ValueKey('music-not-allowed')), findsOneWidget);
        expect(find.byKey(const ValueKey('music-add-instrument')), findsNothing);
      });
    }
  });

  // ------------------------------------------------------------------------------------------------ the list
  group('the instruments list', () {
    testWidgets('in the stored order, each with its checkpoint count; live when another admin edits', (tester) async {
      final db = await open(tester, const MusicCurriculumPage());
      final tops = ['kartal', 'harmonium', 'womper'].map((i) => tester.getTopLeft(find.byKey(ValueKey('music-row-$i'))).dy).toList();
      expect(tops, [...tops]..sort());
      expect(find.text('3 checkpoints · has a link'), findsOneWidget);
      expect(find.text('1 checkpoint'), findsOneWidget);
      await db.doc('musicCurriculum/womper').update({'name': 'Womper (new)'});
      await settle(tester);
      expect(find.text('Womper (new)'), findsOneWidget);
    });

    testWidgets('Add instrument: a name is required, a link must be a web address; it is created with a stable id at the end, then opens', (tester) async {
      final db = await open(tester, const MusicCurriculumPage());
      await tap(tester, 'music-add-instrument');
      await tap(tester, 'music-new-save');
      expect(find.text('Please write the instrument name'), findsOneWidget);
      await fill(tester, 'music-new-name', 'Flute');
      await fill(tester, 'music-new-link', 'not a link');
      await tap(tester, 'music-new-save');
      expect(find.text('Please enter a full web link (https://…)'), findsOneWidget);
      await fill(tester, 'music-new-link', 'https://youtu.be/flute');
      await tap(tester, 'music-new-save');
      final all = (await db.collection('musicCurriculum').get()).docs;
      expect(all.length, 4);
      final created = all.firstWhere((d) => d.data()['name'] == 'Flute');
      expect(created.id.startsWith('i-'), isTrue, reason: 'a stable generated id, not the name');
      expect(created.data()['link'], 'https://youtu.be/flute');
      expect(created.data()['order'], 3, reason: 'at the end');
      expect(created.data()['checkpoints'], isEmpty);
      expect(find.byType(MusicInstrumentEditorPage), findsOneWidget, reason: 'it opens to add checkpoints');
    });

    testWidgets('a link is optional when adding', (tester) async {
      final db = await open(tester, const MusicCurriculumPage());
      await tap(tester, 'music-add-instrument');
      await fill(tester, 'music-new-name', '  Dholak ');
      await tap(tester, 'music-new-save');
      final created = (await db.collection('musicCurriculum').get()).docs.firstWhere((d) => d.data()['name'] == 'Dholak');
      expect(created.data()['link'], '');
    });

    testWidgets('Cancel adds nothing', (tester) async {
      final db = await open(tester, const MusicCurriculumPage());
      await tap(tester, 'music-add-instrument');
      await fill(tester, 'music-new-name', 'Flute');
      await tap(tester, 'music-new-cancel');
      expect((await db.collection('musicCurriculum').get()).docs.length, 3);
    });

    testWidgets('reorder by dragging: the new order is written (0, 1, 2 ...) and the ids stay', (tester) async {
      final db = await open(tester, const MusicCurriculumPage());
      // drag Womper (last) to the top
      final handle = find.byKey(const ValueKey('music-drag-womper'));
      final start = tester.getCenter(handle);
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, -260));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await settle(tester);
      expect((await doc(db, 'musicCurriculum/womper'))['order'], 0);
      expect((await doc(db, 'musicCurriculum/kartal'))['order'], 1);
      expect((await doc(db, 'musicCurriculum/harmonium'))['order'], 2);
      expect((await db.collection('musicCurriculum').get()).docs.map((d) => d.id).toSet(), {'kartal', 'harmonium', 'womper'});
    });
  });

  // ------------------------------------------------------------------------------------------------ the editor
  group('editing one instrument', () {
    Future<FakeFirebaseFirestore> editor(WidgetTester tester, {String id = 'kartal', double scale = 1.0, bool dark = false, String who = 'H'}) =>
        open(tester, MusicInstrumentEditorPage(instrumentId: id), who: who, scale: scale, dark: dark);

    testWidgets('rename keeps the checkpoints and every student\'s ticks', (tester) async {
      final db = await editor(tester);
      final before = await doc(db, 'musicProgress/s1');
      await tap(tester, 'music-edit-name');
      await fill(tester, 'music-text-field', '  Karatalas ');
      await tap(tester, 'music-text-save');
      final d = await doc(db, 'musicCurriculum/kartal');
      expect(d['name'], 'Karatalas');
      expect(cpIds(d), ['k1', 'k2', 'k3']);
      expect(await doc(db, 'musicProgress/s1'), before, reason: 'nobody\'s ticks were touched');
      expect(find.text('Karatalas'), findsOneWidget);
    });

    testWidgets('an empty name is refused', (tester) async {
      final db = await editor(tester);
      await tap(tester, 'music-edit-name');
      await fill(tester, 'music-text-field', '   ');
      await tap(tester, 'music-text-save');
      expect(find.text('Please write something'), findsOneWidget);
      expect((await doc(db, 'musicCurriculum/kartal'))['name'], 'Kartal');
    });

    testWidgets('change the link, refuse a bad one, remove it', (tester) async {
      final db = await editor(tester);
      await tap(tester, 'music-edit-link');
      await fill(tester, 'music-text-field', 'ftp://nope');
      await tap(tester, 'music-text-save');
      expect(find.text('Please enter a full web link (https://…)'), findsOneWidget);
      await fill(tester, 'music-text-field', ' https://youtu.be/new ');
      await tap(tester, 'music-text-save');
      expect((await doc(db, 'musicCurriculum/kartal'))['link'], 'https://youtu.be/new');
      await tap(tester, 'music-remove-link');
      expect((await doc(db, 'musicCurriculum/kartal'))['link'], '');
      expect(find.text('No link'), findsOneWidget);
      expect(find.byKey(const ValueKey('music-remove-link')), findsNothing);
    });

    testWidgets('add a checkpoint (a new stable id at the end); rename one (same id)', (tester) async {
      final db = await editor(tester);
      await tap(tester, 'music-add-cp');
      await fill(tester, 'music-text-field', ' Two tal: slow beat ');
      await tap(tester, 'music-text-save');
      var d = await doc(db, 'musicCurriculum/kartal');
      expect(cpTitles(d), ['Hold it properly', 'Slow beat', 'Fast beat', 'Two tal: slow beat']);
      expect(cpIds(d).sublist(0, 3), ['k1', 'k2', 'k3']);
      expect(cpIds(d).last.startsWith('cp-'), isTrue);
      await tap(tester, 'music-cp-edit-k2');
      await fill(tester, 'music-text-field', 'Slow beat (slowly)');
      await tap(tester, 'music-text-save');
      d = await doc(db, 'musicCurriculum/kartal');
      expect(cpTitles(d)[1], 'Slow beat (slowly)');
      expect(cpIds(d)[1], 'k2', reason: 'renaming keeps the id, so the ticks stay');
      expect(((await doc(db, 'musicProgress/s1'))['ticks'] as Map).containsKey('k2'), isTrue);
    });

    testWidgets('delete a checkpoint asks first; Cancel keeps it; Delete removes it (the old ticks stay in storage)', (tester) async {
      final db = await editor(tester);
      await tap(tester, 'music-cp-delete-k3');
      expect(find.byKey(const ValueKey('music-delete-checkpoint-dialog')), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect(cpIds(await doc(db, 'musicCurriculum/kartal')), ['k1', 'k2', 'k3']);
      await tap(tester, 'music-cp-delete-k1');
      await tap(tester, 'music-confirm-yes');
      expect(cpIds(await doc(db, 'musicCurriculum/kartal')), ['k2', 'k3']);
      expect(((await doc(db, 'musicProgress/s1'))['ticks'] as Map).containsKey('k1'), isTrue, reason: 'kept in storage, just not counted');
    });

    testWidgets('reorder the checkpoints by dragging: the order changes, the ids stay', (tester) async {
      final db = await editor(tester);
      await reveal(tester, find.byKey(const ValueKey('music-cp-drag-k3')));
      final start = tester.getCenter(find.byKey(const ValueKey('music-cp-drag-k3')));
      final g = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(0, -30));
        await tester.pump(const Duration(milliseconds: 60));
      }
      await g.up();
      await settle(tester);
      final d = await doc(db, 'musicCurriculum/kartal');
      expect(cpIds(d).toSet(), {'k1', 'k2', 'k3'});
      expect(cpIds(d).first, 'k3', reason: 'the last one moved to the top');
      expect(cpTitles(d).first, 'Fast beat');
    });

    testWidgets('delete the instrument: it asks, then it is gone for everyone (the students\' ticks stay in storage)', (tester) async {
      final db = await editor(tester);
      await tap(tester, 'music-delete-instrument');
      expect(find.text('Delete Kartal?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle(tester);
      expect((await db.doc('musicCurriculum/kartal').get()).exists, isTrue);
      await tap(tester, 'music-delete-instrument');
      await tap(tester, 'music-confirm-yes');
      expect((await db.doc('musicCurriculum/kartal').get()).exists, isFalse);
      expect(((await doc(db, 'musicProgress/s1'))['ticks'] as Map).keys, containsAll(['k1', 'k2']), reason: 'kept in storage');
    });

    testWidgets('live: an edit by another admin shows at once; a deleted instrument says so', (tester) async {
      final db = await editor(tester);
      await db.doc('musicCurriculum/kartal').update({
        'checkpoints': [
          {'id': 'k1', 'title': 'Changed elsewhere'},
        ],
      });
      await settle(tester);
      expect(find.text('1. Changed elsewhere'), findsOneWidget);
      await db.doc('musicCurriculum/kartal').delete();
      await settle(tester);
      expect(find.byKey(const ValueKey('music-instrument-gone')), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------------------------------------ the store (the data rules)
  group('the store keeps progress by checkpoint id', () {
    test('editCheckpoints works from what is in the database NOW (two admins editing at once do not overwrite each other)', () async {
      final db = await world();
      GuideDb.useForTests(db);
      final store = FirestoreMusicStore(db);
      await store.editCheckpoints('kartal', (cur) => [...cur, const MusicCheckpoint(id: 'a', title: 'A')]);
      await store.editCheckpoints('kartal', (cur) => [...cur, const MusicCheckpoint(id: 'b', title: 'B')]);
      expect(cpIds(await doc(db, 'musicCurriculum/kartal')), ['k1', 'k2', 'k3', 'a', 'b']);
    });

    test('a rename / reorder / delete / add changes the completion of a student the way the spec says', () async {
      final db = await world();
      final store = FirestoreMusicStore(db);
      final inst = (await store.curriculum().first).firstWhere((i) => i.id == 'harmonium');
      final p = await store.progress('s1').first;
      expect(p.completed(inst), isTrue, reason: 'h1 + h2 are both ticked');
      await store.editCheckpoints('harmonium', (cur) => [cur[1].copyWith(title: 'Renamed'), cur[0]]);
      var now = (await store.curriculum().first).firstWhere((i) => i.id == 'harmonium');
      expect(p.completed(now), isTrue, reason: 'rename + reorder keep the ticks');
      await store.editCheckpoints('harmonium', (cur) => [...cur, const MusicCheckpoint(id: 'h3', title: 'New')]);
      now = (await store.curriculum().first).firstWhere((i) => i.id == 'harmonium');
      expect(p.completed(now), isFalse, reason: 'a new checkpoint makes it incomplete again');
      await store.editCheckpoints('harmonium', (cur) => [for (final c in cur) if (c.id != 'h3') c]);
      now = (await store.curriculum().first).firstWhere((i) => i.id == 'harmonium');
      expect(p.completed(now), isTrue, reason: 'deleting it makes it complete again');
    });

    test('tick and untick write the admin\'s id and name; the rest of the document is untouched', () async {
      final db = await world();
      final store = FirestoreMusicStore(db);
      await store.setTick('s1', 'k3', true, by: 'H', byName: 'H Das');
      var d = await doc(db, 'musicProgress/s1');
      expect(((d['ticks'] as Map)['k3'] as Map)['by'], 'H');
      expect(((d['ticks'] as Map)['k3'] as Map)['byName'], 'H Das');
      expect(((d['ticks'] as Map)['k3'] as Map)['at'], isNotNull);
      expect((d['others'] as List).length, 1);
      await store.setTick('s1', 'k3', false, by: 'H', byName: 'H Das');
      d = await doc(db, 'musicProgress/s1');
      expect((d['ticks'] as Map).containsKey('k3'), isFalse);
      expect((d['ticks'] as Map).length, 4);
      await store.setTick('nobody', 'k3', false, by: 'H', byName: 'H Das'); // nothing there: a quiet no-op
      // ticking before the student has any document creates it with ticks only
      await store.setTick('fresh', 'k1', true, by: 'G', byName: 'G Das');
      final fresh = await doc(db, 'musicProgress/fresh');
      expect(fresh.keys.toSet(), {'uid', 'ticks'});
    });
  });

  // ------------------------------------------------------------------------------------------------ a student's progress
  group('a student\'s progress page', () {
    Future<FakeFirebaseFirestore> page(WidgetTester tester, {String who = 'H', bool canTick = true, double scale = 1.0, bool dark = false, FakeFirebaseFirestore? db}) =>
        open(tester, StudentMusicPage(studentUid: 's1', studentName: 'Arjun Kumar', canTick: canTick), who: who, scale: scale, dark: dark, db: db);

    testWidgets('the curriculum with the student\'s ticks: counts, the Completed badge, in the HODs\' order', (tester) async {
      await page(tester);
      expect(find.text('Arjun Kumar · Music'), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const ValueKey('student-music-count-kartal'))).data, '2 of 3');
      expect(tester.widget<Text>(find.byKey(const ValueKey('student-music-count-harmonium'))).data, '2 of 2');
      expect(tester.widget<Text>(find.byKey(const ValueKey('student-music-count-womper'))).data, '0 of 1');
      expect(find.descendant(of: find.byKey(const ValueKey('student-music-instrument-harmonium')), matching: find.byKey(const ValueKey('student-music-completed'))), findsOneWidget);
      expect(find.byKey(const ValueKey('student-music-completed')), findsOneWidget, reason: 'only Harmonium is complete');
      final tops = ['kartal', 'harmonium', 'womper'].map((i) => tester.getTopLeft(find.byKey(ValueKey('student-music-instrument-$i'))).dy).toList();
      expect(tops, [...tops]..sort());
    });

    testWidgets('who ticked and when, subtly: Student, You (this admin), another admin\'s name', (tester) async {
      await page(tester, who: 'G');
      await tap(tester, 'student-music-header-kartal');
      expect(tester.widget<Text>(find.byKey(const ValueKey('student-music-by-k1'))).data, 'Student · 12 Oct');
      expect(tester.widget<Text>(find.byKey(const ValueKey('student-music-by-k2'))).data, 'You · 14 Oct');
      await tap(tester, 'student-music-header-harmonium');
      expect(tester.widget<Text>(find.byKey(const ValueKey('student-music-by-h1'))).data, 'M1 Das · 15 Oct');
      expect(tester.widget<Text>(find.byKey(const ValueKey('student-music-by-h2'))).data, 'Student');
    });

    for (final who in ['H', 'G', 'M1', 'F1']) {
      testWidgets('${roles[who]} can tick and untick for the student (no approval); the tick carries the admin and the time', (tester) async {
        final db = await page(tester, who: who);
        await tap(tester, 'student-music-header-womper');
        await tap(tester, 'student-music-cp-w1');
        var ticks = (await doc(db, 'musicProgress/s1'))['ticks'] as Map;
        expect((ticks['w1'] as Map)['by'], who);
        expect((ticks['w1'] as Map)['byName'], '$who Das');
        expect((ticks['w1'] as Map)['at'], isNotNull);
        expect(tester.widget<Text>(find.byKey(const ValueKey('student-music-count-womper'))).data, '1 of 1');
        expect(find.byKey(const ValueKey('student-music-completed')), findsNWidgets(2));
        await tap(tester, 'student-music-cp-w1');
        ticks = (await doc(db, 'musicProgress/s1'))['ticks'] as Map;
        expect(ticks.containsKey('w1'), isFalse);
        expect(find.byKey(const ValueKey('student-music-completed')), findsOneWidget);
      });
    }

    testWidgets('an admin can untick the STUDENT\'s own tick, and the student\'s tick is shown as theirs', (tester) async {
      final db = await page(tester);
      await tap(tester, 'student-music-header-kartal');
      await tap(tester, 'student-music-cp-k1');
      expect(((await doc(db, 'musicProgress/s1'))['ticks'] as Map).containsKey('k1'), isFalse);
    });

    testWidgets('a viewer who may not act (outside the scope) sees the progress but cannot tick', (tester) async {
      final db = await page(tester, canTick: false);
      expect(find.text('You can see this progress but not change it.'), findsOneWidget);
      await tap(tester, 'student-music-header-womper');
      await tap(tester, 'student-music-cp-w1');
      expect(((await doc(db, 'musicProgress/s1'))['ticks'] as Map).containsKey('w1'), isFalse);
    });

    testWidgets('the student\'s own ticks and the HOD\'s edits arrive live', (tester) async {
      final db = await page(tester);
      await db.doc('musicProgress/s1').update({'ticks.w1': {'by': 'student', 'byName': ''}});
      await settle(tester);
      expect(tester.widget<Text>(find.byKey(const ValueKey('student-music-count-womper'))).data, '1 of 1');
      await db.doc('musicCurriculum/womper').update({
        'checkpoints': [
          {'id': 'w1', 'title': 'Learning Womper'},
          {'id': 'w2', 'title': 'Advanced Womper'},
        ],
      });
      await settle(tester);
      expect(tester.widget<Text>(find.byKey(const ValueKey('student-music-count-womper'))).data, '1 of 2', reason: 'a new checkpoint: incomplete again');
    });

    testWidgets('the student\'s own instruments (Others) are listed, read only', (tester) async {
      await page(tester);
      await reveal(tester, find.byKey(const ValueKey('student-music-other-o1')));
      expect(find.text('Flute'), findsOneWidget);
      expect(find.text('Intermediate'), findsOneWidget);
    });

    testWidgets('no curriculum yet: a plain message', (tester) async {
      await page(tester, db: FakeFirebaseFirestore());
      expect(find.byKey(const ValueKey('student-music-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('student-music-others-empty')), findsOneWidget);
    });
  });

  group('the Music card on the student\'s profile', () {
    testWidgets('says how many instruments are completed and opens the progress page', (tester) async {
      await open(tester, const Scaffold(body: Padding(padding: EdgeInsets.all(20), child: StudentMusicCard(studentUid: 's1', studentName: 'Arjun Kumar'))));
      expect(find.text('Music'), findsOneWidget);
      expect(find.text('1 of 3 instruments completed'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('student-music-card')));
      await settle(tester);
      expect(find.byType(StudentMusicPage), findsOneWidget);
    });

    test('wiring: the student profile has a "Music" section, with the viewer\'s scope deciding who may tick', () {
      expect(File('lib/Pages/StudentProfilePage.dart').readAsStringSync(), allOf(contains('"Music"'), contains('StudentMusicCard('), contains('canTick: canAct')));
      expect(File('lib/Pages/BoysDetails.dart').readAsStringSync(), contains('MusicCurriculumPage.mayEdit(AdminProfileProvider.current)'));
    });
  });

  // ------------------------------------------------------------------------------------------------ look
  for (final dark in [false, true]) {
    for (final scale in kScales) {
      final mode = '${dark ? 'dark' : 'light'}, text $scale';
      testWidgets('$mode: the list, the editor and the progress page fit, targets >= 48 dp', (tester) async {
        await open(tester, const MusicCurriculumPage(), scale: scale, dark: dark);
        expectNoOverflow(tester);
        for (final k in ['music-add-instrument', 'music-drag-kartal']) {
          final r = tester.getRect(find.byKey(ValueKey(k)));
          expect(r.height, greaterThanOrEqualTo(47.5), reason: k);
          expect(r.right, lessThanOrEqualTo(360.5), reason: k);
        }
        await open(tester, const MusicInstrumentEditorPage(instrumentId: 'kartal'), scale: scale, dark: dark);
        expectNoOverflow(tester);
        for (final k in ['music-edit-name', 'music-edit-link', 'music-cp-edit-k1', 'music-cp-delete-k1', 'music-cp-drag-k1', 'music-add-cp']) {
          await reveal(tester, find.byKey(ValueKey(k)));
          final r = tester.getRect(find.byKey(ValueKey(k)));
          expect(r.height, greaterThanOrEqualTo(47.5), reason: k);
          expect(r.right, lessThanOrEqualTo(360.5), reason: k);
        }
        await reveal(tester, find.byKey(const ValueKey('music-delete-instrument')));
        expectNoOverflow(tester);
        await open(tester, const StudentMusicPage(studentUid: 's1', studentName: 'Arjun Kumar'), scale: scale, dark: dark);
        for (final i in ['kartal', 'harmonium', 'womper']) {
          await tap(tester, 'student-music-header-$i');
        }
        expectNoOverflow(tester);
        for (final k in ['student-music-cp-k1', 'student-music-cp-h2', 'student-music-cp-w1']) {
          await reveal(tester, find.byKey(ValueKey(k)));
          expect(tester.getRect(find.byKey(ValueKey(k))).height, greaterThanOrEqualTo(47.5), reason: k);
        }
      });
    }
  }
}
