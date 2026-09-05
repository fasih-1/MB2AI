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
    required this.onRefresh,
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
  final VoidCallback onRefresh;
  final ValueChanged<TaskSummary> onTaskSelected;
  final ValueChanged<TaskSummary> onComplete;
  final ValueChanged<TaskSummary> onRecover;
  final ValueChanged<TaskSummary> onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 330,
      decoration: BoxDecoration(
        color: kSurface.withValues(alpha: 0.72),
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(kPanelRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildHeader(context),
          const Divider(height: 1),
          _buildBody(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                isActiveView ? 'Tasks' : 'Completed',
                style: textTheme.titleLarge,
              ),
              const SizedBox(width: 8),
              if (!isLoading && error == null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: kAppBackground,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kBorder),
                  ),
                  child: Text(
                    '${tasks.length}',
                    style: textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const Spacer(),
              Tooltip(
                message: 'Refresh',
                child: IconButton(
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh, size: 18),
                  color: kTextSecondary,
                  constraints: const BoxConstraints.tightFor(
                    width: 34,
                    height: 34,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildViewToggle(context),
        ],
      ),
    );
  }

  /// A labelled two-segment toggle. The old header used two bare icons, where
  /// which view was active read only as a colour difference.
  Widget _buildViewToggle(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kAppBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: <Widget>[
          _buildToggleSegment(
            context,
            label: 'Active',
            icon: Icons.list_alt,
            value: 'active',
          ),
          _buildToggleSegment(
            context,
            label: 'Done',
            icon: Icons.check_circle_outline,
            value: 'completed',
          ),
        ],
      ),
    );
  }

  Widget _buildToggleSegment(
    BuildContext context, {
    required String label,
    required IconData icon,
    required String value,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    final selected = (value == 'active') == isActiveView;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onViewChanged(value),
          child: AnimatedContainer(
            duration: kFastMotion,
            decoration: BoxDecoration(
              color: selected ? accent.withValues(alpha: 0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? accent.withValues(alpha: 0.45) : Colors.transparent,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 15, color: selected ? accent : kTextSecondary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: textTheme.bodySmall?.copyWith(
                    color: selected ? accent : kTextSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
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
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.cloud_off_outlined,
                  size: 30,
                  color: kDangerRed,
                ),
                const SizedBox(height: 10),
                Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(color: kDangerRed),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (tasks.isEmpty) {
      return Expanded(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  isActiveView
                      ? Icons.inbox_outlined
                      : Icons.check_circle_outline,
                  size: 30,
                  color: kTextSecondary.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 10),
                Text(
                  isActiveView
                      ? 'No active tasks.\nRun a scrape to pull them in.'
                      : 'Nothing completed yet.',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        itemCount: tasks.length,
        separatorBuilder: (context, index) => const SizedBox(height: 6),
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
