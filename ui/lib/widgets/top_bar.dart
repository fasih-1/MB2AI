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

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: kSurface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(kCardRadius),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: <Widget>[
          ShaderMask(
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
              style: textTheme.headlineSmall?.copyWith(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onScrape,
            icon: const Icon(Icons.sync, size: 17),
            label: const Text('Scrape'),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: isVaultLoading ? null : onOpenVault,
            icon: isVaultLoading
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.inventory_2_outlined, size: 17),
            label: const Text('Vault'),
          ),
          const SizedBox(width: 10),
          Tooltip(
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
          ),
        ],
      ),
    );
  }
}
