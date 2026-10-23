import 'package:flutter/material.dart';

import '../Services/HierarchyApi.dart';
import '../utils/AdminProfile.dart';
import '../utils/GuideRoster.dart';
import '../theme/GuideTheme.dart';
import '../theme/GuideTokens.dart';
import '../widgets/GuideSurface.dart';
import '../widgets/GuideDialog.dart';
import '../widgets/OwnedBy.dart';
import '../widgets/GuideWait.dart';
import '../widgets/GuideEntry.dart';

/// "Add Admin" / admin list — hierarchy version.
///
/// * The list comes from the `listAdmins` callable, already filtered by the
///   visibility matrix (HOD sees everyone; a Guide sees Guides and Male
///   Enablers, never a HOD or a Female Enabler; a Male Enabler only Male
///   Enablers; a Female Enabler only Female Enablers). Seeing an admin never
///   grants access to that admin's students.
/// * Adding asks for NAME and EMAIL. The name is the admin's permanent code AND
///   the display name students see (a HOD can change the display name later).
///   The role choices follow the approved matrix (HOD: any incl. HOD; Guide:
///   Guide / Male Enabler; enablers: their own type). A HOD adding a Male
///   Enabler also picks a team Guide (or none).
/// * Only a HOD can edit (name, email, role, team) or remove. Removing asks
///   "Are you sure? N students will become Unassigned."
///
/// Every change is a callable; the server enforces the same rules again.
class AdminManagerPage extends StatefulWidget {
  const AdminManagerPage({super.key});

  @override
  State<AdminManagerPage> createState() => _AdminManagerPageState();
}

class _AdminManagerPageState extends State<AdminManagerPage> {
  late Future<List<AdminSummary>> _future;

  @override
  void initState() {
    super.initState();
    _future = HierarchyApi.instance.listAdmins();
  }

  void _reload() {
    AdminProfileProvider.instance.refresh();
    setState(() => _future = HierarchyApi.instance.listAdmins());
  }

