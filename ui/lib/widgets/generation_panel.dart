import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'mode_selector.dart';

/// The top bar: branding, custom instructions, attachment picker, and the
/// scrape / generate / refresh / vault actions.
class GenerationPanel extends StatelessWidget {
  const GenerationPanel({
    super.key,
    required this.instructionsController,
    required this.mode,
    required this.modePulseToken,
    required this.isGenerating,
    required this.isVaultLoading,
    required this.showDebugConsole,
    required this.attachedFileName,
    required this.onModeChanged,
    required this.onToggleDebugConsole,
    required this.onScrape,
    required this.onGenerate,
    required this.onRefresh,
    required this.onOpenVault,
    required this.onPickAttachment,
    required this.onClearAttachment,
  });

  final TextEditingController instructionsController;
  final String mode;
  final int modePulseToken;
  final bool isGenerating;
  final bool isVaultLoading;
  final bool showDebugConsole;
  final String? attachedFileName;
  final ValueChanged<String> onModeChanged;
  final VoidCallback onToggleDebugConsole;
  final VoidCallback onScrape;
  final VoidCallback onGenerate;
  final VoidCallback onRefresh;
  final VoidCallback onOpenVault;
  final VoidCallback onPickAttachment;
  final VoidCallback onClearAttachment;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(kCardRadius),
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
          _buildHeaderRow(context),
          const SizedBox(height: 14),
          TextField(
            controller: instructionsController,
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
          _buildAttachmentRow(context),
          const SizedBox(height: 12),
          _buildActions(context),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
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
            onTap: onToggleDebugConsole,
            child: Ink(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: showDebugConsole
                    ? kAccentBlue.withValues(alpha: 0.14)
                    : Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: showDebugConsole
                      ? kAccentBlue.withValues(alpha: 0.7)
                      : kSlateText.withValues(alpha: 0.12),
                ),
              ),
              child: Icon(
                Icons.terminal,
                size: 20,
                color: showDebugConsole ? kAccentBlue : kSlateText,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttachmentRow(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: <Widget>[
        OutlinedButton.icon(
          onPressed: onPickAttachment,
          icon: const Icon(Icons.attach_file),
          label: const Text('Attach File'),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            attachedFileName == null
                ? 'No file attached (.txt, .md, .pdf)'
                : 'Attached: $attachedFileName',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: attachedFileName == null
                  ? kSlateText.withValues(alpha: 0.65)
                  : kSlateText,
            ),
          ),
        ),
        if (attachedFileName != null)
          IconButton(
            onPressed: onClearAttachment,
            icon: const Icon(Icons.close),
            tooltip: 'Remove attachment',
          ),
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        ElevatedButton.icon(
          onPressed: onScrape,
          icon: const Icon(Icons.sync),
          label: const Text('Scrape ManageBac'),
        ),
        ModeSelector(
          mode: mode,
          pulseToken: modePulseToken,
          onModeChanged: onModeChanged,
        ),
        GenerateDraftButton(isBusy: isGenerating, onPressed: onGenerate),
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
          label: const Text('Refresh Tasks'),
        ),
        OutlinedButton.icon(
          onPressed: isVaultLoading ? null : onOpenVault,
          icon: isVaultLoading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.history),
          label: const Text('Vault History'),
        ),
      ],
    );
  }
}
