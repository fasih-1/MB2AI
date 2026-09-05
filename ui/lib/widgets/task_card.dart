import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'meta_badge.dart';

/// A small icon button that lifts and tilts on hover.
///
/// Hover is local state. The dashboard used to track the hovered button id
/// globally, which rebuilt the whole screen on every pointer move.
class TaskActionButton extends StatefulWidget {
  const TaskActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? color;

  @override
  State<TaskActionButton> createState() => _TaskActionButtonState();
}

class _TaskActionButtonState extends State<TaskActionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: AnimatedRotation(
          turns: _hovered ? 0.02 : 0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedScale(
            scale: _hovered ? 1.07 : 1,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: IconButton(
              onPressed: widget.onPressed,
              constraints: const BoxConstraints.tightFor(width: 34, height: 34),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                widget.icon,
                size: 17,
                color: widget.color ?? (_hovered ? accent : kTextSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One task in the sidebar list.
///
/// Renders the active variant (tap to select, check to complete) or the
/// completed variant (recover / permanently delete), depending on [isActive].
///
/// Each task carries a subject-identity colour and icon (see
/// [subjectColorFor]/[subjectIconFor]) so the list reads at a glance without
/// opening anything — except the selected task, which borrows the app's
/// accent colour instead, so the one thing you're looking at is also the one
/// thing tinted to match the rest of the UI.
class TaskCard extends StatefulWidget {
  const TaskCard({
    super.key,
    required this.task,
    required this.isActive,
    required this.isSelected,
    this.onTap,
    this.onComplete,
    this.onRecover,
    this.onDelete,
  });

  final TaskSummary task;
  final bool isActive;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onComplete;
  final VoidCallback? onRecover;
  final VoidCallback? onDelete;

  @override
  State<TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<TaskCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final selected = widget.isSelected;
    final accent = Theme.of(context).colorScheme.primary;
    final identityColor = selected
        ? accent
        : subjectColorFor(widget.task.className);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        duration: kFastMotion,
        curve: Curves.easeOutCubic,
        scale: _hovered ? 1.015 : 1,
        child: AnimatedContainer(
          duration: kFastMotion,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected
                ? kSurfaceElevated
                : (_hovered
                      ? kSurfaceElevated.withValues(alpha: 0.6)
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent.withValues(alpha: 0.5) : kBorder,
            ),
            boxShadow: selected ? accentGlow(accent, opacity: 0.13, blur: 16) : null,
          ),
          child: IntrinsicHeight(
            child: Row(
              children: <Widget>[
                // Accent rail: the primary selection cue.
                AnimatedContainer(
                  duration: kFastMotion,
                  width: 3,
                  decoration: BoxDecoration(
                    color: selected ? accent : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 11, top: 11),
                  child: _buildSubjectChip(identityColor),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    hoverColor: Colors.transparent,
                    title: Text(
                      widget.task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium?.copyWith(
                        fontSize: 13.8,
                        color: kTextPrimary,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            widget.task.className,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: kTextSecondary,
                            ),
                          ),
                          _buildMetaRow(),
                        ],
                      ),
                    ),
                    trailing: widget.isActive
                        ? _buildCompleteButton(accent)
                        : _buildCompletedActions(),
                    onTap: widget.isActive ? widget.onTap : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The subject-identity icon chip. Colour comes from [identityColor] —
  /// the task's subject normally, or the app's accent when this card is
  /// selected.
  Widget _buildSubjectChip(Color identityColor) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: identityColor.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        subjectIconFor(widget.task.className),
        size: 17,
        color: identityColor,
      ),
    );
  }

  /// Badges for whatever metadata the scrape produced.
  ///
  /// Everything here is optional: older vault rows and tasks whose badge strip
  /// did not parse simply render nothing, so the card degrades to its previous
  /// two-line form rather than showing empty pills.
  Widget _buildMetaRow() {
    final task = widget.task;
    final badges = <Widget>[];

    if (task.taskType != null) {
      badges.add(
        MetaBadge(label: task.taskType!, emphasised: task.isSummative),
      );
    }
    if (task.weight != null) {
      badges.add(MetaBadge(label: task.weight!, tooltip: 'Weighting'));
    }
    if (task.rubricCriteria.isNotEmpty) {
      badges.add(
        MetaBadge(
          label: task.rubricCriteria.map((c) => c.letter).join(' '),
          icon: Icons.checklist,
          tooltip: task.rubricCriteria.map((c) => c.label).join('\n'),
        ),
      );
    }

    if (badges.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(spacing: 5, runSpacing: 5, children: badges),
    );
  }

  Widget _buildCompleteButton(Color accent) {
    return Tooltip(
      message: 'Mark as Completed',
      child: Material(
        color: Colors.transparent,
        child: InkResponse(
          onTap: widget.onComplete,
          radius: 18,
          child: AnimatedContainer(
            duration: kFastMotion,
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: _hovered ? accent.withValues(alpha: 0.8) : kBorder,
              ),
              color: _hovered ? accent.withValues(alpha: 0.18) : Colors.transparent,
            ),
            child: Icon(
              Icons.check,
              size: 16,
              color: _hovered ? accent : kTextSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TaskActionButton(
          tooltip: 'Recover Task',
          icon: Icons.restore,
          onPressed: widget.onRecover ?? () {},
        ),
        TaskActionButton(
          tooltip: 'Permanently Delete',
          icon: Icons.delete_forever,
          color: kDangerRed,
          onPressed: widget.onDelete ?? () {},
        ),
      ],
    );
  }
}
