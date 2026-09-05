import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

/// Holds the user's chosen accent colour and persists it across launches.
///
/// A plain [ChangeNotifier] rather than a state-management package: the app
/// has no other shared app-wide state, so one small notifier read via
/// [ListenableBuilder] at the app root is enough, and it keeps this setting
/// consistent with the rest of the codebase's explicit, prop-drilled style.
class AccentColorController extends ChangeNotifier {
  AccentColorController() : _accent = kDefaultAccent;

  static const String _prefsKey = 'mb2ai_accent_color_argb';

  Color _accent;
  Color get accent => _accent;

  /// Reads the saved colour, if any. Call once before the first frame; a
  /// missing or unreadable value quietly keeps the default rather than
  /// failing app startup.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(_prefsKey);
      if (stored != null) {
        _accent = Color(stored);
        notifyListeners();
      }
    } catch (_) {
      // Local settings storage is a convenience, not a requirement.
    }
  }

  Future<void> setAccent(Color color) async {
    if (color == _accent) {
      return;
    }
    _accent = color;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, color.toARGB32());
    } catch (_) {
      // The colour still applies for this session even if saving it failed.
    }
  }
}
