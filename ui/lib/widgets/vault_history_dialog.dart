import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'staggered_entrance.dart';

/// Shows saved drafts from the vault.
///
/// Resolves to the draft the user picked, or null if they closed the dialog.
Future<VaultDraft?> showVaultHistoryDialog({
  required BuildContext context,
  required List<VaultDraft> drafts,
  required int animationCycle,
}) {
  return showDialog<VaultDraft>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Vault History'),
        content: SizedBox(
          width: 700,
          child: drafts.isEmpty
              ? const Text('No saved drafts yet.')
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: drafts.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final draft = drafts[index];
                    return StaggeredEntranceItem(
                      index: index,
                      replayToken: animationCycle,
                      child: ListTile(
                        title: Text(draft.taskTitle),
                        titleTextStyle: Theme.of(context).textTheme.titleMedium,
                        subtitle: Text(
                          '${draft.className}  ·  ${draft.mode}  ·  ${draft.createdAt}',
                        ),
                        subtitleTextStyle:
                            Theme.of(context).textTheme.bodySmall,
                        onTap: () =>
                            Navigator.of(dialogContext).pop(draft),
                      ),
                    );
                  },
                ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

/// Confirmation before a permanent delete, which cannot be undone.
Future<bool> showPermanentDeleteDialog({
  required BuildContext context,
  required String taskTitle,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        title: const Text('Permanently Delete Task?'),
        content: Text(
          'This will permanently remove "$taskTitle" from Completed. This action cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: kDangerRed,
              foregroundColor: const Color(0xFF14060A),
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete Permanently'),
          ),
        ],
      );
    },
  );

  return confirmed == true;
}
