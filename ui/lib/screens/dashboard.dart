import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_notifier/local_notifier.dart';

import '../services/api_service.dart';
import '../theme/app_theme.dart';
import '../widgets/ambient_background.dart';
import '../widgets/debug_console.dart';
import '../widgets/draft_view.dart';
import '../widgets/generation_controls.dart';
import '../widgets/task_sidebar.dart';
import '../widgets/top_bar.dart';
import '../widgets/vault_history_dialog.dart';

/// Owns dashboard state and talks to the API. All presentation lives in
/// widgets/, which take data and callbacks and hold no app state of their own.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.apiService});

  final ApiService apiService;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<TaskSummary> _tasks = <TaskSummary>[];
  final List<TaskSummary> _hiddenTasks = <TaskSummary>[];
  final List<VaultDraft> _vaultDrafts = <VaultDraft>[];
  final TextEditingController _customInstructionsController =
      TextEditingController();

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
  bool _showDebugConsole = false;
  bool _showGenerationOptions = false;
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

  bool get _showingActive => _taskView == 'active';

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  @override
  void dispose() {
    _customInstructionsController.dispose();
    super.dispose();
  }

  /// Clears the selected task and any draft shown for it. Was repeated inline
  /// wherever the selection could become stale.
  void _clearSelection() {
    _selectedTaskId = null;
    _selectedTaskTitle = null;
    _selectedTaskClassName = null;
    _draftMarkdown = null;
    _draftError = null;
    _isDraftLoading = false;
    _isGeneratingDraft = false;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Loading -------------------------------------------------------------

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
        if (_showingActive && _selectedTaskId != null) {
          final stillExists = _tasks.any((task) => task.id == _selectedTaskId);
          if (!stillExists) {
            _clearSelection();
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

  // --- Task mutations ------------------------------------------------------

  Future<void> _hideTask(TaskSummary task) async {
    final int originalIndex = _tasks.indexWhere((item) => item.id == task.id);
    if (originalIndex < 0) {
      return;
    }

    setState(() {
      _tasks.removeAt(originalIndex);
      _hiddenTasks.insert(0, task);
      if (_selectedTaskId == task.id) {
        _clearSelection();
      }
    });

    try {
      await widget.apiService.hideTask(task);
      _showMessage('Task marked completed: ${task.title}');
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hiddenTasks.removeWhere((item) => item.id == task.id);
        _tasks.insert(originalIndex, task);
      });
      _showMessage('Unable to complete task: $e');
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
      _showMessage('Task recovered: ${task.title}');
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _tasks.removeWhere((item) => item.id == task.id);
        _hiddenTasks.insert(originalIndex, task);
      });
      _showMessage('Unable to recover task: $e');
    }
  }

  Future<void> _confirmAndPermanentlyDeleteTask(TaskSummary task) async {
    final shouldDelete = await showPermanentDeleteDialog(
      context: context,
      taskTitle: task.title,
    );
    if (shouldDelete) {
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
      _showMessage('Permanently deleted: ${task.title}');
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _hiddenTasks.insert(originalIndex, task);
      });
      _showMessage('Permanent delete failed: $e');
    }
  }

  // --- Backend jobs --------------------------------------------------------

  Future<void> _triggerScrape() async {
    try {
      await widget.apiService.triggerScrape();
      _showMessage('Scraping started.');
    } catch (e) {
      _showMessage('Scrape failed: $e');
    }
  }

  Future<void> _triggerGenerate() async {
    if (_isGeneratingDraft) {
      return;
    }

    if (_selectedTaskTitle == null || _selectedTaskClassName == null) {
      _showMessage('Please select a task from the sidebar first.');
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
      _showMessage(
        'Generation started for $_selectedTaskTitle in $_mode mode.',
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
      _showMessage('Generation failed: $e');
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

  // --- Live log handling ---------------------------------------------------

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

    _showMessage('Draft Ready: $taskTitle');

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

  // --- Attachments and export ----------------------------------------------

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

    List<VaultDraft> drafts;
    try {
      drafts = await widget.apiService.getVaultDrafts();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isVaultLoading = false;
      });
      _showMessage('Vault fetch failed: $e');
      return;
    }

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

    final picked = await showVaultHistoryDialog(
      context: context,
      drafts: _vaultDrafts,
      animationCycle: _vaultAnimationCycle,
    );

    if (picked == null || !mounted) {
      return;
    }

    setState(() {
      _selectedTaskId = 'vault_${picked.id}';
      _selectedTaskTitle = picked.taskTitle;
      _selectedTaskClassName = picked.className;
      _draftMarkdown = picked.content;
      _draftError = null;
      _isDraftLoading = false;
    });
  }

  Future<void> _exportDraft() async {
    final draft = _draftMarkdown;
    if (draft == null || draft.trim().isEmpty) {
      _showMessage('No draft to export yet.');
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
      _showMessage('Draft exported to $finalPath');
    } catch (e) {
      _showMessage('Export failed: $e');
    }
  }

  // --- Composition ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAppBackground,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            const AmbientBackground(),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TaskSidebar(
                    tasks: _showingActive ? _tasks : _hiddenTasks,
                    isActiveView: _showingActive,
                    isLoading: _showingActive ? _isLoading : _isHiddenLoading,
                    error: _showingActive ? _error : _hiddenError,
                    selectedTaskId: _selectedTaskId,
                    completedAnimationCycle: _completedViewAnimationCycle,
                    onViewChanged: _setTaskView,
                    onRefresh: _showingActive ? _loadTasks : _loadHiddenTasks,
                    onTaskSelected: _selectTask,
                    onComplete: _hideTask,
                    onRecover: _recoverTask,
                    onDelete: _confirmAndPermanentlyDeleteTask,
                  ),
                  const SizedBox(width: 18),
                  Expanded(child: _buildWorkspace(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspace(BuildContext context) {
    // The generation bar only appears with a task selected, so the toolbar
    // never shows controls that cannot act on anything.
    final hasSelection = _selectedTaskId != null;

    return Column(
      children: <Widget>[
        TopBar(
          isVaultLoading: _isVaultLoading,
          showDebugConsole: _showDebugConsole,
          onScrape: _triggerScrape,
          onOpenVault: _openVaultHistory,
          onToggleDebugConsole: () {
            setState(() {
              _showDebugConsole = !_showDebugConsole;
            });
          },
        ),
        const SizedBox(height: 14),
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(26, 22, 26, 12),
            decoration: BoxDecoration(
              color: kSurface.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(kPanelRadius),
              border: Border.all(color: kBorder),
            ),
            child: DraftView(
              selectedTaskId: _selectedTaskId,
              selectedTaskTitle: _selectedTaskTitle,
              selectedTaskClassName: _selectedTaskClassName,
              isLoading: _isDraftLoading,
              markdown: _draftMarkdown,
              error: _draftError,
              onExport: _exportDraft,
            ),
          ),
        ),
        AnimatedSize(
          duration: kMediumMotion,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: hasSelection
              ? Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: GenerationControls(
                    instructionsController: _customInstructionsController,
                    mode: _mode,
                    modePulseToken: _modePulseToken,
                    isGenerating: _isGeneratingDraft,
                    isExpanded: _showGenerationOptions,
                    attachedFileName: _attachedFileName,
                    onModeChanged: (value) {
                      setState(() {
                        _mode = value;
                        _modePulseToken++;
                      });
                    },
                    onGenerate: _triggerGenerate,
                    onToggleExpanded: () {
                      setState(() {
                        _showGenerationOptions = !_showGenerationOptions;
                      });
                    },
                    onPickAttachment: _pickAttachment,
                    onClearAttachment: _clearAttachment,
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        AnimatedContainer(
          duration: kMediumMotion,
          curve: Curves.easeOut,
          margin: EdgeInsets.only(top: _showDebugConsole ? 14 : 0),
          height: _showDebugConsole ? 240 : 0,
          child: DebugConsole(
            onLogMessage: _handleLogMessage,
            onTestSuccess: _triggerDebugSuccess,
          ),
        ),
      ],
    );
  }
}
