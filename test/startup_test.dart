import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/utils/AdminProfile.dart';
import 'package:folk_guide_app/utils/ForceUpdateCheck.dart';
import 'package:folk_guide_app/utils/StartupGate.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The launch path: no fixed delay, the decisions in their old order, the app opening from a
// cached admin profile that is re-checked in the background, and signing out when the admin
// was removed.

Map<String, dynamic> profileMap({String id = 'G', String role = 'GUIDE', String team = '', String name = 'G Prabhu', Map<String, bool>? groups}) => {
      'id': id,
      'displayName': name,
      'role': role,
      'teamGuide': team,
      'email': 'g@x.org',
      'notificationPrefs': {'groups': groups ?? {'own': true}, 'types': {'birthday': false}},
      'notificationTypes': [
        {'key': 'birthday', 'label': 'Birthdays', 'scope': 'student'},
      ],
      'admins': [
        {'id': 'G', 'displayName': 'G Prabhu', 'role': 'GUIDE', 'teamGuide': '', 'email': 'g@x.org'},
        {'id': 'E1', 'displayName': 'E1 Das', 'role': 'MALE_ENABLER', 'teamGuide': 'G'},
      ],
    };

AdminProfile profile([Map<String, dynamic>? m]) => AdminProfile.fromMap(m ?? profileMap());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => HierarchyApi.useForTests(null));

  group('the profile cache', () {
    test('toMap / fromMap round trip: every field survives', () {
      final p = profile();
      final back = AdminProfile.fromMap(jsonDecode(jsonEncode(p.toMap())) as Map<String, dynamic>);
      expect(jsonEncode(back.toMap()), jsonEncode(p.toMap()));
      expect(back.role, AdminRole.guide);
      expect(back.groupOn('own'), isTrue);
      expect(back.typeOn('birthday'), isFalse);
      expect(back.notificationTypes.single.label, 'Birthdays');
      expect(back.admins.map((a) => a.id), ['G', 'E1']);
      expect(back.admins.first.email, 'g@x.org');
      expect(back.admins.last.email, isNull);
    });

    test('a successful load writes the cache; it is read back only for the SAME email', () async {
      HierarchyApi.useForTests((n, d) async => profileMap());
      await AdminProfileProvider.instance.load();
      expect((await AdminProfileProvider.instance.readCache('g@x.org'))!.id, 'G');
      expect((await AdminProfileProvider.instance.readCache(' G@X.ORG '))!.id, 'G', reason: 'case-insensitive');
      expect(await AdminProfileProvider.instance.readCache('someone@else.org'), isNull, reason: 'another account never gets it');
      expect(await AdminProfileProvider.instance.readCache(''), isNull);
    });

    test('a damaged cache is no cache', () async {
      SharedPreferences.setMockInitialValues({AdminProfileProvider.cacheKey: '{not json'});
      expect(await AdminProfileProvider.instance.readCache('g@x.org'), isNull);
      SharedPreferences.setMockInitialValues({AdminProfileProvider.cacheKey: '{"id": ""}'});
      expect(await AdminProfileProvider.instance.readCache('g@x.org'), isNull);
    });

    test('a load that finds a non-admin writes nothing; clear / sign-out deletes the cache', () async {
      HierarchyApi.useForTests((n, d) async => throw HierarchyException('permission-denied', 'no'));
      expect(await AdminProfileProvider.instance.load(), isNull);
      expect(await AdminProfileProvider.instance.readCache('g@x.org'), isNull);
      HierarchyApi.useForTests((n, d) async => profileMap());
      await AdminProfileProvider.instance.load();
      AdminProfileProvider.instance.clear();
      await AdminProfileProvider.instance.clearCache();
      expect(await AdminProfileProvider.instance.readCache('g@x.org'), isNull);
      expect(AdminProfileProvider.current, isNull);
    });
  });

  group('revalidate: the background re-check after opening from the cache', () {
    Future<ProfileRefresh> check(Map<String, dynamic> before, Object Function() answer) async {
      AdminProfileProvider.instance.restore(profile(before));
      HierarchyApi.useForTests((n, d) async {
        final a = answer();
        if (a is Exception) throw a;
        return a as Map<String, dynamic>;
      });
      return AdminProfileProvider.instance.revalidate();
    }

    test('the same profile: unchanged', () async {
      expect(await check(profileMap(), () => profileMap()), ProfileRefresh.unchanged);
    });

    test('a preference / display name / admin list change: updated, the provider holds the new one', () async {
      expect(await check(profileMap(), () => profileMap(name: 'New Name', groups: {'own': false})), ProfileRefresh.updated);
      expect(AdminProfileProvider.current!.displayName, 'New Name');
      expect(AdminProfileProvider.current!.groupOn('own'), isFalse);
      expect((await AdminProfileProvider.instance.readCache('g@x.org'))!.displayName, 'New Name', reason: 'the cache follows');
    });

    test('role or team changed: restructured (who sees what is different)', () async {
      expect(await check(profileMap(), () => profileMap(role: 'HOD')), ProfileRefresh.restructured);
      expect(AdminProfileProvider.current!.isHod, isTrue);
      expect(await check(profileMap(role: 'MALE_ENABLER', team: 'G'), () => profileMap(role: 'MALE_ENABLER', team: 'G2')), ProfileRefresh.restructured);
    });

    test('the admin was removed: removed (the app signs out)', () async {
      expect(await check(profileMap(), () => HierarchyException('permission-denied', 'Not a registered admin.')), ProfileRefresh.removed);
    });

    test('no connection / a server error: offline, nothing changes and nobody is signed out', () async {
      expect(await check(profileMap(), () => HierarchyException('unavailable', 'offline')), ProfileRefresh.offline);
      expect(AdminProfileProvider.current!.id, 'G');
      expect(await check(profileMap(), () => StateError('boom')), ProfileRefresh.offline);
    });
  });

  group('StartupGate: the launch decision', () {
    final calls = <String>[];
    Future<StartupOutcome> run({
      bool update = false,
      String? email = 'g@x.org',
      bool outside = false,
      AdminProfile? cached,
      Future<String?> Function(String)? fresh,
    }) {
      calls.clear();
      return StartupGate.run(
        forceUpdate: () async {
          calls.add('force');
          return update;
        },
        currentEmail: () => email,
        installedOutsidePlayStore: () async {
          calls.add('outside');
          return outside;
        },
        cachedProfile: (e) async {
          calls.add('cache');
          return cached;
        },
        resolveFresh: (e) async {
          calls.add('fresh');
          return (fresh ?? (_) async => 'G')(e);
        },
      );
    }

    test('an update required wins over everything, even a signed-out user and a cached profile', () async {
      expect((await run(update: true, email: null)).target, StartupTarget.forceUpdate);
      expect((await run(update: true, cached: profile())).target, StartupTarget.forceUpdate);
      expect(calls.contains('fresh'), isFalse);
    });

    test('nobody signed in: sign-in (no install check, no profile work)', () async {
      final o = await run(email: null, outside: true);
      expect(o.target, StartupTarget.signIn);
      expect(calls, ['force']);
    });

    test('a copy installed outside the Play Store is blocked (after the sign-in check)', () async {
      expect((await run(outside: true, cached: profile())).target, StartupTarget.nonPlayInstall);
    });

    test('signed in with a cached profile: the shell at once, from the cache, WITHOUT asking the server', () async {
      final o = await run(cached: profile());
      expect(o.target, StartupTarget.shell);
      expect(o.guideId, 'G');
      expect(o.fromCache, isTrue);
      expect(calls.contains('fresh'), isFalse, reason: 'no getAdminProfile on the way in');
    });

    test('signed in, no cache: the profile is fetched (as before); registered / not registered / offline', () async {
      var o = await run();
      expect([o.target, o.guideId, o.fromCache], [StartupTarget.shell, 'G', false]);
      expect((await run(fresh: (_) async => null)).target, StartupTarget.notRegistered);
      expect((await run(fresh: (_) async => throw HierarchyException('unavailable', 'x'))).target, StartupTarget.offline);
    });

    test('the force-update read and the install check are started TOGETHER, not one after the other', () async {
      final order = <String>[];
      final forceDone = Completer<bool>();
      final outsideDone = Completer<bool>();
      final future = StartupGate.run(
        forceUpdate: () {
          order.add('force started');
          return forceDone.future;
        },
        currentEmail: () => 'g@x.org',
        installedOutsidePlayStore: () {
          order.add('outside started');
          return outsideDone.future;
        },
        cachedProfile: (e) async => profile(),
        resolveFresh: (e) async => 'G',
      );
      await Future<void>.delayed(Duration.zero);
      expect(order, ['force started', 'outside started'], reason: 'both running before either finished');
      outsideDone.complete(false);
      forceDone.complete(false);
      expect((await future).target, StartupTarget.shell);
    });
  });

  group('the splash has no fixed delay, no slow work in front of the first screen', () {
    final main = File('lib/main.dart').readAsStringSync();

    test('no fixed delay in main (the 2 s minimum lives in LaunchSplash and runs in parallel), no awaited token registration', () {
      expect(main.contains('Future.delayed'), isFalse);
      expect(main.contains('updateAdminFcmToken('), isFalse, reason: 'the shell registers the token after its first frame');
      expect(main, contains('StartupGate.run('));
      expect(main, contains('unawaited(_revalidateInBackground())'));
    });

    test('notification permission / channel setup starts after the first frame', () {
      expect(main, contains('addPostFrameCallback((_) async {'));
      expect(main.contains('Future.microtask'), isFalse);
      expect(main, contains('Future.wait<Object?>'), reason: 'Firebase and the theme load together');
    });

    test('the force-update check is capped at 1.5 s and still fails open', () {
      expect(ForceUpdateCheck.timeout, const Duration(milliseconds: 1500));
      final src = File('lib/utils/ForceUpdateCheck.dart').readAsStringSync();
      expect(src, contains('.timeout(timeout)'));
      expect(src, contains('return false;'));
    });

    test('the shell (not the splash) registers the FCM token, once its first frame is drawn', () {
      final entry = File('lib/Home/FolkBoysEntry.dart').readAsStringSync();
      expect(entry, contains('_updateTokenForGuide();'));
      expect(entry, contains('addPostFrameCallback'));
    });

    test('prepareMissingReports is not run at startup (it is not called anywhere)', () {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        if (f.path.endsWith('MissingReportNotification.dart')) continue;
        expect(f.readAsStringSync().contains('prepareMissingReports('), isFalse, reason: f.path);
      }
    });
  });
}
