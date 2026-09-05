import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'mode_selector.dart';

/// The generation bar beneath the draft.
///
/// Replaces the old always-open panel that showed the instructions field, the
/// attachment row and five buttons even with nothing selected. Instructions and
/// attachments now live behind an expander, and the whole bar only appears once
/// a task is selected — so the draft gets the window and no control is shown
/// that cannot currently do anything.
class GenerationControls extends StatelessWidget {
  const GenerationControls({
    super.key,
    required this.instructionsController,
    required this.mode,
    required this.modePulseToken,
    required this.isGenerating,
    required this.isExpanded,
    required this.attachedFileName,
    required this.onModeChanged,
    required this.onGenerate,
    required this.onToggleExpanded,
    required this.onPickAttachment,
    required this.onClearAttachment,
  });

  final TextEditingController instructionsController;
  final String mode;
  final int modePulseToken;
  final bool isGenerating;
  final bool isExpanded;
  final String? attachedFileName;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onGenerate;
  final VoidCallback onToggleExpanded;
  final VoidCallback onPickAttachment;
  final VoidCallback onClearAttachment;

  /// True when something is configured that the collapsed bar would hide.
  bool get _hasHiddenContext =>
      attachedFileName != null || instructionsController.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AnimatedSize(
            duration: kMediumMotion,
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: isExpanded
                ? _buildContextFields(context)
                : const SizedBox(width: double.infinity),
          ),
          _buildControlRow(context),
        ],
      ),
    );
  }

  Widget _buildContextFields(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: instructionsController,
            minLines: 2,
            maxLines: 4,
            style: textTheme.bodyMedium,
            decoration: const InputDecoration(
              labelText: 'Custom instructions (optional)',
              hintText: 'Add context or constraints for this draft...',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: onPickAttachment,
                icon: const Icon(Icons.attach_file, size: 17),
                label: const Text('Attach'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  attachedFileName ?? 'No file attached (.txt, .md, .pdf)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: attachedFileName == null
                        ? kTextSecondary
                        : kTextPrimary,
                  ),
                ),
              ),
              if (attachedFileName != null)
                IconButton(
                  onPressed: onClearAttachment,
                  icon: const Icon(Icons.close, size: 17),
                  tooltip: 'Remove attachment',
                  color: kTextSecondary,
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildControlRow(BuildContext context) {
    final modeSelector = ModeSelector(
      mode: mode,
      pulseToken: modePulseToken,
      onModeChanged: onModeChanged,
    );

    return Padding(
      padding: const EdgeInsets.all(12),
      // The mode selector, generate button and expander have fixed widths, so
      // below this the row would overflow; stack it onto two lines instead.
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 470) {
            return Row(
              children: <Widget>[
                modeSelector,
                const SizedBox(width: 12),
                GenerateDraftButton(
                  isBusy: isGenerating,
                  onPressed: onGenerate,
                ),
                const Spacer(),
                _buildExpanderButton(context),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              modeSelector,
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  GenerateDraftButton(
                    isBusy: isGenerating,
                    onPressed: onGenerate,
                  ),
                  const Spacer(),
                  _buildExpanderButton(context),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildExpanderButton(BuildContext context) {
    final showDot = _hasHiddenContext && !isExpanded;
    final accent = Theme.of(context).colorScheme.primary;

    return Tooltip(
      message: isExpanded
          ? 'Hide instructions and attachment'
          : 'Add instructions or an attachment',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onToggleExpanded,
          child: Ink(
            height: 40,
            width: 44,
            decoration: BoxDecoration(
              color: isExpanded
                  ? accent.withValues(alpha: 0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isExpanded ? accent.withValues(alpha: 0.55) : kBorder,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: kMediumMotion,
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.expand_more,
                    size: 20,
                    color: isExpanded ? accent : kTextSecondary,
                  ),
                ),
                // Without this the collapsed bar would silently hide typed
                // instructions or an attached file.
                if (showDot)
                  Positioned(
                    top: 8,
                    right: 9,
                    child: CircleAvatar(radius: 3, backgroundColor: accent),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
