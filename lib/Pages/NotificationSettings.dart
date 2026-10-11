import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Services/HierarchyApi.dart';
import '../utils/AdminProfile.dart';
import '../utils/ColorProvider.dart';
import '../theme/GuideTheme.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideWait.dart';

/// One "whose students notify me" switch.
class StudentGroupSwitch {
  const StudentGroupSwitch(this.key, this.label);

  /// Preference key: "own", "unassigned" or "admin:<adminId>".
  final String key;
  final String label;
}

/// The group switches this admin sees, by role (approved design):
///  * HOD            "My students", one "<name>'s students" per other admin, "Unassigned students"
///  * Guide          "My students", one per his Male Enablers, "Unassigned male students"
///  * Male Enabler   "My students", "Unassigned male students"
///  * Female Enabler "My students", "Unassigned female students"
List<StudentGroupSwitch> groupSwitchesFor(AdminProfile p) {
  switch (p.role) {
    case AdminRole.hod:
      return [
        const StudentGroupSwitch('own', 'My students'),
        for (final a in p.admins)
          if (a.id != p.id)
            StudentGroupSwitch('admin:${a.id}', "${a.displayName}'s students"),
        const StudentGroupSwitch('unassigned', 'Unassigned students'),
      ];
    case AdminRole.guide:
      return [
        const StudentGroupSwitch('own', 'My students'),
        for (final a in p.myMaleEnablers)
          StudentGroupSwitch('admin:${a.id}', "${a.displayName}'s students"),
        const StudentGroupSwitch('unassigned', 'Unassigned male students'),
      ];
    case AdminRole.maleEnabler:
      return const [
        StudentGroupSwitch('own', 'My students'),
        StudentGroupSwitch('unassigned', 'Unassigned male students'),
      ];
    case AdminRole.femaleEnabler:
      return const [
        StudentGroupSwitch('own', 'My students'),
        StudentGroupSwitch('unassigned', 'Unassigned female students'),
      ];
  }
}

/// The "Notifications" page (Others menu).
///
/// Top: "Whose students notify me" — which groups of students you are told
/// about. Below: one switch per notification type. A notification about a
/// student is delivered only if BOTH its student group and its type are on;
/// types that are not about one student (calendar, plan suggestions, trips...)
/// obey only their type switch. Everything defaults to ON, except a Guide's
/// switches for his Male Enablers' students (OFF). Saved with the
/// `saveNotificationPrefs` callable; the server applies them when routing.
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, this.api});

  final HierarchyApi? api;

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  late final AdminProfile _profile = AdminProfileProvider.require();
  late final List<StudentGroupSwitch> _groups = groupSwitchesFor(_profile);
  late final Map<String, bool> _groupValues = {
    for (final g in _groups) g.key: _profile.groupOn(g.key),
  };
  late final Map<String, bool> _typeValues = {
    for (final t in _profile.notificationTypes) t.key: _profile.typeOn(t.key),
  };
  late final Map<String, bool> _savedGroups = Map.of(_groupValues);
  late final Map<String, bool> _savedTypes = Map.of(_typeValues);
  bool _saving = false;

  bool get _dirty =>
      !_same(_groupValues, _savedGroups) || !_same(_typeValues, _savedTypes);

  static bool _same(Map<String, bool> a, Map<String, bool> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final api = widget.api ?? HierarchyApi.instance;
      await api.saveNotificationPrefs(
          groups: Map.of(_groupValues), types: Map.of(_typeValues));
      AdminProfileProvider.instance
          .applyPrefs(groups: Map.of(_groupValues), types: Map.of(_typeValues));
      _savedGroups
        ..clear()
        ..addAll(_groupValues);
      _savedTypes
        ..clear()
        ..addAll(_typeValues);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Notification settings saved')));
    } on HierarchyException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: context.g.danger));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save. Check your connection.'),
          backgroundColor: context.g.danger));
    }
  }

  Widget _heading(String text, ColorProvider c) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(
          text,
          style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: c.secondColor),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final colorProvider = Provider.of<ColorProvider>(context);

    return GuideScaffold(
      appBar: GuideAppBar(
        title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _heading('Whose students notify me', colorProvider),
          for (final g in _groups)
            SwitchListTile(
              title: Text(g.label),
              value: _groupValues[g.key] ?? true,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _groupValues[g.key] = v),
            ),
          const Divider(height: 28),
          _heading('Notify me about', colorProvider),
          for (final t in _profile.notificationTypes)
            SwitchListTile(
              title: Text(t.label),
              value: _typeValues[t.key] ?? true,
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _typeValues[t.key] = v),
            ),
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              'A notification about a student reaches you only if both the '
              'student group and the type are on.',
              style: TextStyle(fontSize: 11, color: context.g.mutedText),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _dirty && !_saving ? _save : null,
        icon: _saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: const GuideBusyDot())
            : const Icon(Icons.save_outlined),
        label: const Text('Save'),
      ),
    );
  }
}
