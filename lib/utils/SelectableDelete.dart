/// Long-press multi-select + hard-delete, shared identically across
/// InteractionLogger, AssociationManager and FlaggedMessages (Rule 1 — one
/// implementation, not three).
///
/// Mirrors the interaction model `Home/Dashboard.dart` already established
/// for its own student multi-select (long-press to enter selection mode,
/// tap to toggle, an AppBar swap showing a delete action, a confirmation
/// dialog) — but deliberately does NOT reuse that screen's one real gap:
/// `Dashboard._deleteSelectedUsers()` deletes purely off client-side
/// `selectedUserIds` state, re-fetching each document only to read its name,
/// never re-checking ownership against it before calling `.delete()`. Every
/// delete here re-fetches each document and re-runs the caller's own
/// [canDelete] against that document's OWN freshly-read data immediately
/// before deleting it — a stale or manipulated selection can never delete
/// something the permission check would reject, because the check runs at
/// delete-time against real data, not against whatever the UI happened to
/// have selected.
library;

import 'package:flutter/material.dart';

import 'Snackbar.dart';
import '../theme/GuideTheme.dart';
import 'GuideDb.dart';
import '../widgets/GuideAppBar.dart';
import '../widgets/GuideDialog.dart';

/// AppBar shown once 1+ items are selected — visual language matches
/// `Dashboard._buildSelectionAppBar` (red bar, close icon, delete icon,
/// "$n selected" title) so this feels like the same mechanism, not a
/// different one bolted on per screen.
PreferredSizeWidget selectionAppBar({
  required BuildContext context,
  required int count,
  required VoidCallback onCancel,
  required VoidCallback? onDelete,
  // Optional, e.g. AssociationManager's TabBar — kept visible/functional
  // during selection so a guide can still switch tabs while selecting
  // across both without losing the selection (selection state is a single
  // shared id set, not per-tab).
  PreferredSizeWidget? bottom,
}) {
  return GuideAppBar(
    danger: true,
    leading: IconButton(
      icon: const Icon(Icons.close),
      tooltip: 'Cancel selection',
      onPressed: onCancel,
    ),
    title: Text('$count selected'),
    actions: [
      IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete selected',
        onPressed: onDelete,
      ),
    ],
    bottom: bottom,
  );
}

/// Wraps an existing card [child] with the one shared selection visual
/// treatment (Part 3 — "selected-state styling should look intentional, not
/// bolted on, consistent across all three list types"): a red border plus a
/// small checkmark badge when selected, a slight dimming of unselected cards
/// while selection mode is active so the selected ones read as emphasised,
/// and the long-press/tap handling that drives it. The card's own visual
/// design (colours, borders, badges already particular to each screen) is
/// untouched — this only adds a layer on top.
Widget selectableCard({
  required BuildContext context,
  required Widget child,
  required bool selected,
  required bool selectionMode,
  required VoidCallback onTap,
  required VoidCallback onLongPress,
}) {
  return Stack(
    children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: selected
              ? Border.all(color: context.g.danger, width: 2)
              : null,
        ),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: selectionMode && !selected ? 0.72 : 1.0,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              child: child,
            ),
          ),
        ),
      ),
      if (selected)
        Positioned(
          top: 8,
          right: 8,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: context.g.danger,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check, size: 14, color: context.g.onPrimary),
          ),
        ),
    ],
  );
}

/// Confirms, then hard-deletes every id in [selectedIds] from
/// [collectionName] — permanent Firestore document deletion (product-owner
/// decision, Part 2 item 4), never a soft/"archived" flag.
///
/// [canDelete] is called with EACH document's own freshly-fetched data,
/// immediately before that document is deleted — never with cached/stale
/// state — so the permission check always reflects what is actually true of
/// that record right now (see the file header for why this matters).
///
/// Verifies rather than assumes: after each `.delete()` call, re-fetches the
/// document and only counts it as deleted once it is confirmed gone. A
/// document already absent (e.g. deleted from another device a moment
/// earlier) counts as a success — the end state the caller wanted is already
/// true — rather than as a failure to report.
///
/// Returns the set of ids that were ACTUALLY deleted, so the caller updates
/// its own selection/UI state only for what genuinely succeeded — never an
/// optimistic "assume it worked" removal (Part 2 item 4).
Future<Set<String>> confirmAndDeleteSelected({
  required BuildContext context,
  required String collectionName,
  required Set<String> selectedIds,
  required Future<bool> Function(Map<String, dynamic> data) canDelete,
  String itemNounSingular = 'item',
  String itemNounPlural = 'items',
}) async {
  if (selectedIds.isEmpty) return {};

  final count = selectedIds.length;
  final noun = count == 1 ? itemNounSingular : itemNounPlural;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => GuideDialog(
      title: Text("Delete $count $noun?"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "This permanently deletes the selected record(s). This cannot "
            "be undone.",
            style: TextStyle(fontSize: 13.5, height: 1.35),
          ),
          const SizedBox(height: 12),
          // Part 2 item 3's specific product-owner-requested warning —
          // connects to the target/goal feature and any other AI-assisted
          // guidance in this project that draws on this kind of history
          // (e.g. the interaction-extraction flow's own
          // recommendedNextAction/recommendedReasoning fields).
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.g.warning.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: context.g.warning.withValues(alpha: .14)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 16, color: context.g.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Deleting this may also affect the quality of future "
                    "AI-generated suggestions about this student, since "
                    "some recommendations draw on this history.",
                    style: TextStyle(
                        fontSize: 12, color: context.g.warning),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text("Cancel"),
        ),
        ElevatedButton(
          style:
              ElevatedButton.styleFrom(backgroundColor: context.g.danger),
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text("Delete", style: TextStyle(color: context.g.onPrimary)),
        ),
      ],
    ),
  );

  if (confirmed != true) return {};

  final firestore = GuideDb.instance;
  final deleted = <String>{};
  var deniedCount = 0;
  var failedCount = 0;

  await Future.wait(selectedIds.map((id) async {
    try {
      final ref = firestore.collection(collectionName).doc(id);
      final snap = await ref.get();

      if (!snap.exists) {
        // Already gone (e.g. deleted elsewhere a moment earlier) — the end
        // state the caller wanted is already true.
        deleted.add(id);
        return;
      }

      final allowed = await canDelete(snap.data() as Map<String, dynamic>);
      if (!allowed) {
        deniedCount++;
        return;
      }

      await ref.delete();

      // Verify, don't assume: only counted as deleted once confirmed gone.
      final recheck = await ref.get();
      if (recheck.exists) {
        failedCount++;
        return;
      }

      deleted.add(id);
    } catch (_) {
      failedCount++;
    }
  }));

  if (!context.mounted) return deleted;

  if (deniedCount == 0 && failedCount == 0) {
    showSnackbar(
      context,
      deleted.length == 1
          ? "Deleted 1 $itemNounSingular"
          : "Deleted ${deleted.length} $itemNounPlural",
      context.g.success,
      Icons.check_circle,
    );
  } else {
    final parts = <String>[];
    if (deleted.isNotEmpty) parts.add("${deleted.length} deleted");
    if (deniedCount > 0) parts.add("$deniedCount not permitted");
    if (failedCount > 0) parts.add("$failedCount failed");
    showSnackbar(
      context, parts.join(', '), context.g.warning, Icons.warning_amber_rounded);
  }

  return deleted;
}
