import 'package:flutter/material.dart';

import '../theme/accent_color_controller.dart';
import '../theme/app_theme.dart';

/// The slim application toolbar.
///
/// Only holds actions that are always meaningful: syncing, browsing the
/// vault, changing the accent colour, and the debug console. Anything that
/// needs a selected task lives down in GenerationControls instead, so the bar
/// does not present dead controls.
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.isVaultLoading,
    required this.showDebugConsole,
    required this.accentController,
    required this.onScrape,
    required this.onOpenVault,
    required this.onToggleDebugConsole,
  });

  final bool isVaultLoading;
  final bool showDebugConsole;
  final AccentColorController accentController;
  final VoidCallback onScrape;
  final VoidCallback onOpenVault;
  final VoidCallback onToggleDebugConsole;

  /// Below this the labelled buttons no longer fit beside the wordmark.
  static const double _compactBreakpoint = 460;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: kSurface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: kBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _compactBreakpoint;
          return Row(
            children: <Widget>[
              Flexible(child: _buildWordmark(context)),
              const Spacer(),
              _buildScrapeButton(compact: compact),
              const SizedBox(width: 8),
              _buildVaultButton(compact: compact),
              const SizedBox(width: 8),
              _buildAccentPicker(context),
              const SizedBox(width: 8),
              _buildConsoleToggle(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWordmark(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[
            lightenAccent(accent),
            accent,
            darkenAccent(accent, 0.08),
          ],
          stops: const <double>[0.0, 0.55, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.srcIn,
      child: Text(
        'MB2AI',
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: textTheme.headlineSmall?.copyWith(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildScrapeButton({required bool compact}) {
    if (compact) {
      return Tooltip(
        message: 'Scrape ManageBac',
        child: OutlinedButton(
          onPressed: onScrape,
          style: _iconButtonStyle,
          child: const Icon(Icons.sync, size: 17),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onScrape,
      icon: const Icon(Icons.sync, size: 17),
      label: const Text('Scrape'),
    );
  }

  Widget _buildVaultButton({required bool compact}) {
    final icon = isVaultLoading
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.inventory_2_outlined, size: 17);

    if (compact) {
      return Tooltip(
        message: 'Vault History',
        child: OutlinedButton(
          onPressed: isVaultLoading ? null : onOpenVault,
          style: _iconButtonStyle,
          child: icon,
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: isVaultLoading ? null : onOpenVault,
      icon: icon,
      label: const Text('Vault'),
    );
  }

  Widget _buildAccentPicker(BuildContext context) {
    return Tooltip(
      message: 'Accent colour',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => _showAccentPicker(context),
          child: Container(
            width: 38,
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: kBorder)),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentController.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showAccentPicker(BuildContext context) async {
    final chosen = await showDialog<Color>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Accent Colour'),
          content: SizedBox(
            width: 260,
            child: Wrap(
              spacing: 14,
              runSpacing: 14,
              children: <Widget>[
                for (final swatch in kAccentSwatches)
                  _AccentSwatch(
                    color: swatch,
                    selected: swatch == accentController.accent,
                    onTap: () => Navigator.of(dialogContext).pop(swatch),
                  ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );

    if (chosen != null) {
      await accentController.setAccent(chosen);
    }
  }

  Widget _buildConsoleToggle(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Tooltip(
      message: showDebugConsole ? 'Hide log console' : 'Show log console',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onToggleDebugConsole,
          child: Ink(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: showDebugConsole
                  ? accent.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: showDebugConsole ? accent.withValues(alpha: 0.6) : kBorder,
              ),
            ),
            child: Icon(
              Icons.terminal,
              size: 18,
              color: showDebugConsole ? accent : kTextSecondary,
            ),
          ),
        ),
      ),
    );
  }

  static final ButtonStyle _iconButtonStyle = OutlinedButton.styleFrom(
    padding: EdgeInsets.zero,
    minimumSize: const Size(38, 38),
    fixedSize: const Size(38, 38),
  );
}

class _AccentSwatch extends StatefulWidget {
  const _AccentSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_AccentSwatch> createState() => _AccentSwatchState();
}

class _AccentSwatchState extends State<_AccentSwatch> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '#${widget.color.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedScale(
            scale: _hovered ? 1.1 : 1,
            duration: kFastMotion,
            curve: Curves.easeOut,
            child: Container(
              width: 40,
              height: 40,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.selected ? widget.color : Colors.transparent,
                  width: 2,
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  border: Border.all(color: kBorder),
                ),
                child: widget.selected
                    ? Icon(Icons.check, size: 18, color: onAccentFor(widget.color))
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
