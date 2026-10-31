import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AdminManager.dart';
import 'package:folk_guide_app/Pages/NonPlayInstallScreen.dart';
import 'package:folk_guide_app/Pages/NotificationSettings.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/ColorProvider.dart';
import 'package:folk_guide_app/utils/InstallSource.dart';
import 'package:folk_guide_app/utils/StudentScope.dart';
import 'package:folk_guide_app/widgets/GuideSurface.dart';
import 'package:provider/provider.dart';

const _types = [
  {'key': 'association_request', 'label': 'Meeting requests', 'scope': 'student'},
  {'key': 'birthday', 'label': 'Birthdays', 'scope': 'student'},
  {'key': 'calendar_reminder', 'label': 'Calendar reminders', 'scope': 'general'},
];

Map<String, dynamic> profileMap(String id, String role,
        {String team = '', List<Map<String, dynamic>> admins = const [], Map<String, dynamic>? prefs}) =>
    {
      'id': id,
      'displayName': '$id Prabhu',
      'role': role,
      'teamGuide': team,
      'email': '$id@x.org',
      'notificationPrefs': prefs ?? {},
      'notificationTypes': _types,
      'admins': admins,
    };

AdminProfile profile(String id, String role,
        {String team = '', List<Map<String, dynamic>> admins = const [], Map<String, dynamic>? prefs}) =>
    AdminProfile.fromMap(profileMap(id, role, team: team, admins: admins, prefs: prefs));

