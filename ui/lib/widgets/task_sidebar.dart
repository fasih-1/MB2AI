import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import 'staggered_entrance.dart';
import 'task_card.dart';

/// The left panel: a header that toggles between Active and Completed, and the
/// task list for whichever view is showing.
///
/// Stateless — the dashboard owns the data and the mutations, and passes them
/// down. Named for what it lists; grouping tasks under their subject is a
/// separate change that would use the new /subjects endpoint.
class TaskSidebar extends StatelessWidget {
  const TaskSidebar({
    super.key,
    required this.tasks,
    required this.isActiveView,
    required this.isLoading,
    required this.error,
    required this.selectedTaskId,
    required this.completedAnimationCycle,
    required this.onViewChanged,
    required this.onTaskSelected,
    required this.onComplete,
    required this.onRecover,
    required this.onDelete,
  });

  final List<TaskSummary> tasks;
  final bool isActiveView;
  final bool isLoading;
  final String? error;
  final String? selectedTaskId;
  final int completedAnimationCycle;
  final ValueChanged<String> onViewChanged;
  final ValueChanged<TaskSummary> onTaskSelected;
  final ValueChanged<TaskSummary> onComplete;
  final ValueChanged<TaskSummary> onRecover;
  final ValueChanged<TaskSummary> onDelete;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kPanelRadius),
      child: Container(
        width: 360,
        decoration: BoxDecoration(
          border: Border.all(color: kSlateText.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(kPanelRadius),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: kSlateText.withValues(alpha: 0.08),
              blurRadius: 26,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.60),
              borderRadius: BorderRadius.circular(kPanelRadius),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildHeader(context),
                _buildBody(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              isActiveView ? 'Tasks' : 'Completed',
              style: textTheme.headlineSmall?.copyWith(
                color: kSlateText,
                fontSize: 23,
              ),
            ),
          ),
          Tooltip(
            message: 'Active Tasks',
            child: IconButton(
              onPressed: () => onViewChanged('active'),
              icon: Icon(
                Icons.list_alt,
                color: isActiveView
                    ? kAccentBlue
                    : kSlateText.withValues(alpha: 0.65),
              ),
            ),
          ),
          Tooltip(
            message: 'Completed Bin',
            child: IconButton(
              onPressed: () => onViewChanged('completed'),
              icon: Icon(
                Icons.delete_outline,
                color: isActiveView
                    ? kSlateText.withValues(alpha: 0.65)
                    : kAccentBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (isLoading) {
      return const Expanded(child: Center(child: CircularProgressIndicator()));
    }

    if (error != null) {
      return Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              error!,
              style: const TextStyle(color: kDangerRed),
            ),
          ),
        ),
      );
    }

    if (tasks.isEmpty) {
      return Expanded(
        child: Center(
          child: Text(
            isActiveView
                ? 'No active tasks found yet.'
                : 'No completed tasks yet.',
            style: textTheme.bodyMedium?.copyWith(
              color: kSlateText.withValues(alpha: 0.65),
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        itemCount: tasks.length,
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (BuildContext context, int index) {
          final task = tasks[index];
          final card = TaskCard(
            task: task,
            isActive: isActiveView,
            isSelected: task.id == selectedTaskId,
            onTap: () => onTaskSelected(task),
            onComplete: () => onComplete(task),
            onRecover: () => onRecover(task),
            onDelete: () => onDelete(task),
          );

          if (isActiveView) {
            return card;
          }

          return StaggeredEntranceItem(
            index: index,
            replayToken: completedAnimationCycle,
            child: card,
          );
        },
      ),
    );
  }
}
