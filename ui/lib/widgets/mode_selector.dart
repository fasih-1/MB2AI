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
    return Container(
      width: 270,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(kCardRadius),
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
                  _buildSegment(context, value: 'tutor', label: 'Tutor'),
                  _buildSegment(
                    context,
                    value: 'ghostwriter',
                    label: 'Ghostwriter',
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
  }) {
    final textTheme = Theme.of(context).textTheme;
    final isSelected = mode == value;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          hoverColor: isSelected
              ? kAccentBlue.withValues(alpha: 0.22)
              : kAccentBlue.withValues(alpha: 0.08),
          onTap: () {
            if (mode == value) {
              return;
            }
            onModeChanged(value);
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
        onPressed: isBusy ? null : onPressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: kAccentBlue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isBusy ? 24 : 12),
          ),
        ),
        child: AnimatedSwitcher(
          duration: kMediumMotion,
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
}
