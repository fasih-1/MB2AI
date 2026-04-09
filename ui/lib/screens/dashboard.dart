import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:local_notifier/local_notifier.dart';

import '../services/api_service.dart';
import '../widgets/debug_console.dart';

const Color kAppBackground = Color(0xFFFAFBFD);
const Color kAccentBlue = Color(0xFF007BFF);
const Color kSlateText = Color(0xFF2C3E50);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<TaskSummary> _tasks = <TaskSummary>[];
  final List<TaskSummary> _hiddenTasks = <TaskSummary>[];
  final TextEditingController _customInstructionsController =
      TextEditingController();
  final List<VaultDraft> _vaultDrafts = <VaultDraft>[];

  bool _isLoading = true;
  bool _isHiddenLoading = false;
  bool _isVaultLoading = false;
  String? _error;
  String? _hiddenError;
  String _mode = 'tutor';
  String _taskView = 'active';
  bool _isDraftLoading = false;
  String? _selectedTaskId;
  String? _selectedTaskTitle;
  String? _selectedTaskClassName;
  String? _draftMarkdown;
  String? _draftError;
  String? _hoveredTaskId;
  String? _hoveredActionButtonId;
  bool _showDebugConsole = false;
  bool _isGeneratingDraft = false;
  int _completedViewAnimationCycle = 0;
  int _vaultAnimationCycle = 0;
  int _modePulseToken = 0;
  final Set<String> _recentSuccessEventKeys = <String>{};
  final List<String> _recentSuccessEventOrder = <String>[];
  String? _attachedFilePath;
  String? _attachedFileName;
  static final RegExp _genSuccessPattern = RegExp(
    r'GEN_SUCCESS title=(.*?) class=(.*?) path=',
  );

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final fetched = await widget.apiService.getTasks();
      if (!mounted) {
        return;
      }
      setState(() {
        _tasks
          ..clear()
          ..addAll(fetched);
        if (_taskView == 'active' && _selectedTaskId != null) {
          final stillExists = _tasks.any((task) => task.id == _selectedTaskId);
          if (!stillExists) {
            _selectedTaskId = null;
            _selectedTaskTitle = null;
            _selectedTaskClassName = null;
            _draftMarkdown = null;
            _draftError = null;
            _isDraftLoading = false;
            _isGeneratingDraft = false;
          }
        }
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadHiddenTasks() async {
    setState(() {
      _isHiddenLoading = true;
      _hiddenError = null;
    });

    try {
      final fetched = await widget.apiService.getHiddenTasks();
      if (!mounted) {
        return;
      }
      setState(() {
        _hiddenTasks
          ..clear()
          ..addAll(fetched);
        _isHiddenLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isHiddenLoading = false;
        _hiddenError = e.toString();
      });
    }
  }

  Future<void> _setTaskView(String view) async {
    if (_taskView == view) {
      return;
    }
    setState(() {
      _taskView = view;
      if (view == 'completed') {
        _completedViewAnimationCycle++;
      }
    });
    if (view == 'completed') {
      await _loadHiddenTasks();
    }
  }

  Future<void> _hideTask(TaskSummary task) async {
    final int originalIndex = _tasks.indexWhere((item) => item.id == task.id);
    if (originalIndex < 0) {
      return;
    }

    setState(() {
      _tasks.removeAt(originalIndex);
      _hiddenTasks.insert(0, task);
      if (_selectedTaskId == task.id) {
        _selectedTaskId = null;
        _selectedTaskTitle = null;
        _selectedTaskClassName = null;
        _draftMarkdown = null;
        _draftError = null;
        _isDraftLoading = false;
        _isGeneratingDraft = false;
      }
    });

    try {
      await widget.apiService.hideTask(task);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Task marked completed: ${task.title}')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hiddenTasks.removeWhere((item) => item.id == task.id);
        _tasks.insert(originalIndex, task);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to complete task: $e')));
    }
  }

  Future<void> _recoverTask(TaskSummary task) async {
    final int originalIndex = _hiddenTasks.indexWhere(
      (item) => item.id == task.id,
    );
    if (originalIndex < 0) {
      return;
    }

    setState(() {
      _hiddenTasks.removeAt(originalIndex);
      _tasks.insert(0, task);
    });

    try {
      await widget.apiService.recoverTask(task.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Task recovered: ${task.title}')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tasks.removeWhere((item) => item.id == task.id);
        _hiddenTasks.insert(originalIndex, task);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to recover task: $e')));
    }
  }

  Future<void> _confirmAndPermanentlyDeleteTask(TaskSummary task) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permanently Delete Task?'),
          content: Text(
            'This will permanently remove "${task.title}" from Completed. This action cannot be undone.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete Permanently'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await _permanentlyDeleteTask(task);
    }
  }

  Future<void> _permanentlyDeleteTask(TaskSummary task) async {
    final int originalIndex = _hiddenTasks.indexWhere(
      (item) => item.id == task.id,
    );
    if (originalIndex < 0) {
      return;
    }

    setState(() {
      _hiddenTasks.removeAt(originalIndex);
    });

    try {
      await widget.apiService.permanentlyDeleteTask(task.id);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Permanently deleted: ${task.title}')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hiddenTasks.insert(originalIndex, task);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Permanent delete failed: $e')));
    }
  }

  Future<void> _triggerScrape() async {
    try {
      await widget.apiService.triggerScrape();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Scraping started.')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Scrape failed: $e')));
    }
  }

  Future<void> _triggerGenerate() async {
    if (_isGeneratingDraft) {
      return;
    }

    if (_selectedTaskTitle == null || _selectedTaskClassName == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a task from the sidebar first.'),
        ),
      );
      return;
    }

    setState(() {
      _isGeneratingDraft = true;
      _isDraftLoading = true;
      _draftError = null;
      _draftMarkdown = null;
    });

    try {
      await widget.apiService.triggerGenerate(
        _mode,
        className: _selectedTaskClassName,
        taskTitle: _selectedTaskTitle,
        customInstructions: _customInstructionsController.text,
        attachmentFile: _attachedFilePath == null
            ? null
            : File(_attachedFilePath!),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Generation started for $_selectedTaskTitle in $_mode mode.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isGeneratingDraft = false;
        _isDraftLoading = false;
        _draftError = e.toString();
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Generation failed: $e')));
    }
  }

  Future<void> _selectTask(TaskSummary task) async {
    setState(() {
      _selectedTaskId = task.id;
      _selectedTaskTitle = task.title;
      _selectedTaskClassName = task.className;
      _isGeneratingDraft = false;
      _isDraftLoading = true;
      _draftMarkdown = null;
      _draftError = null;
    });

    try {
      final markdown = await widget.apiService.getDraft(
        task.className,
        task.title,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _draftMarkdown = markdown;
        _isDraftLoading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isDraftLoading = false;
        _draftError = e.toString();
      });
    }
  }

  Future<void> _handleLogMessage(String line) async {
    final eventKey = line.trim();
    if (eventKey.isEmpty || _recentSuccessEventKeys.contains(eventKey)) {
      return;
    }

    final match = _genSuccessPattern.firstMatch(line);
    if (match == null) {
      return;
    }

    final taskTitle = (match.group(1) ?? '').trim();
    final className = (match.group(2) ?? '').trim();
    if (taskTitle.isEmpty) {
      return;
    }

    _recentSuccessEventKeys.add(eventKey);
    _recentSuccessEventOrder.add(eventKey);
    if (_recentSuccessEventOrder.length > 200) {
      final oldest = _recentSuccessEventOrder.removeAt(0);
      _recentSuccessEventKeys.remove(oldest);
    }

    await SystemSound.play(SystemSoundType.alert);

    final notification = LocalNotification(
      title: 'DRAFT READY',
      body: 'A Draft for $taskTitle - $className is ready for your viewing.',
    );
    await notification.show();

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Draft Ready: $taskTitle')));
    }

    if (_isGeneratingDraft && _isCurrentSelection(taskTitle, className)) {
      unawaited(_refreshSelectedDraftAfterGeneration());
    }
  }

  bool _isCurrentSelection(String taskTitle, String className) {
    return (_selectedTaskTitle ?? '').trim().toLowerCase() ==
            taskTitle.toLowerCase() &&
        (_selectedTaskClassName ?? '').trim().toLowerCase() ==
            className.toLowerCase();
  }

  Future<void> _refreshSelectedDraftAfterGeneration() async {
    final taskTitle = _selectedTaskTitle;
    final className = _selectedTaskClassName;
    if (taskTitle == null || className == null) {
      return;
    }

    try {
      final markdown = await widget.apiService.getDraft(className, taskTitle);
      if (!mounted) {
        return;
      }
      setState(() {
        _draftMarkdown = markdown;
        _draftError = null;
        _isDraftLoading = false;
        _isGeneratingDraft = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _draftError = e.toString();
        _isDraftLoading = false;
        _isGeneratingDraft = false;
      });
    }
  }

  Future<void> _triggerDebugSuccess() async {
    const debugTitle = '[DEBUG] Summative Task 1';
    const debugClass = '[DEBUG] IB MYP Biology';
    final fakeLog =
        'GEN_SUCCESS title=$debugTitle class=$debugClass path=debug-${DateTime.now().millisecondsSinceEpoch} duration_ms=1 mode=tutor';
    await _handleLogMessage(fakeLog);
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['txt', 'md', 'pdf'],
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final selected = result.files.first;
    if (selected.path == null) {
      return;
    }

    setState(() {
      _attachedFilePath = selected.path;
      _attachedFileName = selected.name;
    });
  }

  void _clearAttachment() {
    setState(() {
      _attachedFilePath = null;
      _attachedFileName = null;
    });
  }

  Future<void> _openVaultHistory() async {
    setState(() {
      _isVaultLoading = true;
    });

    try {
      final drafts = await widget.apiService.getVaultDrafts();
      if (!mounted) {
        return;
      }

      setState(() {
        _vaultDrafts
          ..clear()
          ..addAll(drafts);
        _isVaultLoading = false;
        _vaultAnimationCycle++;
      });

      await showDialog<void>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Vault History'),
            content: SizedBox(
              width: 700,
              child: _vaultDrafts.isEmpty
                  ? const Text('No saved drafts yet.')
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: _vaultDrafts.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final draft = _vaultDrafts[index];
                        return _StaggeredEntranceItem(
                          index: index,
                          replayToken: _vaultAnimationCycle,
                          child: ListTile(
                            title: Text(draft.taskTitle),
                            subtitle: Text(
                              '${draft.className} | ${draft.mode} | ${draft.createdAt}',
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              setState(() {
                                _selectedTaskId = 'vault_${draft.id}';
                                _selectedTaskTitle = draft.taskTitle;
                                _selectedTaskClassName = draft.className;
                                _draftMarkdown = draft.content;
                                _draftError = null;
                                _isDraftLoading = false;
                              });
                            },
                          ),
                        );
                      },
                    ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isVaultLoading = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Vault fetch failed: $e')));
    }
  }

  Future<void> _exportDraft() async {
    final draft = _draftMarkdown;
    if (draft == null || draft.trim().isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No draft to export yet.')));
      return;
    }

    final rawTitle = (_selectedTaskTitle ?? 'draft').trim();
    final safeTitle = rawTitle.replaceAll(RegExp(r'[<>:"/\\|?*]+'), '_');
    final savePath = await FilePicker.saveFile(
      dialogTitle: 'Export Draft',
      fileName: '$safeTitle.md',
      type: FileType.custom,
      allowedExtensions: <String>['md', 'txt'],
    );

    if (savePath == null) {
      return;
    }

    var finalPath = savePath;
    final lower = finalPath.toLowerCase();
    if (!lower.endsWith('.md') && !lower.endsWith('.txt')) {
      finalPath = '$finalPath.md';
    }

    try {
      await File(finalPath).writeAsString(draft);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Draft exported to $finalPath')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  @override
  void dispose() {
    _customInstructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAppBackground,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.12, -0.24),
                    radius: 1.22,
                    colors: <Color>[
                      Colors.white,
                      const Color(0xFFF6FAFF),
                      const Color(0xFFEFF4FB),
                    ],
                    stops: const <double>[0.0, 0.58, 1.0],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 54,
              right: -40,
              child: IgnorePointer(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kAccentBlue.withValues(alpha: 0.07),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -20,
              child: IgnorePointer(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kAccentBlue.withValues(alpha: 0.04),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: <Widget>[
                  _buildSidebar(context),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        _buildActionBar(context),
                        const SizedBox(height: 20),
                        Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                            width: double.infinity,
                            padding: const EdgeInsets.all(30),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: kSlateText.withValues(alpha: 0.06),
                              ),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: kSlateText.withValues(alpha: 0.06),
                                  blurRadius: 46,
                                  offset: const Offset(0, 20),
                                ),
                                BoxShadow(
                                  color: kAccentBlue.withValues(alpha: 0.03),
                                  blurRadius: 30,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: _buildMainContentCard(context),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                          margin: EdgeInsets.only(
                            top: _showDebugConsole ? 16 : 0,
                          ),
                          height: _showDebugConsole ? 250 : 0,
                          child: DebugConsole(
                            onLogMessage: _handleLogMessage,
                            onTestSuccess: _triggerDebugSuccess,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final bool showingActive = _taskView == 'active';
    final List<TaskSummary> visibleTasks = showingActive
        ? _tasks
        : _hiddenTasks;
    final bool isLoadingView = showingActive ? _isLoading : _isHiddenLoading;
    final String? errorView = showingActive ? _error : _hiddenError;
    final String emptyMessage = showingActive
        ? 'No active tasks found yet.'
        : 'No completed tasks yet.';

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 360,
        decoration: BoxDecoration(
          border: Border.all(color: kSlateText.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(24),
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
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 14),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          showingActive ? 'Tasks' : 'Completed',
                          style: textTheme.headlineSmall?.copyWith(
                            color: kSlateText,
                            fontSize: 23,
                          ),
                        ),
                      ),
                      Tooltip(
                        message: 'Active Tasks',
                        child: IconButton(
                          onPressed: () => _setTaskView('active'),
                          icon: Icon(
                            Icons.list_alt,
                            color: showingActive
                                ? kAccentBlue
                                : kSlateText.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                      Tooltip(
                        message: 'Completed Bin',
                        child: IconButton(
                          onPressed: () => _setTaskView('completed'),
                          icon: Icon(
                            Icons.delete_outline,
                            color: showingActive
                                ? kSlateText.withValues(alpha: 0.65)
                                : kAccentBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLoadingView)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (errorView != null)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          errorView,
                          style: const TextStyle(color: Color(0xFFB91C1C)),
                        ),
                      ),
                    ),
                  )
                else if (visibleTasks.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        emptyMessage,
                        style: textTheme.bodyMedium?.copyWith(
                          color: kSlateText.withValues(alpha: 0.65),
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: visibleTasks.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final task = visibleTasks[index];
                        final selected = task.id == _selectedTaskId;
                        final hovered = task.id == _hoveredTaskId;
                        final card = MouseRegion(
                          onEnter: (_) {
                            setState(() {
                              _hoveredTaskId = task.id;
                            });
                          },
                          onExit: (_) {
                            if (_hoveredTaskId == task.id) {
                              setState(() {
                                _hoveredTaskId = null;
                              });
                            }
                          },
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            scale: hovered ? 1.02 : 1,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOut,
                              decoration: BoxDecoration(
                                color: selected
                                    ? kAccentBlue.withValues(alpha: 0.16)
                                    : Colors.white.withValues(alpha: 0.42),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: selected
                                      ? kAccentBlue.withValues(alpha: 0.68)
                                      : kSlateText.withValues(alpha: 0.08),
                                ),
                                boxShadow: (selected || hovered)
                                    ? <BoxShadow>[
                                        BoxShadow(
                                          color: kAccentBlue.withValues(
                                            alpha: selected
                                                ? (hovered ? 0.18 : 0.12)
                                                : 0.10,
                                          ),
                                          blurRadius: hovered ? 24 : 18,
                                          offset: Offset(0, hovered ? 10 : 8),
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
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                hoverColor: kAccentBlue.withValues(alpha: 0.08),
                                title: Text(
                                  task.title,
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
                                    task.className,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: kSlateText.withValues(alpha: 0.70),
                                    ),
                                  ),
                                ),
                                trailing: showingActive
                                    ? Tooltip(
                                        message: 'Mark as Completed',
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkResponse(
                                            onTap: () => _hideTask(task),
                                            radius: 18,
                                            child: Container(
                                              width: 32,
                                              height: 32,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: kAccentBlue.withValues(
                                                    alpha: 0.55,
                                                  ),
                                                ),
                                                color: kAccentBlue.withValues(
                                                  alpha: 0.12,
                                                ),
                                              ),
                                              child: const Icon(
                                                Icons.check,
                                                size: 18,
                                                color: kAccentBlue,
                                              ),
                                            ),
                                          ),
                                        ),
                                      )
                                    : Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          _buildAnimatedTaskActionButton(
                                            id: '${task.id}_recover',
                                            tooltip: 'Recover Task',
                                            icon: Icons.restore,
                                            onPressed: () => _recoverTask(task),
                                          ),
                                          _buildAnimatedTaskActionButton(
                                            id: '${task.id}_delete',
                                            tooltip: 'Permanently Delete',
                                            icon: Icons.delete_forever,
                                            color: const Color(0xFFB91C1C),
                                            onPressed: () =>
                                                _confirmAndPermanentlyDeleteTask(
                                                  task,
                                                ),
                                          ),
                                        ],
                                      ),
                                onTap: showingActive
                                    ? () => _selectTask(task)
                                    : null,
                              ),
                            ),
                          ),
                        );

                        if (!showingActive) {
                          return _StaggeredEntranceItem(
                            index: index,
                            replayToken: _completedViewAnimationCycle,
                            child: card,
                          );
                        }

                        return card;
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedTaskActionButton({
    required String id,
    required String tooltip,
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    final hovered = _hoveredActionButtonId == id;
    return Tooltip(
      message: tooltip,
      child: MouseRegion(
        onEnter: (_) {
          setState(() {
            _hoveredActionButtonId = id;
          });
        },
        onExit: (_) {
          if (_hoveredActionButtonId == id) {
            setState(() {
              _hoveredActionButtonId = null;
            });
          }
        },
        child: AnimatedRotation(
          turns: hovered ? 0.02 : 0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: AnimatedScale(
            scale: hovered ? 1.07 : 1,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            child: IconButton(
              onPressed: onPressed,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
              icon: Icon(icon, size: 18, color: color),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionBar(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSlateText.withValues(alpha: 0.06)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: kSlateText.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: ShaderMask(
                  shaderCallback: (Rect bounds) {
                    return const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: <Color>[
                        Color(0xFF0A2E6D),
                        Color(0xFF005FCC),
                        Color(0xFF00B7FF),
                      ],
                      stops: <double>[0.0, 0.52, 1.0],
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.srcIn,
                  child: Text(
                    'MB2AI',
                    style: textTheme.headlineSmall?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.9,
                    ),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _showDebugConsole = !_showDebugConsole;
                    });
                  },
                  child: Ink(
                    height: 40,
                    width: 40,
                    decoration: BoxDecoration(
                      color: _showDebugConsole
                          ? kAccentBlue.withValues(alpha: 0.14)
                          : Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _showDebugConsole
                            ? kAccentBlue.withValues(alpha: 0.7)
                            : kSlateText.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Icon(
                      Icons.terminal,
                      size: 20,
                      color: _showDebugConsole ? kAccentBlue : kSlateText,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _customInstructionsController,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Custom Instructions (optional)',
              hintText: 'Add specific context or constraints for this draft...',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _pickAttachment,
                icon: const Icon(Icons.attach_file),
                label: const Text('Attach File'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _attachedFileName == null
                      ? 'No file attached (.txt, .md, .pdf)'
                      : 'Attached: $_attachedFileName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: _attachedFileName == null
                        ? kSlateText.withValues(alpha: 0.65)
                        : kSlateText,
                  ),
                ),
              ),
              if (_attachedFileName != null)
                IconButton(
                  onPressed: _clearAttachment,
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove attachment',
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              ElevatedButton.icon(
                onPressed: _triggerScrape,
                icon: const Icon(Icons.sync),
                label: const Text('Scrape ManageBac'),
              ),
              _buildModeSegmentedControl(context),
              _buildGenerateDraftButton(),
              OutlinedButton.icon(
                onPressed: _taskView == 'active'
                    ? _loadTasks
                    : _loadHiddenTasks,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Tasks'),
              ),
              OutlinedButton.icon(
                onPressed: _isVaultLoading ? null : _openVaultHistory,
                icon: _isVaultLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.history),
                label: const Text('Vault History'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateDraftButton() {
    final isBusy = _isGeneratingDraft;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      width: isBusy ? 48 : 172,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isBusy ? 24 : 12),
        boxShadow: isBusy
            ? <BoxShadow>[
                BoxShadow(
                  color: kAccentBlue.withValues(alpha: 0.28),
                  blurRadius: 20,
                  spreadRadius: 0.8,
                ),
              ]
            : null,
      ),
      child: ElevatedButton(
        onPressed: isBusy ? null : _triggerGenerate,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: kAccentBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isBusy ? 24 : 12),
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: isBusy
              ? const SizedBox(
                  key: ValueKey('generate_busy'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Center(
                  key: ValueKey('generate_idle'),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.bolt, size: 18),
                        SizedBox(width: 8),
                        Text('Generate Drafts'),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildModeSegmentedControl(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget buildSegment({required String value, required String label}) {
      final isSelected = _mode == value;
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            hoverColor: isSelected
                ? kAccentBlue.withValues(alpha: 0.22)
                : kAccentBlue.withValues(alpha: 0.08),
            onTap: () {
              if (_mode == value) {
                return;
              }
              setState(() {
                _mode = value;
                _modePulseToken++;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: textTheme.labelLarge?.copyWith(
                  color: isSelected ? Colors.white : kSlateText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      width: 270,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kSlateText.withValues(alpha: 0.14)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / 2;
          return Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeInOutCubic,
                left: _mode == 'tutor' ? 0 : segmentWidth,
                top: 0,
                bottom: 0,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('mode_pulse_$_modePulseToken'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOut,
                  builder: (context, value, _) {
                    final pulse = 1 - value;
                    return Container(
                      width: segmentWidth,
                      decoration: BoxDecoration(
                        color: kAccentBlue,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: kAccentBlue.withValues(
                              alpha: 0.20 + (pulse * 0.10),
                            ),
                            blurRadius: 18 + (pulse * 8),
                            spreadRadius: 0.3 + (pulse * 1.0),
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Row(
                children: <Widget>[
                  buildSegment(value: 'tutor', label: 'Tutor'),
                  buildSegment(value: 'ghostwriter', label: 'Ghostwriter'),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMainContentTransition(Widget child, {required String stateKey}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
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

  Widget _buildMainContentCard(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    late final Widget child;
    late final String stateKey;

    if (_selectedTaskId == null) {
      stateKey = 'main_empty';
      child = Center(
        child: Text(
          'Select a task from the left panel',
          textAlign: TextAlign.center,
          style: textTheme.titleMedium?.copyWith(
            color: kSlateText.withValues(alpha: 0.9),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      return _buildMainContentTransition(child, stateKey: stateKey);
    }

    if (_isDraftLoading) {
      stateKey = 'main_loading_$_selectedTaskId';
      child = const Center(
        child: CircularProgressIndicator(color: kAccentBlue),
      );
      return _buildMainContentTransition(child, stateKey: stateKey);
    }

    if (_draftMarkdown == null ||
        _draftMarkdown!.trim().isEmpty ||
        _draftError != null) {
      stateKey = 'main_no_draft_$_selectedTaskId';
      child = Center(
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
            if (_selectedTaskTitle != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                _selectedTaskTitle!,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: kSlateText.withValues(alpha: 0.68),
                ),
              ),
            ],
          ],
        ),
      );
      return _buildMainContentTransition(child, stateKey: stateKey);
    }

    stateKey = 'main_draft_${_selectedTaskId}_${_draftMarkdown.hashCode}';
    child = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                _selectedTaskTitle ?? 'Generated Draft',
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
              onPressed: _exportDraft,
              icon: const Icon(Icons.download),
              label: const Text('Export Draft'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Markdown(
            data: _draftMarkdown!,
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context))
                .copyWith(
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

    return _buildMainContentTransition(child, stateKey: stateKey);
  }
}

class _StaggeredEntranceItem extends StatefulWidget {
  const _StaggeredEntranceItem({
    required this.index,
    required this.replayToken,
    required this.child,
  });

  final int index;
  final int replayToken;
  final Widget child;

  @override
  State<_StaggeredEntranceItem> createState() => _StaggeredEntranceItemState();
}

class _StaggeredEntranceItemState extends State<_StaggeredEntranceItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  Timer? _delayTimer;
  int _scheduleToken = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _offset = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _scheduleAnimation();
  }

  @override
  void didUpdateWidget(covariant _StaggeredEntranceItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.replayToken != widget.replayToken ||
        oldWidget.index != widget.index) {
      _scheduleAnimation();
    }
  }

  void _scheduleAnimation() {
    _delayTimer?.cancel();
    _controller.value = 0;
    final token = ++_scheduleToken;
    _delayTimer = Timer(Duration(milliseconds: widget.index * 50), () {
      if (!mounted || token != _scheduleToken) {
        return;
      }
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}
