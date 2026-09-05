import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Tutor / Ghostwriter switch, with the accent pill sliding between segments.
///
/// [pulseToken] is bumped by the parent on every change to replay the glow.
class ModeSelector extends StatelessWidget {
  const ModeSelector({
    super.key,
    required this.mode,
    required this.pulseToken,
    required this.onModeChanged,
  });

  final String mode;
  final int pulseToken;
  final ValueChanged<String> onModeChanged;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final onAccent = Theme.of(context).colorScheme.onPrimary;

    return Container(
      width: 240,
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: kAppBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final segmentWidth = constraints.maxWidth / 2;
          return Stack(
            children: <Widget>[
              AnimatedPositioned(
                duration: const Duration(milliseconds: 380),
                curve: Curves.easeInOutCubic,
                left: mode == 'tutor' ? 0 : segmentWidth,
                top: 0,
                bottom: 0,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('mode_pulse_$pulseToken'),
                  tween: Tween<double>(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOut,
                  builder: (context, value, _) {
                    final pulse = 1 - value;
                    return Container(
                      width: segmentWidth,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: accentGlow(
                          accent,
                          opacity: 0.22 + (pulse * 0.16),
                          blur: 14 + (pulse * 10),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Row(
                children: <Widget>[
                  _buildSegment(
                    context,
                    value: 'tutor',
                    label: 'Tutor',
                    onAccent: onAccent,
                  ),
                  _buildSegment(
                    context,
                    value: 'ghostwriter',
                    label: 'Ghostwriter',
                    onAccent: onAccent,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context, {
    required String value,
    required String label,
    required Color onAccent,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final accent = Theme.of(context).colorScheme.primary;
    final isSelected = mode == value;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          hoverColor: isSelected
              ? Colors.white.withValues(alpha: 0.06)
              : accent.withValues(alpha: 0.10),
          onTap: () {
            if (mode == value) {
              return;
            }
            onModeChanged(value);
          },
          child: Center(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: textTheme.labelLarge?.copyWith(
                fontSize: 13,
                color: isSelected ? onAccent : kTextSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Generate button that morphs into a circular spinner while a draft is being
/// generated.
class GenerateDraftButton extends StatelessWidget {
  const GenerateDraftButton({
    super.key,
    required this.isBusy,
    required this.onPressed,
  });

  final bool isBusy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final onAccent = Theme.of(context).colorScheme.onPrimary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      width: isBusy ? 40 : 150,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isBusy ? 20 : 12),
        boxShadow: isBusy ? accentGlow(accent, opacity: 0.34, blur: 22) : null,
      ),
      child: ElevatedButton(
        onPressed: isBusy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: accent,
          disabledBackgroundColor: accent,
          foregroundColor: onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isBusy ? 20 : 12),
          ),
        ),
        child: AnimatedSwitcher(
          duration: kMediumMotion,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: isBusy
              ? SizedBox(
                  key: const ValueKey('generate_busy'),
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(onAccent),
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
                        Icon(Icons.bolt, size: 17),
                        SizedBox(width: 7),
                        Text('Generate'),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
