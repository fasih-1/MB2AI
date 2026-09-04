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
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: Icon(widget.icon, size: 18, color: widget.color),
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
        scale: _hovered ? 1.02 : 1,
        child: AnimatedContainer(
          duration: kFastMotion,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected
                ? kAccentBlue.withValues(alpha: 0.16)
                : Colors.white.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(kCardRadius),
            border: Border.all(
              color: selected
                  ? kAccentBlue.withValues(alpha: 0.68)
                  : kSlateText.withValues(alpha: 0.08),
            ),
            boxShadow: (selected || _hovered)
                ? <BoxShadow>[
                    BoxShadow(
                      color: kAccentBlue.withValues(
                        alpha: selected ? (_hovered ? 0.18 : 0.12) : 0.10,
                      ),
                      blurRadius: _hovered ? 24 : 18,
                      offset: Offset(0, _hovered ? 10 : 8),
                    ),
                  ]
                : null,
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kCardRadius),
            ),
            hoverColor: kAccentBlue.withValues(alpha: 0.08),
            title: Text(
              widget.task.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                fontSize: 14.5,
                color: kSlateText,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                widget.task.className,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: kSlateText.withValues(alpha: 0.70),
                ),
              ),
            ),
            trailing: widget.isActive
                ? _buildCompleteButton()
                : _buildCompletedActions(),
            onTap: widget.isActive ? widget.onTap : null,
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
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: kAccentBlue.withValues(alpha: 0.55)),
              color: kAccentBlue.withValues(alpha: 0.12),
            ),
            child: const Icon(Icons.check, size: 18, color: kAccentBlue),
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
