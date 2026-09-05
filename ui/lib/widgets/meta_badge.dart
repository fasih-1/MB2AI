import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A compact pill for task metadata: assessment type, weight, criteria.
///
/// Deliberately quiet by default so a row of them does not compete with the
/// task title. [emphasised] lifts the one piece of metadata that changes how a
/// task should be treated — currently whether it is summative.
class MetaBadge extends StatelessWidget {
  const MetaBadge({
    super.key,
    required this.label,
    this.icon,
    this.emphasised = false,
    this.tooltip,
  });

  final String label;
  final IconData? icon;
  final bool emphasised;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    final foreground = emphasised ? accent : kTextSecondary;

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: emphasised
            ? accent.withValues(alpha: 0.12)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: emphasised ? accent.withValues(alpha: 0.4) : kBorder,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: foreground),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: textTheme.bodySmall?.copyWith(
              fontSize: 11,
              height: 1.2,
              color: foreground,
              fontWeight: emphasised ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    if (tooltip == null) {
      return pill;
    }
    return Tooltip(message: tooltip!, child: pill);
  }
}