Map<String, dynamic> a(String id, String role, {String team = ''}) =>
    {'id': id, 'displayName': '$id Das', 'role': role, 'teamGuide': team};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('roles', () {
    test('gender is implied by role; wire strings match the backend', () {
      expect(AdminRole.hod.gender, 'male');
      expect(AdminRole.guide.gender, 'male');
      expect(AdminRole.maleEnabler.gender, 'male');
      expect(AdminRole.femaleEnabler.gender, 'female');
      expect(AdminRoleX.fromWire('MALE_ENABLER'), AdminRole.maleEnabler);
      expect(AdminRoleX.fromWire('nonsense'), AdminRole.guide, reason: 'least privilege');
      expect(AdminRole.femaleEnabler.wire, 'FEMALE_ENABLER');
    });

    test('who may add which role (approved matrix)', () {
      expect(rolesThatCanBeAddedBy(AdminRole.hod), AdminRole.values);
      expect(rolesThatCanBeAddedBy(AdminRole.guide), [AdminRole.guide, AdminRole.maleEnabler]);
      expect(rolesThatCanBeAddedBy(AdminRole.maleEnabler), [AdminRole.maleEnabler]);
      expect(rolesThatCanBeAddedBy(AdminRole.femaleEnabler), [AdminRole.femaleEnabler]);
    });

    test('profile parsing, team lookup and the Guide default for Male Enabler switches', () {
      final p = profile('AMHD', 'GUIDE', admins: [
        a('AMHD', 'GUIDE'),
        a('ME1', 'MALE_ENABLER', team: 'AMHD'),
        a('ME2', 'MALE_ENABLER', team: 'FOLK'),
      ]);
      expect(p.isGuide, isTrue);
      expect(p.isHod, isFalse);
      expect(p.myMaleEnablers.map((e) => e.id), ['ME1']);
      expect(p.adminById('ME2')?.displayName, 'ME2 Das');
      expect(p.notificationTypes.length, 3);
      expect(p.groupOn('own'), isTrue);
      expect(p.groupOn('unassigned'), isTrue);
      expect(p.groupOn('admin:ME1'), isFalse, reason: 'a Guide opts in per Male Enabler (default OFF)');
      expect(p.typeOn('birthday'), isTrue);
      final saved = profile('AMHD', 'GUIDE', prefs: {
        'groups': {'admin:ME1': true, 'own': false},
        'types': {'birthday': false},
      });
      expect(saved.groupOn('admin:ME1'), isTrue);
      expect(saved.groupOn('own'), isFalse);
      expect(saved.typeOn('birthday'), isFalse);
      // the HOD's per-admin switches default ON
      expect(profile('H', 'HOD').groupOn('admin:X'), isTrue);
    });
  });

  group('StudentScope.canManage mirrors the server rule', () {
    StudentRef s(String g, String guide, String team) => StudentRef(uid: 'u', guideId: guide, teamGuide: team, gender: g);
    test('HOD manages everyone', () {
      final scope = StudentScope(profile('H', 'HOD'));
      for (final st in [s('male', 'A', 'A'), s('female', 'F', ''), s('male', '', ''), s('female', '', '')]) {
        expect(scope.canManage(st), isTrue);
      }
    });
    test('Guide: own, team and unassigned males only', () {
      final scope = StudentScope(profile('G', 'GUIDE'));
      expect(scope.canManage(s('male', 'G', 'G')), isTrue);
      expect(scope.canManage(s('male', 'ME1', 'G')), isTrue, reason: "his Male Enabler's student");
      expect(scope.canManage(s('male', '', '')), isTrue);
      expect(scope.canManage(s('male', 'OTHER', 'OTHER')), isFalse);
      expect(scope.canManage(s('male', 'ME9', '')), isFalse, reason: 'teamless enabler: HOD only');
      expect(scope.canManage(s('female', '', '')), isFalse);
      expect(scope.canManage(s('female', 'F1', '')), isFalse);
    });
    test('Male Enabler: own and unassigned males; not his Guide\'s students', () {
      final scope = StudentScope(profile('E', 'MALE_ENABLER', team: 'G'));
      expect(scope.canManage(s('male', 'E', 'G')), isTrue);
      expect(scope.canManage(s('male', '', '')), isTrue);
      expect(scope.canManage(s('male', 'G', 'G')), isFalse);
      expect(scope.canManage(s('female', '', '')), isFalse);
    });
    test('Female Enabler: own and unassigned females only', () {
      final scope = StudentScope(profile('F', 'FEMALE_ENABLER'));
      expect(scope.canManage(s('female', 'F', '')), isTrue);
      expect(scope.canManage(s('female', '', '')), isTrue);
      expect(scope.canManage(s('female', 'F2', '')), isFalse);
      expect(scope.canManage(s('male', '', '')), isFalse);
    });
    test('StudentRef reads a users document defensively', () {
      final r = StudentRef.fromUser('u1', {'guideId': ' AMHD ', 'teamGuide': 'AMHD', 'gender': 'Female'});
      expect(r.guideId, 'AMHD');
      expect(r.gender, 'female');
      expect(StudentRef.fromUser('u2', null).guideId, '');
      expect(StudentRef.fromUser('u2', {'gender': 'x'}).gender, '');
    });
  });

  group('notification switches by role (approved design)', () {
    List<String> labels(AdminProfile p) => groupSwitchesFor(p).map((g) => g.label).toList();
    List<String> keys(AdminProfile p) => groupSwitchesFor(p).map((g) => g.key).toList();

    test('HOD: one per admin plus unassigned', () {
      final p = profile('H', 'HOD', admins: [a('H', 'HOD'), a('G', 'GUIDE'), a('F', 'FEMALE_ENABLER')]);
      expect(keys(p), ['own', 'admin:G', 'admin:F', 'unassigned']);
      expect(labels(p), ['My students', "G Das's students", "F Das's students", 'Unassigned students']);
    });
    test('Guide: mine, one per Male Enabler on his team, unassigned male', () {
      final p = profile('G', 'GUIDE', admins: [a('G', 'GUIDE'), a('ME1', 'MALE_ENABLER', team: 'G'), a('ME2', 'MALE_ENABLER', team: 'X')]);
      expect(keys(p), ['own', 'admin:ME1', 'unassigned']);
      expect(labels(p).last, 'Unassigned male students');
    });
    test('Male Enabler and Female Enabler', () {
      expect(labels(profile('E', 'MALE_ENABLER')), ['My students', 'Unassigned male students']);
      expect(labels(profile('F', 'FEMALE_ENABLER')), ['My students', 'Unassigned female students']);
    });
  });

  group('HierarchyApi', () {
    test('getAdminProfile returns null for a non-admin, rethrows real failures', () async {
      final notAdmin = HierarchyApi((n, d) async => throw HierarchyException('permission-denied', 'no'));
      expect(await notAdmin.getAdminProfile(), isNull);
      final down = HierarchyApi((n, d) async => throw HierarchyException('unavailable', 'offline'));
      expect(() => down.getAdminProfile(), throwsA(isA<HierarchyException>()));
    });

    test('requests carry exactly the documented fields', () async {
      final calls = <String, Map<String, dynamic>>{};
      final api = HierarchyApi((n, d) async {
        calls[n] = d;
        if (n == 'removeAdmin') return {'studentCount': 3, 'teamlessEnablers': ['ME1'], 'removed': false};
        if (n == 'addAdmin') return {'admin': a('NEW', 'GUIDE')};
        return {};
      });
      await api.assignStudent(studentId: 's', toGuideId: '', boardId: 'b', columnId: 'c', order: 2);
      expect(calls['assignStudent'], {'studentId': 's', 'toGuideId': '', 'boardId': 'b', 'columnId': 'c', 'order': 2});
      await api.assignStudent(studentId: 's', toGuideId: 'G');
      expect(calls['assignStudent'], {'studentId': 's', 'toGuideId': 'G'});
      final r = await api.removeAdmin('AMHD', dryRun: true);
      expect(r.studentCount, 3);
      expect(r.teamlessEnablers, ['ME1']);
      expect(calls['removeAdmin'], {'id': 'AMHD', 'dryRun': true});
      await api.addAdmin(name: 'NEW', email: 'n@x.org', role: AdminRole.maleEnabler, displayName: 'New', teamGuide: 'G');
      expect(calls['addAdmin'], {'name': 'NEW', 'email': 'n@x.org', 'role': 'MALE_ENABLER', 'displayName': 'New', 'teamGuide': 'G'});
      await api.saveNotificationPrefs(groups: {'own': false}, types: {'birthday': true});
      expect(calls['saveNotificationPrefs'], {'groups': {'own': false}, 'types': {'birthday': true}});
      await api.registerAdminToken('tok');
      expect(calls['registerAdminToken'], {'token': 'tok'});
      await api.sendStudentNotification({'kind': 'submission_nudge', 'studentUid': 'u'});
      expect(calls['sendStudentNotification'], {'kind': 'submission_nudge', 'studentUid': 'u'});
    });
  });

  group('Notifications page', () {
    Future<void> pump(WidgetTester tester, AdminProfile p, HierarchyApi api) async {
      AdminProfileProvider.instance.debugSet(p);
      await tester.binding.setSurfaceSize(const Size(360, 900));
      await tester.pumpWidget(ChangeNotifierProvider<ColorProvider>(
        create: (_) => ColorProvider(),
        child: MaterialApp(home: NotificationSettingsPage(api: api)),
      ));
      await tester.pump();
    }

    testWidgets('Guide sees the designed switches with the designed defaults, and saves exactly what is shown', (tester) async {
      Map<String, dynamic>? sent;
      final api = HierarchyApi((n, d) async {
        sent = d;
        return {};
      });
      await pump(tester, profile('G', 'GUIDE', admins: [a('G', 'GUIDE'), a('ME1', 'MALE_ENABLER', team: 'G')]), api);
      expect(find.text('Notifications'), findsOneWidget);
      expect(find.text('Whose students notify me'), findsOneWidget);
      expect(find.text('My students'), findsOneWidget);
      expect(find.text("ME1 Das's students"), findsOneWidget);
      expect(find.text('Unassigned male students'), findsOneWidget);
      expect(find.text('Meeting requests'), findsOneWidget);
      expect(find.text('Calendar reminders'), findsOneWidget);
      Switch sw(String label) => tester.widget<Switch>(find.descendant(of: find.widgetWithText(SwitchListTile, label), matching: find.byType(Switch)));
      expect(sw('My students').value, isTrue);
      expect(sw("ME1 Das's students").value, isFalse, reason: 'default OFF for a Guide');
      expect(sw('Birthdays').value, isTrue);
      // nothing changed yet: Save is disabled
      expect(tester.widget<FloatingActionButton>(find.byType(FloatingActionButton)).onPressed, isNull);
      await tester.tap(find.widgetWithText(SwitchListTile, "ME1 Das's students"));
      await tester.tap(find.widgetWithText(SwitchListTile, 'Birthdays'));
      await tester.pump();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      expect(sent!['groups'], {'own': true, 'admin:ME1': true, 'unassigned': true});
      expect(sent!['types'], {'association_request': true, 'birthday': false, 'calendar_reminder': true});
      await tester.pump(const Duration(seconds: 1));
      expect(AdminProfileProvider.current!.groupOn('admin:ME1'), isTrue, reason: 'the provider is updated after saving');
      expect(find.text('Notification settings saved'), findsOneWidget);
    });

    testWidgets('a server refusal is shown, not swallowed', (tester) async {
      final api = HierarchyApi((n, d) async => throw HierarchyException('permission-denied', 'Not allowed.'));
      await pump(tester, profile('F', 'FEMALE_ENABLER', admins: [a('F', 'FEMALE_ENABLER')]), api);
      expect(find.text('Unassigned female students'), findsOneWidget);
      await tester.tap(find.widgetWithText(SwitchListTile, 'My students'));
      await tester.pump();
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Not allowed.'), findsOneWidget);
    });
  });

  group('Admin list and Add Admin', () {
    Future<void> pump(WidgetTester tester, AdminProfile p, Map<String, dynamic>? Function(String, Map<String, dynamic>) handler) async {
      AdminProfileProvider.instance.debugSet(p);
      HierarchyApi.useForTests((n, d) async => handler(n, d) ?? {});
      await tester.binding.setSurfaceSize(const Size(360, 900));
      await tester.pumpWidget(ChangeNotifierProvider<ColorProvider>(
        create: (_) => ColorProvider(),
        child: const MaterialApp(home: AdminManagerPage()),
      ));
      await tester.pump();
      await tester.pump();
    }

    tearDown(() => HierarchyApi.useForTests(null));

    testWidgets('HOD sees everyone with edit and remove; remove asks how many students become Unassigned', (tester) async {
      final calls = <String>[];
      await pump(tester, profile('H', 'HOD'), (n, d) {
        calls.add('$n $d');
        if (n == 'listAdmins') return {'admins': [a('H', 'HOD'), a('G', 'GUIDE'), a('F', 'FEMALE_ENABLER')]};
        if (n == 'removeAdmin') return {'studentCount': 4, 'teamlessEnablers': <String>[], 'removed': d['dryRun'] != true};
        return null;
      });
      expect(find.text('G Das'), findsOneWidget);
      expect(find.text('F Das'), findsOneWidget);
      expect(find.byTooltip('Edit'), findsNWidgets(3));
      expect(find.byTooltip('Remove'), findsNWidgets(2), reason: 'never on yourself');
      await tester.tap(find.byTooltip('Remove').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('Are you sure? 4 students will become Unassigned.'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.startsWith('removeAdmin')).length, 2, reason: 'a dry run, then the real removal');
      expect(calls.any((c) => c.contains('dryRun: true')), isTrue);
    });

    testWidgets('a Guide sees remove (never edit) on Guides and Male Enablers, not on himself or other roles', (tester) async {
      await pump(tester, profile('G', 'GUIDE'), (n, d) => n == 'listAdmins'
          ? {'admins': [a('G', 'GUIDE'), a('G2', 'GUIDE'), a('ME1', 'MALE_ENABLER', team: 'G'), a('H', 'HOD')]}
          : null);
      expect(find.byTooltip('Edit'), findsNothing, reason: 'editing stays HOD-only');
      expect(find.byTooltip('Remove'), findsNWidgets(2), reason: 'G2 and ME1 only');
      expect(find.textContaining('Team: G Das'), findsOneWidget);
    });

    testWidgets('a Guide removing a Male Enabler gets the same confirmation, then the removal', (tester) async {
      final calls = <String>[];
      await pump(tester, profile('G', 'GUIDE'), (n, d) {
        calls.add('$n ${d['id']} ${d['dryRun']}');
        if (n == 'listAdmins') return {'admins': [a('G', 'GUIDE'), a('ME1', 'MALE_ENABLER', team: 'G')]};
        if (n == 'removeAdmin') return {'studentCount': 1, 'teamlessEnablers': <String>[], 'removed': d['dryRun'] != true};
        return null;
      });
      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Are you sure? 1 student will become Unassigned.'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.startsWith('removeAdmin ME1')).length, 2, reason: 'a dry run, then the real removal');
    });

    // Who sees the remove control on whom: delete rights mirror add rights.
    final everyone = [
      a('H', 'HOD'), a('H2', 'HOD'), a('G', 'GUIDE'), a('G2', 'GUIDE'),
      a('ME', 'MALE_ENABLER', team: 'G'), a('ME2', 'MALE_ENABLER'),
      a('FE', 'FEMALE_ENABLER'), a('FE2', 'FEMALE_ENABLER'),
    ];
    final expectedRemovable = {
      'H': ['H2', 'G', 'G2', 'ME', 'ME2', 'FE', 'FE2'],
      'G': ['G2', 'ME', 'ME2'],
      'ME': ['ME2'],
      'FE': ['FE2'],
    };
    final roleOf = {'H': 'HOD', 'G': 'GUIDE', 'ME': 'MALE_ENABLER', 'FE': 'FEMALE_ENABLER'};
    for (final entry in expectedRemovable.entries) {
      testWidgets('${roleOf[entry.key]}: the remove control is on exactly ${entry.value.join(", ")}', (tester) async {
        // the server's admin list is already filtered by the visibility matrix; the full
        // list here is the worst case (the control must still follow the delete rule)
        await pump(tester, profile(entry.key, roleOf[entry.key]!), (n, d) => n == 'listAdmins' ? {'admins': everyone} : null);
        final shown = <String>[];
        for (final card in tester.widgetList<GuideCard>(find.byType(GuideCard))) {
          final name = find.descendant(of: find.byWidget(card), matching: find.textContaining(' Das')).evaluate().first.widget as Text;
          final title = (name.data ?? '').replaceAll(' Das', '');
          final hasRemove = find.descendant(of: find.byWidget(card), matching: find.byTooltip('Remove')).evaluate().isNotEmpty;
          if (hasRemove) shown.add(title);
        }
        expect(shown, entry.value);
        expect(find.byTooltip('Edit'), entry.key == 'H' ? findsNWidgets(everyone.length) : findsNothing);
      });
    }

    for (final scale in [1.0, 1.3, 1.6]) {
      for (final who in ['H', 'G', 'ME', 'FE']) {
        testWidgets('text scale $scale, ${roleOf[who]}: the admin list has no overflow on 360 dp', (tester) async {
          tester.platformDispatcher.textScaleFactorTestValue = scale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          await pump(tester, profile(who, roleOf[who]!), (n, d) => n == 'listAdmins' ? {'admins': everyone} : null);
          expect(tester.takeException(), isNull);
          for (final r in tester.widgetList<IconButton>(find.byType(IconButton))) {
            expect(r.onPressed, isNotNull);
          }
          final tooltips = find.byTooltip('Remove');
          for (var i = 0; i < tooltips.evaluate().length; i++) {
            final box = tester.getRect(tooltips.at(i));
            expect(box.width, greaterThanOrEqualTo(40));
            expect(box.right, lessThanOrEqualTo(360));
          }
        });
      }
    }

    testWidgets('the server refusing a removal (last HOD, yourself, a role you may not) shows its message', (tester) async {
      await pump(tester, profile('G', 'GUIDE'), (n, d) {
        if (n == 'listAdmins') return {'admins': [a('G', 'GUIDE'), a('G2', 'GUIDE')]};
        throw HierarchyException('permission-denied', 'You cannot remove this admin.');
      });
      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('You cannot remove this admin.'), findsOneWidget);
    });

    test('canRemoveAdminRole mirrors the server rule for every role pair', () {
      for (final actor in AdminRole.values) {
        for (final target in AdminRole.values) {
          expect(canRemoveAdminRole(actor, target), rolesThatCanBeAddedBy(actor).contains(target), reason: '$actor -> $target');
        }
      }
      expect(canRemoveAdminRole(AdminRole.hod, AdminRole.hod), isTrue);
      expect(canRemoveAdminRole(AdminRole.guide, AdminRole.hod), isFalse);
      expect(canRemoveAdminRole(AdminRole.guide, AdminRole.femaleEnabler), isFalse);
      expect(canRemoveAdminRole(AdminRole.maleEnabler, AdminRole.guide), isFalse);
      expect(canRemoveAdminRole(AdminRole.femaleEnabler, AdminRole.maleEnabler), isFalse);
    });

    testWidgets('Add Admin asks NAME and EMAIL; a Guide gets only Guide / Male Enabler choices; the server message is shown', (tester) async {
      Map<String, dynamic>? added;
      await pump(tester, profile('G', 'GUIDE'), (n, d) {
        if (n == 'listAdmins') return {'admins': [a('G', 'GUIDE')]};
        if (n == 'addAdmin') {
          added = d;
          throw HierarchyException('permission-denied', 'You cannot add an admin with that role.');
        }
        return null;
      });
      await tester.tap(find.text('Add admin'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Name'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<AdminRole>));
      await tester.pumpAndSettle();
      expect(find.text('Guide'), findsWidgets);
      expect(find.text('Male Enabler'), findsWidgets);
      expect(find.text('HOD'), findsNothing);
      expect(find.text('Female Enabler'), findsNothing);
      await tester.tap(find.text('Guide').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), 'NKD');
      await tester.enterText(find.widgetWithText(TextField, 'Email'), 'nkd@x.org');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Add'));
      await tester.pumpAndSettle();
      expect(added, {'name': 'NKD', 'email': 'nkd@x.org', 'role': 'GUIDE', 'displayName': 'NKD'});
      expect(find.text('You cannot add an admin with that role.'), findsOneWidget);
    });

    testWidgets('a HOD adding a Male Enabler picks a team Guide', (tester) async {
      await pump(tester, profile('H', 'HOD'), (n, d) => n == 'listAdmins' ? {'admins': [a('H', 'HOD'), a('G', 'GUIDE')]} : null);
      await tester.tap(find.text('Add admin'));
      await tester.pumpAndSettle();
      expect(find.text('Team Guide'), findsNothing);
      await tester.tap(find.byType(DropdownButtonFormField<AdminRole>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Male Enabler').last);
      await tester.pumpAndSettle();
      expect(find.text('Team Guide'), findsOneWidget);
    });
  });

  group('install source', () {
    Future<bool> blocked(Object? installer, {bool release = true}) async {
      const channel = MethodChannel('folk/install_source');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => installer);
      return installedOutsidePlayStore(channel: channel, releaseMode: release);
    }

    test('a release build from a file or another store is blocked; Play and debug are not', () async {
      expect(await blocked(null), isTrue);
      expect(await blocked('com.google.android.packageinstaller'), isTrue);
      expect(await blocked('com.android.vending'), isFalse);
      expect(await blocked(null, release: false), isFalse);
    });

    testWidgets('the blocking screen says what to do', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: NonPlayInstallScreen()));
      expect(find.text('This copy was installed outside the Play Store. Please uninstall it and install the app from the Play Store.'), findsOneWidget);
      expect(find.text('Open the Play Store'), findsOneWidget);
      expect(NonPlayInstallScreen.packageId, 'org.folksurat.guides');
    });
  });

  group('source guarantees', () {
    final files = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) f,
    ];
    // Code only: comment lines may legitimately mention what was removed.
    String codeOf(File f) => [
          for (final l in f.readAsStringSync().split('\n'))
            if (!l.trimLeft().startsWith('//')) l
        ].join('\n');

    test('the service-account key and every direct FCM call are gone', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('service-account'), isFalse);
      expect(pubspec.contains('googleapis_auth'), isFalse);
      expect(File('lib/Services/AccessToken.dart').existsSync(), isFalse);
      expect(File('lib/Services/SendNotification.dart').existsSync(), isFalse);
      for (final f in files) {
        final src = codeOf(f);
        expect(src.contains('fcm.googleapis.com'), isFalse, reason: f.path);
        expect(src.contains('sendTokenNotification'), isFalse, reason: f.path);
        expect(src.contains('AccessTokenFirebase'), isFalse, reason: f.path);
        expect(src.contains('service-account'), isFalse, reason: f.path);
      }
    });

    test('no id is special: no kHodGuideId or SBSD checks, no LayoutBuilder', () {
      for (final f in files) {
        final src = f.readAsStringSync();
        final code = [for (final l in src.split('\n')) if (!l.trimLeft().startsWith('//')) l].join('\n');
        expect(code.contains('kHodGuideId'), isFalse, reason: f.path);
        expect(code.contains("'SBSD'"), isFalse, reason: f.path);
        expect(code.contains('LayoutBuilder'), isFalse, reason: f.path);
      }
    });

    test('the app never reads or writes adminUsers, tokens or the notification collection', () {
      for (final f in files) {
        final code = [for (final l in f.readAsStringSync().split('\n')) if (!l.trimLeft().startsWith('//')) l].join('\n');
        expect(code.contains("collection('adminUsers')"), isFalse, reason: f.path);
        expect(code.contains("collection('adminTokens')"), isFalse, reason: f.path);
        expect(code.contains("collection('guideEmails')"), isFalse, reason: f.path);
        if (!f.path.endsWith('StudentDeletion.dart')) {
          expect(code.contains("collection('notification')"), isFalse, reason: f.path);
        }
      }
    });

    test('no screen reads the whole users collection', () {
      for (final f in files) {
        final code = [for (final l in f.readAsStringSync().split('\n')) if (!l.trimLeft().startsWith('//')) l].join('\n');
        expect(RegExp(r"collection\('users'\)\s*\.(get|snapshots)\(").hasMatch(code), isFalse, reason: f.path);
      }
    });

    test('boards are listed with rule-provable queries, never an unfiltered boards read', () {
      final board = codeOf(File('lib/utils/BoardQueries.dart'));
      expect(board.contains('_boards().snapshots()'), isFalse);
      expect(board.contains("where('ownerGuideId', isEqualTo: profile.id)"), isTrue);
      expect(board.contains("where('sharedWith', arrayContains: profile.id)"), isTrue);
      expect(board.contains('profile.isHod'), isTrue, reason: 'only the HOD asks for the guideAssignment board');
    });

    test('reassignment goes only through the assignStudent callable', () {
      final board = codeOf(File('lib/utils/BoardQueries.dart'));
      expect(board.contains('reassignGuide'), isFalse);
      expect(File('lib/Home/FolkBoysWorkspace.dart').readAsStringSync(), contains('assignStudent('));
      for (final f in files) {
        final code = f.readAsStringSync();
        expect(RegExp(r"'guideId':\s*(newGuide|FieldValue\.delete)").hasMatch(code), isFalse, reason: f.path);
      }
    });

    test('version bumped', () {
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: 1.1.9+13'));
    });
  });
}
