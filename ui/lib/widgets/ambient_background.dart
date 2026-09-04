import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The decorative radial wash and accent orbs behind the dashboard.
///
/// Purely presentational and non-interactive, so it stays out of the
/// dashboard's build method.
class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
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
                    kEdgeTint,
                  ],
                  stops: const <double>[0.0, 0.58, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: 54,
            right: -40,
            child: _orb(280, kAccentBlue.withValues(alpha: 0.07)),
          ),
          Positioned(
            bottom: -50,
            left: -20,
            child: _orb(220, kAccentBlue.withValues(alpha: 0.04)),
          ),
        ],
      ),
    );
  }

  Widget _orb(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
