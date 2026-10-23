import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/GuideTheme.dart';
import '../actions/StudentActions.dart';
import '../utils/Snackbar.dart';
import '../widgets/GuideSurface.dart';

/// One student's own notification switches, seen and set by their guide.
///
/// ---------------------------------------------------------------------------
/// The SAME six keys the Student app owns
/// ---------------------------------------------------------------------------
/// This is a mirror of `Students/.../pages/NotificationPreferences.dart`, not a
/// parallel system: the keys, the titles and the subtitles below are copied
/// from that file so a guide and a student are never shown two different
/// descriptions of the same switch.
///
///   sadhanaReminderMorning   the 08:00 "fill your report" reminder
///   sadhanaReminderMidday    the 11:00 second nudge
///   associationUpdates       meeting confirmed / changed / cancelled
///   chantingChallenge        a new group chanting target
///   newTrip                  a new trip announced for them
///   guideManualReminder      a guide personally nudging them
///
/// Stored at `users/{uid}.notificationPrefs.<key>`, written one dotted key at a
/// time with `SetOptions(merge: true)` — exactly as the Student app writes it,
/// so a key a newer Student app adds is never clobbered by this screen.
///
/// ---------------------------------------------------------------------------
/// Why this needs no Student app update, and no deploy
/// ---------------------------------------------------------------------------
/// The Student app reads these very fields live from its own `users/{uid}`
/// stream, so a switch a guide flips here shows there at once. The server side
/// is already in place too: every sender reads the same field and treats
/// ABSENT or true as "send" (never `== true`), so a student who predates a key
/// keeps receiving that notification until someone turns it off — see
/// `functions/index.js`'s `findMissingStudents` and `tripNotify.js`.
///
/// ---------------------------------------------------------------------------
/// If the live rules refuse the write
/// ---------------------------------------------------------------------------
/// A `permission-denied` is reported as a sentence naming the real cause (the
/// deployed rules do not allow a guide to write this document yet) and the
/// switch springs back to where it was, so the screen never shows a value the
/// server did not accept.
class StudentNotificationSettingsPage extends StatefulWidget {
  const StudentNotificationSettingsPage({
    super.key,
    required this.studentUid,
    required this.studentName,
    required this.canEdit,
    this.firestore,
  });

  final String studentUid;
  final String studentName;

  /// The caller's scope decision; false shows the switches read-only.
  final bool canEdit;

  /// Swapped in tests.
  final FirebaseFirestore? firestore;

  @override
  State<StudentNotificationSettingsPage> createState() =>
      _StudentNotificationSettingsPageState();
}

class StudentPrefItem {
  const StudentPrefItem(this.key, this.title, this.subtitle, this.icon);
  final String key;
  final String title;
  final String subtitle;
  final IconData icon;
}

/// Copied from the Student app's own list, in its order.
const List<StudentPrefItem> kStudentPrefs = [
  StudentPrefItem('sadhanaReminderMorning', 'Morning sadhana reminder',
      'At 8:00 am, if the report for the day is not filled yet',
      Icons.wb_twilight),
  StudentPrefItem('sadhanaReminderMidday', 'Midday sadhana reminder',
      'At 11:00 am, a second nudge if it is still pending',
      Icons.wb_sunny_outlined),
  StudentPrefItem('associationUpdates', 'Meeting updates',
      'When you confirm, change or cancel a meeting', Icons.groups_outlined),
  StudentPrefItem('chantingChallenge', 'Chanting challenges',
      'When a new group chanting target is set', Icons.self_improvement),
  StudentPrefItem('newTrip', 'New trips',
      'When a new trip is announced for them', Icons.explore_outlined),
  StudentPrefItem('guideManualReminder', 'Reminders from you',
      'When you personally nudge them about a report',
      Icons.notifications_active_outlined),
];

/// Absent or true both mean ON — never `== true`, or every student who
/// predates a key would read as opted out. The Student app and every server
/// sender use this same rule.
bool prefIsOn(Map<String, dynamic>? prefs, String key) =>
    prefs == null || prefs[key] is! bool ? true : prefs[key] as bool;

class _StudentNotificationSettingsPageState
    extends State<StudentNotificationSettingsPage> {
  /// Keys currently being written, so a row ignores a second tap mid-write.
  final Set<String> _busy = {};

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  Future<void> _set(String key, bool value) async {
    if (_busy.contains(key)) return;
    setState(() => _busy.add(key));
    try {
      // One shared write (actions/StudentActions.dart), merged one key at a time.
      await setStudentNotificationPref(widget.studentUid, key, value, db: _db);
    } on FirebaseException catch (e) {
      if (!mounted) return;
      showSnackbar(
          context,
          e.code == 'permission-denied'
              ? 'You are not allowed to change this student\'s notifications '
                  'yet. This needs a rules update on the server.'
              : 'Could not save that just now.',
          Colors.red,
          Icons.error);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(context, 'Could not save that just now.', Colors.red,
          Icons.error);
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = context.g;
    return GuidePageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: Column(
            children: [
              GuideTopBar(title: 'Notifications'),
              Expanded(
                child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _db
                      .collection('users')
                      .doc(widget.studentUid)
                      .snapshots(),
                  builder: (context, snap) {
                    final data = snap.data?.data();
                    final prefs =
                        (data?['notificationPrefs'] as Map?)?.cast<String, dynamic>();
                    return ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'What ${widget.studentName} is told about. These '
                            'are the same switches they see in their own app.',
                            style: context.gText.small
                                .copyWith(color: g.mutedText),
                          ),
                        ),
                        for (final p in kStudentPrefs)
                          Opacity(
                            opacity: widget.canEdit ? 1 : .55,
                            child: IgnorePointer(
                              ignoring: !widget.canEdit,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: g.surface,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: g.cardShadow,
                                ),
                                // The tile paints its ink on the nearest
                                // Material; without this the decorated box
                                // above would hide the splash (and Flutter
                                // asserts about exactly that).
                                child: Material(
                                  type: MaterialType.transparency,
                                  child: SwitchListTile.adaptive(
                                    contentPadding: EdgeInsets.zero,
                                    secondary: Icon(p.icon, color: g.brass),
                                    title: Text(p.title),
                                    subtitle: Text(p.subtitle,
                                        style: context.gText.small),
                                    value: prefIsOn(prefs, p.key),
                                    onChanged: _busy.contains(p.key)
                                        ? null
                                        : (v) => _set(p.key, v),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
