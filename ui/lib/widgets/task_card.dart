import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';

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
                color: widget.color ??
                    (_hovered ? kAccentBlue : kTextSecondary),
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
/// Selection reads as an accent left rail plus a lifted surface, rather than
/// the wash of accent-tinted fill the light theme used — on a dark ground a
/// large tinted block competes with the draft for attention.
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
              color: selected ? kAccentBlue.withValues(alpha: 0.5) : kBorder,
            ),
            boxShadow: selected ? accentGlow(opacity: 0.13, blur: 16) : null,
          ),
          child: IntrinsicHeight(
            child: Row(
              children: <Widget>[
                // Accent rail: the primary selection cue.
                AnimatedContainer(
                  duration: kFastMotion,
                  width: 3,
                  decoration: BoxDecoration(
                    color: selected ? kAccentBlue : Colors.transparent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
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
                        color: selected ? kTextPrimary : kTextPrimary,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w600,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        widget.task.className,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: kTextSecondary,
                        ),
                      ),
                    ),
                    trailing: widget.isActive
                        ? _buildCompleteButton()
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

  Widget _buildCompleteButton() {
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
                color: _hovered
                    ? kAccentBlue.withValues(alpha: 0.8)
                    : kBorder,
              ),
              color: _hovered
                  ? kAccentBlue.withValues(alpha: 0.18)
                  : Colors.transparent,
            ),
            child: Icon(
              Icons.check,
              size: 16,
              color: _hovered ? kAccentBlue : kTextSecondary,
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