  void _toast(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? context.g.danger : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final profile = AdminProfileProvider.require();

    return GuideScaffold(
      floatingActionButton: GuideFab(
        icon: Icons.person_add_alt_1_outlined,
        label: 'Add admin',
        onPressed: () => _openAddAdminDialog(profile),
      ),
      body: Column(
        children: [
          const GuideTopBar(title: 'Admins'),
          Expanded(
            child: FutureBuilder<List<AdminSummary>>(
              future: _future,
              builder: (context, snapshot) {
                final t = context.gText;
                if (snapshot.hasError) {
                  return Center(child: Text('Could not load admins.', style: t.body));
                }
                if (!snapshot.hasData) {
                  return GuideWait(snapshot: snapshot);
                }
                final admins = snapshot.data!;
                if (admins.isEmpty) {
                  return Center(child: Text('No admins yet.', style: t.body));
                }
                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                      GuideSpace.pagePadding, 12, GuideSpace.pagePadding, 110),
                  itemCount: admins.length,
                  itemBuilder: (context, index) => GuideEntry(
                    index: index,
                    child: _adminTile(profile, admins[index], admins),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _adminTile(
      AdminProfile me, AdminSummary a, List<AdminSummary> everyone) {
    final t = context.gText;
    final g = context.g;
    final team = a.role == AdminRole.maleEnabler
        ? (a.teamGuide.isEmpty
            ? 'No team Guide'
            : 'Team: ${_nameOf(everyone, a.teamGuide)}')
        : null;
    final email = a.email;
    // Editing stays HOD-only; removing follows what this role may add.
    final canEdit = me.isHod;
    final canRemove = a.id != me.id && canRemoveAdminRole(me.role, a.role);
    final initial = a.displayName.isEmpty ? '?' : a.displayName.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GuideCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: g.chipBackground, shape: BoxShape.circle),
                child: Text(initial,
                    style: t.bodyStrong.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(a.displayName, style: t.cardTitleSmall),
                    const SizedBox(height: 2),
                    Text(
                      [
                        a.role.label,
                        if (team != null) team,
                      ].join(' · '),
                      style: t.small,
                    ),
                    if (email != null && email.isNotEmpty) Text(email, style: t.caption),
                    if (a.id != a.displayName) Text('ID ${a.id}', style: t.caption),
                  ],
                ),
              ),
              if (canEdit)
                IconButton(
                  icon: Icon(Icons.edit_outlined, color: g.mutedText),
                  tooltip: 'Edit',
                  onPressed: () => _openEditDialog(me, a, everyone),
                ),
              if (canRemove)
                IconButton(
                  icon: Icon(Icons.delete_outline, color: g.mutedText),
                  tooltip: 'Remove',
                  onPressed: () => _confirmRemove(a),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _nameOf(List<AdminSummary> all, String id) {
    for (final a in all) {
      if (a.id == id) return a.displayName;
    }
    return id;
  }

  // --------------------------------------------------------------------
  // add
  // --------------------------------------------------------------------

  Future<void> _openAddAdminDialog(AdminProfile me) async {
    List<AdminSummary> all = const [];
    try {
      all = await _future;
    } catch (_) {}
    if (!mounted) return;

    final roles = rolesThatCanBeAddedBy(me.role);
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    AdminRole role = roles.first;
    String teamGuide = ''; // HOD adding a Male Enabler picks one (or none)
    String? error;
    bool saving = false;
    bool added = false;

    final existingIds = [for (final a in all) a.id];
    final guides = all.where((a) => a.role == AdminRole.guide).toList();

    await showDialog<void>(
      context: context,
      builder: ownedBy([nameController, emailController], (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              if (saving) return;
              final name = nameController.text.trim();
              final email = emailController.text.trim();

              final nameProblem = validateNewGuideName(name, existingIds);
              if (nameProblem != null) {
                setDialogState(() => error = nameProblem);
                return;
              }
              if (!kAdminEmailRegex.hasMatch(email)) {
                setDialogState(() => error = 'Enter a valid email address');
                return;
              }
              setDialogState(() {
                error = null;
                saving = true;
              });
              try {
                await HierarchyApi.instance.addAdmin(
                  name: name,
                  email: email,
                  role: role,
                  displayName: name,
                  teamGuide:
                      me.isHod && role == AdminRole.maleEnabler ? teamGuide : null,
                );
                added = true;
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } on HierarchyException catch (e) {
                setDialogState(() {
                  saving = false;
                  error = e.message;
                });
              } catch (_) {
                setDialogState(() {
                  saving = false;
                  error = 'Could not save. Check your connection.';
                });
              }
            }

            return GuideDialog(
              title: const Text('Add an admin'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        hintText: 'e.g. NKD',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      enabled: !saving,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'their.email@gmail.com',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (roles.length == 1)
                      Text('Role: ${roles.first.label}',
                          style: const TextStyle(fontWeight: FontWeight.w600))
                    else
                      DropdownButtonFormField<AdminRole>(
                        isExpanded: true,
                        value: role,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                        ),
                        items: [
                          for (final r in roles)
                            DropdownMenuItem(value: r, child: Text(r.label)),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setDialogState(() => role = v ?? role),
                      ),
                    if (me.isHod && role == AdminRole.maleEnabler) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: teamGuide,
                        decoration: const InputDecoration(
                          labelText: 'Team Guide',
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: '', child: Text('No team (HOD only)')),
                          for (final g in guides)
                            DropdownMenuItem(
                                value: g.id, child: Text(g.displayName)),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setDialogState(() => teamGuide = v ?? ''),
                      ),
                    ],
                    if (!me.isHod && role == AdminRole.maleEnabler) ...[
                      const SizedBox(height: 8),
                      Text(
                        me.isGuide
                            ? 'They will join your team.'
                            : 'They will join your team Guide.',
                        style:
                            TextStyle(fontSize: 11, color: context.g.mutedText),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(
                      'The name identifies this admin everywhere — students '
                      'assigned to them, their meetings and their '
                      'notifications — and cannot be renamed here later (a HOD '
                      'can change the name students see). The email is what '
                      'they sign in with.',
                      style: TextStyle(fontSize: 11, color: context.g.mutedText),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!,
                          style: TextStyle(
                              color: context.g.danger, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: const GuideBusyDot(),
                        )
                      : const Text('Add'),
                ),
              ],
            );
          },
        );
      }),
    );

    if (added) {
      _toast('Admin added');
      _reload();
    }
  }

  // --------------------------------------------------------------------
  // edit (HOD only)
  // --------------------------------------------------------------------

  Future<void> _openEditDialog(
      AdminProfile me, AdminSummary a, List<AdminSummary> all) async {
    final isSelf = a.id == me.id;
    final nameController = TextEditingController(text: a.displayName);
    final emailController = TextEditingController(text: a.email ?? '');
    AdminRole role = a.role;
    String teamGuide = a.teamGuide;
    String? error;
    bool saving = false;
    bool changed = false;
    final guides = all.where((g) => g.role == AdminRole.guide).toList();

    await showDialog<void>(
      context: context,
      builder: ownedBy([nameController, emailController], (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              if (saving) return;
              final email = emailController.text.trim();
              final name = nameController.text.trim();
              if (name.isEmpty) {
                setDialogState(() => error = 'Enter a name');
                return;
              }
              if (!kAdminEmailRegex.hasMatch(email)) {
                setDialogState(() => error = 'Enter a valid email address');
                return;
              }
              setDialogState(() {
                error = null;
                saving = true;
              });
              try {
                final api = HierarchyApi.instance;
                final roleChanged = role != a.role;
                await api.updateAdmin(
                  id: a.id,
                  displayName: name == a.displayName ? null : name,
                  email: email == (a.email ?? '') ? null : email,
                  role: roleChanged ? role : null,
                  teamGuide: roleChanged && role == AdminRole.maleEnabler
                      ? teamGuide
                      : null,
                );
                // A team change for an existing Male Enabler.
                if (!roleChanged &&
                    role == AdminRole.maleEnabler &&
                    teamGuide != a.teamGuide) {
                  await api.setTeamGuide(a.id, teamGuide);
                }
                changed = true;
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } on HierarchyException catch (e) {
                setDialogState(() {
                  saving = false;
                  error = e.message;
                });
              } catch (_) {
                setDialogState(() {
                  saving = false;
                  error = 'Could not save. Check your connection.';
                });
              }
            }

            return GuideDialog(
              title: Text('${a.displayName} — edit'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Name (shown to students)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      enabled: !saving,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                      ),
                    ),
                    if (!isSelf) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<AdminRole>(
                        isExpanded: true,
                        value: role,
                        decoration: const InputDecoration(
                          labelText: 'Role',
                        ),
                        items: [
                          for (final r in AdminRole.values)
                            DropdownMenuItem(value: r, child: Text(r.label)),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setDialogState(() => role = v ?? role),
                      ),
                    ],
                    if (role == AdminRole.maleEnabler) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: guides.any((g) => g.id == teamGuide)
                            ? teamGuide
                            : '',
                        decoration: const InputDecoration(
                          labelText: 'Team Guide',
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: '', child: Text('No team (HOD only)')),
                          for (final g in guides)
                            DropdownMenuItem(
                                value: g.id, child: Text(g.displayName)),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setDialogState(() => teamGuide = v ?? ''),
                      ),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!,
                          style: TextStyle(
                              color: context.g.danger, fontSize: 12)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: const GuideBusyDot(),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      }),
    );

    if (changed) {
      _toast('Saved');
      _reload();
    }
  }

  // --------------------------------------------------------------------
  // remove (the HOD any admin; others as far as they may add: see canRemoveAdminRole)
  // --------------------------------------------------------------------

  Future<void> _confirmRemove(AdminSummary a) async {
    final RemoveAdminResult preview;
    try {
      preview = await HierarchyApi.instance.removeAdmin(a.id, dryRun: true);
    } on HierarchyException catch (e) {
      _toast(e.message, error: true);
      return;
    } catch (_) {
      _toast('Could not check. Check your connection.', error: true);
      return;
    }
    if (!mounted) return;

    final n = preview.studentCount;
    final teamless = preview.teamlessEnablers.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => GuideDialog(
        title: Text('Remove ${a.displayName}?'),
        content: Text(
          'Are you sure? $n ${n == 1 ? 'student' : 'students'} will become '
          'Unassigned.'
          '${teamless > 0 ? ' $teamless Male ${teamless == 1 ? 'Enabler' : 'Enablers'} will have no team Guide until a HOD re-attaches them.' : ''}',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text('Remove',
                  style: TextStyle(color: context.g.danger))),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await HierarchyApi.instance.removeAdmin(a.id);
      _toast('${a.displayName} removed');
      _reload();
    } on HierarchyException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('Could not remove. Check your connection.', error: true);
    }
  }
}
