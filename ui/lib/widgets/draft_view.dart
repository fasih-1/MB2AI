import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'meta_badge.dart';

/// The main content area: empty prompt, loading spinner, no-draft placeholder,
/// or the rendered markdown draft.
///
/// Each state is keyed so the shared transition cross-fades between them.
class DraftView extends StatelessWidget {
  const DraftView({
    super.key,
    required this.selectedTaskId,
    required this.selectedTaskTitle,
    required this.selectedTaskClassName,
    this.selectedTask,
    required this.isLoading,
    required this.markdown,
    required this.error,
    required this.onExport,
  });

  final String? selectedTaskId;
  final String? selectedTaskTitle;
  final String? selectedTaskClassName;

  /// The selected task, when one is selected from the sidebar. Null for a
  /// draft opened from vault history, which has no live task behind it.
  final TaskSummary? selectedTask;
  final bool isLoading;
  final String? markdown;
  final String? error;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    if (selectedTaskId == null) {
      return _transition(
        stateKey: 'main_empty',
        child: _buildPlaceholder(
          context,
          icon: Icons.article_outlined,
          headline: 'No task selected',
          detail: 'Pick a task on the left to see or generate its draft.',
        ),
      );
    }

    if (isLoading) {
      return _transition(
        stateKey: 'main_loading_$selectedTaskId',
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final draft = markdown;
    if (draft == null || draft.trim().isEmpty || error != null) {
      return _transition(
        stateKey: 'main_no_draft_$selectedTaskId',
        child: _buildPlaceholder(
          context,
          icon: Icons.auto_awesome_outlined,
          headline: 'No draft yet',
          detail: 'Choose a mode below and hit Generate.',
          footnote: selectedTaskTitle,
        ),
      );
    }

    return _transition(
      stateKey: 'main_draft_${selectedTaskId}_${draft.hashCode}',
      child: _buildDraft(context, draft),
    );
  }

  Widget _transition({required Widget child, required String stateKey}) {
    return AnimatedSwitcher(
      duration: kSlowMotion,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (transitionChild, animation) {
        final offsetAnimation = Tween<Offset>(
          begin: const Offset(0, 0.03),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: offsetAnimation,
            child: transitionChild,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }

  Widget _buildPlaceholder(
    BuildContext context, {
    required IconData icon,
    required String headline,
    required String detail,
    String? footnote,
  }) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: kSurfaceElevated,
              shape: BoxShape.circle,
              border: Border.all(color: kBorder),
            ),
            child: Icon(icon, size: 26, color: kTextSecondary),
          ),
          const SizedBox(height: 16),
          Text(headline, style: textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall,
          ),
          if (footnote != null) ...<Widget>[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kSurfaceElevated,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kBorder),
              ),
              child: Text(
                footnote,
                style: textTheme.bodySmall?.copyWith(color: kTextPrimary),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Assessment metadata for the selected task.
  ///
  /// The header has room for criterion names in full, unlike the sidebar card
  /// where only the letters fit.
  Widget _buildTaskMeta() {
    final task = selectedTask;
    if (task == null) {
      return const SizedBox.shrink();
    }

    final badges = <Widget>[
      if (task.taskType != null)
        MetaBadge(label: task.taskType!, emphasised: task.isSummative),
      if (task.category != null) MetaBadge(label: task.category!),
      if (task.weight != null)
        MetaBadge(label: task.weight!, tooltip: 'Weighting'),
      if (task.status != null) MetaBadge(label: task.status!),
      for (final criterion in task.rubricCriteria)
        MetaBadge(label: criterion.label, icon: Icons.checklist),
    ];

    if (badges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 6, runSpacing: 6, children: badges),
    );
  }

  Widget _buildDraft(BuildContext context, String draft) {
    final textTheme = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    final accentGlowColor = lightenAccent(accent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    selectedTaskTitle ?? 'Generated Draft',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleLarge,
                  ),
                  if (selectedTaskClassName != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      selectedTaskClassName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall,
                    ),
                  ],
                  _buildTaskMeta(),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download, size: 17),
              label: const Text('Export'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 6),
        Expanded(
          child: Markdown(
            data: draft,
            selectable: true,
            padding: const EdgeInsets.symmetric(vertical: 12),
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
                  p: textTheme.bodyLarge,
                  h1: textTheme.headlineSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                  h2: textTheme.titleLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                  h3: textTheme.titleMedium?.copyWith(
                    color: accentGlowColor,
                    fontWeight: FontWeight.w700,
                  ),
                  a: textTheme.bodyLarge?.copyWith(
                    color: accent,
                    decoration: TextDecoration.underline,
                    decorationColor: accent.withValues(alpha: 0.6),
                  ),
                  strong: textTheme.bodyLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                  em: textTheme.bodyLarge?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: kTextSecondary,
                  ),
                  listBullet: textTheme.bodyLarge?.copyWith(color: accent),
                  code: textTheme.bodyMedium?.copyWith(
                    fontFamily: 'monospace',
                    color: accentGlowColor,
                    backgroundColor: Colors.transparent,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: kAppBackground,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBorder),
                  ),
                  blockquote: textTheme.bodyMedium?.copyWith(
                    color: kTextSecondary,
                    fontStyle: FontStyle.italic,
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: kSurfaceElevated.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border(left: BorderSide(color: accent, width: 3)),
                  ),
                  horizontalRuleDecoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: kBorder)),
                  ),
                ),
          ),
        ),
      ],
    );
  }
}
