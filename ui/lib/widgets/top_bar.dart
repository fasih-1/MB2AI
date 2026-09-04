import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The slim application toolbar.
///
/// Only holds actions that are always meaningful: syncing, browsing the vault,
/// and the debug console. Anything that needs a selected task lives down in
/// GenerationControls instead, so the bar does not present dead controls.
class TopBar extends StatelessWidget {
  const TopBar({
    super.key,
    required this.isVaultLoading,
    required this.showDebugConsole,
    required this.onScrape,
    required this.onOpenVault,
    required this.onToggleDebugConsole,
  });

  final bool isVaultLoading;
  final bool showDebugConsole;
  final VoidCallback onScrape;
  final VoidCallback onOpenVault;
  final VoidCallback onToggleDebugConsole;

  /// Below this the labelled buttons no longer fit beside the wordmark.
  static const double _compactBreakpoint = 420;

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
              _buildConsoleToggle(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWordmark(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ShaderMask(
      shaderCallback: (Rect bounds) {
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[kAccentGlow, kAccentBlue, Color(0xFF7EE0FF)],
          stops: <double>[0.0, 0.55, 1.0],
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

  Widget _buildConsoleToggle() {
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
                  ? kAccentBlue.withValues(alpha: 0.16)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: showDebugConsole
                    ? kAccentBlue.withValues(alpha: 0.6)
                    : kBorder,
              ),
            ),
            child: Icon(
              Icons.terminal,
              size: 18,
              color: showDebugConsole ? kAccentBlue : kTextSecondary,
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
