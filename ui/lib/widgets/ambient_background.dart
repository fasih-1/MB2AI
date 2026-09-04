import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The ambient wash behind the dashboard.
///
/// On the dark ground this is a subtle lift toward the top-left plus two very
/// low-alpha accent orbs — enough to keep large flat areas from looking dead,
/// without competing with the panels.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: <Widget>[
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(-0.35, -0.55),
                  radius: 1.35,
                  colors: <Color>[
                    Color(0xFF1B2432),
                    Color(0xFF141A23),
                    kAppBackground,
                  ],
                  stops: <double>[0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: 40,
            right: -60,
            child: _orb(300, kAccentGlow.withValues(alpha: 0.06)),
          ),
          Positioned(
            bottom: -70,
            left: -40,
            child: _orb(240, kAccentBlue.withValues(alpha: 0.04)),
          ),
        ],
      ),
    );
  }

  Widget _orb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: <Color>[color, color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}
