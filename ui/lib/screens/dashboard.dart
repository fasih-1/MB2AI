import 'dart:io';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
  final TextEditingController _customInstructionsController = TextEditingController();
  final List<VaultDraft> _vaultDrafts = <VaultDraft>[];

  bool _isLoading = true;
  bool _isVaultLoading = false;
  String? _error;
  String _mode = 'tutor';
  bool _isDraftLoading = false;
  String? _selectedTaskId;
  String? _selectedTaskTitle;
  String? _selectedTaskClassName;
  String? _draftMarkdown;
  String? _draftError;
  bool _showDebugConsole = false;
  final AudioPlayer _audioPlayer = AudioPlayer();
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

  Future<void> _triggerScrape() async {
    try {
      await widget.apiService.triggerScrape();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Scraping started.')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scrape failed: $e')),
      );
    }
  }

  Future<void> _triggerGenerate() async {
    if (_selectedTaskTitle == null || _selectedTaskClassName == null) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a task from the sidebar first.')),
      );
      return;
    }

    try {
      await widget.apiService.triggerGenerate(
        _mode,
        className: _selectedTaskClassName,
        taskTitle: _selectedTaskTitle,
        customInstructions: _customInstructionsController.text,
        attachmentFile: _attachedFilePath == null ? null : File(_attachedFilePath!),
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Generation started for $_selectedTaskTitle in $_mode mode.'),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Generation failed: $e')),
      );
    }
  }

  Future<void> _selectTask(TaskSummary task) async {
    setState(() {
      _selectedTaskId = task.id;
      _selectedTaskTitle = task.title;
      _selectedTaskClassName = task.className;
      _isDraftLoading = true;
      _draftMarkdown = null;
      _draftError = null;
    });

    try {
      final markdown = await widget.apiService.getDraft(task.className, task.title);
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

    await _audioPlayer.play(AssetSource('sounds/success.wav'));

    final notification = LocalNotification(
      title: 'DRAFT READY',
      body: 'A Draft for $taskTitle - $className is ready for your viewing.',
    );
    await notification.show();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Draft Ready: $taskTitle'),
        ),
      );
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
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final draft = _vaultDrafts[index];
                        return ListTile(
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Vault fetch failed: $e')),
      );
    }
  }

  Future<void> _exportDraft() async {
    final draft = _draftMarkdown;
    if (draft == null || draft.trim().isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No draft to export yet.')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Draft exported to $finalPath')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  @override
  void dispose() {
    _customInstructionsController.dispose();
    _audioPlayer.dispose();
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
                          margin: EdgeInsets.only(top: _showDebugConsole ? 16 : 0),
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
                  child: Text(
                    'Tasks',
                    style: textTheme.headlineSmall?.copyWith(
                      color: kSlateText,
                      fontSize: 23,
                    ),
                  ),
                ),
                if (_isLoading)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFB91C1C)),
                        ),
                      ),
                    ),
                  )
                else if (_tasks.isEmpty)
                  Expanded(
                    child: Center(
                      child: Text(
                        'No tasks found yet.',
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
                      itemCount: _tasks.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (BuildContext context, int index) {
                        final task = _tasks[index];
                        final selected = task.id == _selectedTaskId;
                        return AnimatedContainer(
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
                            boxShadow: selected
                                ? <BoxShadow>[
                                    BoxShadow(
                                      color: kAccentBlue.withValues(alpha: 0.12),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
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
                            onTap: () => _selectTask(task),
                          ),
                        );
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
              ElevatedButton.icon(
                onPressed: _triggerGenerate,
                icon: const Icon(Icons.bolt),
                label: const Text('Generate Drafts'),
              ),
              OutlinedButton.icon(
                onPressed: _loadTasks,
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

  Widget _buildModeSegmentedControl(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    Widget buildSegment({required String value, required String label}) {
      final isSelected = _mode == value;
      return Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: isSelected ? kAccentBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              hoverColor: isSelected
                  ? kAccentBlue.withValues(alpha: 0.90)
                  : kAccentBlue.withValues(alpha: 0.08),
              onTap: () {
                setState(() {
                  _mode = value;
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
      child: Row(
        children: <Widget>[
          buildSegment(value: 'tutor', label: 'Tutor'),
          buildSegment(value: 'ghostwriter', label: 'Ghostwriter'),
        ],
      ),
    );
  }

  Widget _buildMainContentCard(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    if (_selectedTaskId == null) {
      return Center(
        child: Text(
          'Select a task from the left panel',
          textAlign: TextAlign.center,
          style: textTheme.titleMedium?.copyWith(
            color: kSlateText.withValues(alpha: 0.9),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    if (_isDraftLoading) {
      return const Center(
        child: CircularProgressIndicator(color: kAccentBlue),
      );
    }

    if (_draftMarkdown == null || _draftMarkdown!.trim().isEmpty || _draftError != null) {
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
    }

    return Column(
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
            styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: textTheme.bodyLarge?.copyWith(
                color: kSlateText.withValues(alpha: 0.95),
                height: 1.45,
              ),
              h1: textTheme.headlineSmall?.copyWith(color: kAccentBlue, fontWeight: FontWeight.w800),
              h2: textTheme.titleLarge?.copyWith(color: kAccentBlue, fontWeight: FontWeight.w700),
              h3: textTheme.titleMedium?.copyWith(color: kAccentBlue, fontWeight: FontWeight.w700),
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
