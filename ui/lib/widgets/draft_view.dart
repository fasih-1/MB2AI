import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../theme/app_theme.dart';

/// The main content card: empty prompt, loading spinner, no-draft placeholder,
/// or the rendered markdown draft.
///
/// Each state is keyed so the shared transition cross-fades between them.
class DraftView extends StatelessWidget {
  const DraftView({
    super.key,
    required this.selectedTaskId,
    required this.selectedTaskTitle,
    required this.isLoading,
    required this.markdown,
    required this.error,
    required this.onExport,
  });

  final String? selectedTaskId;
  final String? selectedTaskTitle;
  final bool isLoading;
  final String? markdown;
  final String? error;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (selectedTaskId == null) {
      return _transition(
        stateKey: 'main_empty',
        child: Center(
          child: Text(
            'Select a task from the left panel',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              color: kSlateText.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    if (isLoading) {
      return _transition(
        stateKey: 'main_loading_$selectedTaskId',
        child: const Center(
          child: CircularProgressIndicator(color: kAccentBlue),
        ),
      );
    }

    final draft = markdown;
    if (draft == null || draft.trim().isEmpty || error != null) {
      return _transition(
        stateKey: 'main_no_draft_$selectedTaskId',
        child: _buildNoDraft(context),
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
          begin: const Offset(0, 0.04),
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

  Widget _buildNoDraft(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.article_outlined,
            size: 44,
            color: kSlateText.withValues(alpha: 0.55),
          ),
          const SizedBox(height: 14),
          Text(
            'No draft generated yet. Select a mode and click Generate!',
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(
              color: kSlateText.withValues(alpha: 0.84),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (selectedTaskTitle != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              selectedTaskTitle!,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: kSlateText.withValues(alpha: 0.68),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDraft(BuildContext context, String draft) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                selectedTaskTitle ?? 'Generated Draft',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  color: kSlateText,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: onExport,
              icon: const Icon(Icons.download),
              label: const Text('Export Draft'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Markdown(
            data: draft,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(
              Theme.of(context),
            ).copyWith(
              p: textTheme.bodyLarge?.copyWith(
                color: kSlateText.withValues(alpha: 0.95),
                height: 1.45,
              ),
              h1: textTheme.headlineSmall?.copyWith(
                color: kAccentBlue,
                fontWeight: FontWeight.w800,
              ),
              h2: textTheme.titleLarge?.copyWith(
                color: kAccentBlue,
                fontWeight: FontWeight.w700,
              ),
              h3: textTheme.titleMedium?.copyWith(
                color: kAccentBlue,
                fontWeight: FontWeight.w700,
              ),
              a: textTheme.bodyLarge?.copyWith(
                color: kAccentBlue,
                decoration: TextDecoration.underline,
                decorationColor: kAccentBlue.withValues(alpha: 0.6),
              ),
              strong: textTheme.bodyLarge?.copyWith(
                color: kSlateText,
                fontWeight: FontWeight.w700,
              ),
              listBullet: textTheme.bodyLarge?.copyWith(color: kAccentBlue),
              blockquote: textTheme.bodyMedium?.copyWith(
                color: kSlateText.withValues(alpha: 0.82),
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
