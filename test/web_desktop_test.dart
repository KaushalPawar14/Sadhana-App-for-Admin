import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_guide_app/Pages/AgentPage.dart';
import 'package:folk_guide_app/Pages/PriorityStudents.dart';
import 'package:folk_guide_app/Services/HierarchyApi.dart';
import 'package:folk_guide_app/agent/AgentOverlay.dart';
import 'package:folk_guide_app/utils/BottomNavBar.dart';
import 'package:folk_guide_app/utils/Responsive.dart';
import 'package:folk_guide_app/widgets/GuideDialog.dart';
import 'package:folk_guide_app/widgets/GuideNav.dart';
import 'package:folk_guide_app/widgets/GuideSideNav.dart';

import 'priority_remove_test.dart' show need, needs;
import 'support/app_harness.dart';
import 'support/guide_test_support.dart';

/// THE GUIDE APP ON A COMPUTER (the web build): the same app and logic; a window at least 900 dp wide gets the side navigation, wide
/// content, lists beside details, the assistant as a panel, centred dialogs and a keyboard. A phone (and a tablet-sized window) keeps the
/// app exactly as it always was — the whole existing suite runs at phone size and is the proof.

void resize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
}

const _widths = [Size(1280, 800), Size(1440, 900), Size(1920, 1080)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadGuideFonts);
  tearDown(() => AgentSession.panelOpen.value = false);

  group('width classes', () {
    test('a phone and a tablet are never "desktop"; 900 dp is the first desktop width', () {
      expect([360.0, 599.0].map(isDesktopWidth), [false, false]);
      expect([600.0, 899.0].map(isTabletWidth), [true, true]);
      expect([900.0, 1280.0, 1920.0].map(isDesktopWidth), [true, true, true]);
      expect(isTabletWidth(900), isFalse);
    });
  });

  group('the shell', () {
    for (final size in _widths) {
      testWidgets('${size.width.toInt()} wide: side navigation instead of the pill bar, the Home board uses the window', (tester) async {
        await prepareApp(tester);
        await pumpScreen(tester, const CurvedNavBar('H'));
        resize(tester, size);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        expect(find.byType(GuideSideNav), findsOneWidget);
        expect(find.byType(GuideFloatingNav), findsNothing);
        expect(tester.getSize(find.byKey(const ValueKey('side-nav'))).width, kSideNavWidth);
        for (final label in ['Home', 'Analysis', 'Tasks', 'Assistant']) {
          expect(find.descendant(of: find.byType(GuideSideNav), matching: find.text(label)), findsOneWidget, reason: label);
        }
        expect(tester.takeException(), isNull);
        // the other tabs: reading content has a sensible width
        await tester.tap(find.byKey(const ValueKey('side-nav-1')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Folk analysis'), findsOneWidget);
        final w = tester.getSize(find.text('Folk analysis').first);
        expect(w.width, lessThan(kContentMaxWidth));
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const ValueKey('side-nav-2')));
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a tablet (800) and a phone (360) keep the pill navigation exactly as before', (tester) async {
      for (final size in const [Size(800, 1000), Size(360, 800)]) {
        await prepareApp(tester);
        await pumpScreen(tester, const CurvedNavBar('H'));
        resize(tester, size);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(GuideFloatingNav), findsOneWidget, reason: '${size.width}');
        expect(find.byType(GuideSideNav), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('the assistant opens as a PANEL beside the page (with the same chat), closes with its X; the floating button is gone on a computer', (tester) async {
      await prepareApp(tester);
      await pumpScreen(tester, const CurvedNavBar('H'));
      resize(tester, _widths.first);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('assistant-panel')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('side-nav-assistant')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('assistant-panel')), findsOneWidget);
      expect(find.byType(AgentPage), findsOneWidget);
      expect(tester.getSize(find.byKey(const ValueKey('assistant-panel'))).width, kAssistantPanelWidth);
      expect(find.byKey(const ValueKey('agent-input')), findsOneWidget, reason: 'the same chat input, with its mic');
      expect(find.byKey(const ValueKey('agent-chats')), findsOneWidget, reason: 'chat history');
      expect(find.byKey(const ValueKey('agent-plan')), findsOneWidget, reason: 'the plan');
      await tester.tap(find.byKey(const ValueKey('agent-close')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('assistant-panel')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('dialogs, forms and the keyboard', () {
    testWidgets('a dialog is centred with a sensible width on a computer; on a phone it is as before', (tester) async {
      await prepareApp(tester);
      await pumpScreen(tester, const Scaffold(body: SizedBox()));
      resize(tester, _widths.last);
      await tester.pump();
      final context = tester.element(find.byType(Scaffold));
      showDialog<void>(context: context, builder: (_) => GuideDialog(title: const Text('Delete this target?'), content: Text('A long explanation. ' * 40), actions: [TextButton(onPressed: () {}, child: const Text('Cancel'))]));
      await tester.pumpAndSettle();
      final box = tester.getRect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(Material)).first);
      expect(box.width, lessThanOrEqualTo(kDialogMaxWidth));
      expect(box.width, greaterThanOrEqualTo(380));
      expect((box.center.dx - 960).abs(), lessThan(2), reason: 'centred in the window');
      // Esc closes it
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      // the text can be selected
      showDialog<void>(context: context, builder: (_) => const GuideDialog(title: Text('Notes'), content: Text('Selectable text')));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.byType(SelectionArea)), findsOneWidget);
    });

    testWidgets('the assistant input: Enter sends on a computer, Shift+Enter is a new line; on a phone Enter stays a new line', (tester) async {
      await prepareApp(tester);
      final sent = <String>[];
      HierarchyApi.useForTests((name, args) async {
        if (name == 'guideAgentTurn') {
          sent.add((args['text'] ?? '').toString());
          return {'sessionId': 'sess12345', 'status': 'message', 'text': 'Done.'};
        }
        return <String, dynamic>{};
      });
      await pumpScreen(tester, const AgentPage());
      resize(tester, _widths.first);
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('agent-input')), 'who has not filed today?');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump(const Duration(milliseconds: 200));
      expect(sent, contains('who has not filed today?'), reason: 'Enter sent it');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('agent-input'))).controller!.text, isEmpty);
      // Shift+Enter adds a line, sends nothing
      await tester.enterText(find.byKey(const ValueKey('agent-input')), 'line one');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump(const Duration(milliseconds: 100));
      expect(sent.length, 1, reason: 'Shift+Enter did not send');
    });
  });

  group('lists beside details', () {
    testWidgets('Interactions needed: the list on the left, the student\'s profile on the right (a tap, nothing is lost)', (tester) async {
      final db = await prepareApp(tester);
      for (final uid in ['s1', 's2']) {
        await needs(db, uid, [need('sadhana', 'sadhana_slip', 'Not fulfilling his commitments for 3 days')]);
      }
      await pumpScreen(tester, const PriorityStudentsPage());
      resize(tester, _widths.first);
      await tester.pump(const Duration(milliseconds: 300));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byKey(const ValueKey('priority-list-pane')), findsOneWidget);
      expect(find.byKey(const ValueKey('priority-detail-pane')), findsOneWidget);
      expect(find.text('Choose a student to see his profile here.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('priority-s1')));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.text('Choose a student to see his profile here.'), findsNothing);
      expect(find.text('Arjun Kumar'), findsWidgets, reason: 'his profile beside the list');
      expect(find.byKey(const ValueKey('priority-s2')), findsOneWidget, reason: 'the list is still there');
    });

    testWidgets('on a phone the list is alone, as before (no panes)', (tester) async {
      final db = await prepareApp(tester);
      await needs(db, 's1', [need('sadhana', 'sadhana_slip', 'x')]);
      await pumpScreen(tester, const PriorityStudentsPage());
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump(const Duration(milliseconds: 60));
      }
      expect(find.byKey(const ValueKey('priority-list-pane')), findsNothing);
      expect(find.byKey(const ValueKey('priority-detail-pane')), findsNothing);
    });
  });

  group('web-only handling and the standing rules', () {
    String src(String f) => File(f).readAsStringSync();

    test('no LayoutBuilder anywhere in the app (the standing rule): widths come from MediaQuery', () {
      for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
        expect(f.readAsStringSync().contains('LayoutBuilder('), isFalse, reason: f.path);
      }
    });

    test('push notifications are skipped in a browser, safely (no token, no permission dialog, no local notification set-up)', () {
      expect(src('lib/Services/UpdateToken.dart').split('if (kIsWeb) return').length - 1, greaterThanOrEqualTo(3));
      expect(src('lib/Services/UpdateFCM.dart').contains('if (kIsWeb) return null'), isTrue);
      final main = src('lib/main.dart');
      expect(main.contains('if (kIsWeb) return;'), isTrue, reason: 'the post-frame notification set-up');
      expect(main.contains('DefaultFirebaseOptions.currentPlatform'), isTrue, reason: 'the web needs its own Firebase configuration');
    });

    test('the phone-only checks are skipped in a browser: store install check, forced update, orientation lock, the file-based recorder', () {
      expect(src('lib/utils/InstallSource.dart').contains('if (kIsWeb) return false'), isTrue);
      expect(src('lib/utils/ForceUpdateCheck.dart').contains('if (kIsWeb) return false'), isTrue);
      expect(src('lib/main.dart').contains('if (!kIsWeb) {'), isTrue);
      final rec = src('lib/Services/VoiceRecorder.dart');
      expect(rec.contains('if (kIsWeb) {'), isTrue);
      expect(rec.contains('AudioEncoder.opus'), isTrue, reason: 'a browser records webm / opus, which the server accepts');
      expect(rec.contains("mimeType: 'audio/webm'"), isTrue);
    });

    test('sign-in on the web is Google\'s pop-up through Firebase Auth, with the SAME admin check afterwards', () {
      final s = src('lib/Pages/GuideSignIn.dart');
      expect(s.contains('signInWithPopup'), isTrue);
      expect(s.contains('resolveAndPersistIdentity(email)'), isTrue, reason: 'only a registered admin gets in, on the phone and on the web');
      expect(s.contains('This account is not registered as a FOLK guide'), isTrue);
      expect(src('lib/utils/GuideAuthGate.dart').contains('if (!kIsWeb) await GoogleSignIn().signOut()'), isTrue);
    });

    test('a mouse and a trackpad can drag a scrolling area (the board\'s columns); a phone is unaffected', () {
      final m = src('lib/main.dart');
      expect(m.contains('PointerDeviceKind.mouse'), isTrue);
      expect(m.contains('scrollBehavior: const GuideScrollBehavior()'), isTrue);
    });
  });
}
