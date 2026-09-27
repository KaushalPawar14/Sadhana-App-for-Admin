import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../Services/UpdateFCM.dart';
import '../utils/ColorProvider.dart';
import '../utils/GuideRoster.dart';

/// "Add Admin" — Master Task, 2026-09-14 ("Replace the Guide app's name
/// picker with Google Sign-In, and add admin management"), Part 3.
///
/// Replaces `BoysDetails.dart`'s old HOD-only "Add Guide" dialog rather than
/// sitting alongside it: that flow never collected an email, and every
/// admin now needs one to ever sign in at all (Part 2), so keeping both
/// would mean two different "add a guide" entry points doing almost the
/// same thing inconsistently — one of them silently creating an admin who
/// could never log in. Available to ANY guide and the HOD (product owner's
/// explicit decision, Part 3.4), unlike the dialog it replaces.
///
/// Also lists every existing admin with their email (Part 3.6 — recommended
/// AND built, not just proposed): without this, fixing a typo'd email, or
/// giving the three pre-existing admins (`AMHD`/`FOLK`/`SBSD`) an email at
/// all for the first time, would otherwise require the Firebase console
/// every single time. Name/document id stays permanent (matches every other
/// identity in this app — `users.name`, board/guide names); only the email
/// is ever editable here.
class AdminManagerPage extends StatelessWidget {
  const AdminManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colorProvider = Provider.of<ColorProvider>(context);

    return Scaffold(
      backgroundColor: colorProvider.color,
      appBar: AppBar(
        title: const Text('Admins'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add Admin'),
        onPressed: () => _openAddAdminDialog(context),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('adminUsers')
            .orderBy(FieldPath.documentId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('Could not load admins.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No admins yet.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final name = doc.id;
              final email = (doc.data()['email'] as String?)?.trim();
              final hasEmail = email != null && email.isNotEmpty;

              return ListTile(
                title: Text(name,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  hasEmail ? email : 'No email set — cannot sign in',
                  style: TextStyle(
                    color: hasEmail ? null : Colors.red.shade700,
                    fontWeight: hasEmail ? null : FontWeight.w600,
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit email',
                  onPressed: () => _openEditEmailDialog(
                    context,
                    name: name,
                    currentEmail: hasEmail ? email : null,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _openAddAdminDialog(BuildContext context) async {
    List<String> existingNames;
    try {
      existingNames = await guideRosterStream().first;
    } catch (_) {
      existingNames = const <String>[];
    }

    // Who is actually performing this action — NOT the new admin's own
    // name (a real bug caught before shipping: `addedBy` must record the
    // CALLER's resolved identity, so it's fetched here rather than reusing
    // the dialog's own name field for both purposes).
    final actingGuide = await UpdateTokenService().getSavedGuide() ?? '';

    if (!context.mounted) return;

    final nameController = TextEditingController();
    final emailController = TextEditingController();
    String? error;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              if (saving) return;

              final name = nameController.text.trim();
              final email = emailController.text.trim();

              final nameProblem = validateNewGuideName(name, existingNames);
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
                if (await isAdminEmailTaken(email)) {
                  setDialogState(() {
                    saving = false;
                    error = 'That email is already used by another admin';
                  });
                  return;
                }

                await addGuide(name, email: email, addedBy: actingGuide);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (_) {
                setDialogState(() {
                  saving = false;
                  error = 'Could not save. Check your connection.';
                });
              }
            }

            return AlertDialog(
              title: const Text('Add an admin'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    enabled: !saving,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      hintText: 'e.g. NKD',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    enabled: !saving,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      hintText: 'their.email@gmail.com',
                      border: const OutlineInputBorder(),
                      errorText: error,
                    ),
                    onSubmitted: saving ? null : (_) => save(),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'The name is how this admin is identified everywhere — '
                    'students assigned to them, their meetings and their '
                    'notifications. It cannot be renamed later. The email is '
                    'what they sign in with, and can be fixed here later if '
                    'it was typed wrong.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    emailController.dispose();
  }

  Future<void> _openEditEmailDialog(
    BuildContext context, {
    required String name,
    required String? currentEmail,
  }) async {
    final emailController = TextEditingController(text: currentEmail ?? '');
    String? error;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> save() async {
              if (saving) return;

              final email = emailController.text.trim();
              if (!kAdminEmailRegex.hasMatch(email)) {
                setDialogState(() => error = 'Enter a valid email address');
                return;
              }

              setDialogState(() {
                error = null;
                saving = true;
              });

              try {
                if (await isAdminEmailTaken(email, excludingName: name)) {
                  setDialogState(() {
                    saving = false;
                    error = 'That email is already used by another admin';
                  });
                  return;
                }

                await updateAdminEmail(name, newEmail: email);
                if (dialogContext.mounted) Navigator.pop(dialogContext);
              } catch (_) {
                setDialogState(() {
                  saving = false;
                  error = 'Could not save. Check your connection.';
                });
              }
            }

            return AlertDialog(
              title: Text('$name — edit email'),
              content: TextField(
                controller: emailController,
                autofocus: true,
                enabled: !saving,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Email',
                  border: const OutlineInputBorder(),
                  errorText: error,
                ),
                onSubmitted: saving ? null : (_) => save(),
              ),
              actions: [
                TextButton(
                  onPressed:
                      saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving ? null : save,
                  child: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    emailController.dispose();
  }
}
