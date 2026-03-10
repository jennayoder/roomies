import 'package:flutter/material.dart';

/// Holds the current app seed color so the theme can be changed at runtime.
class ThemeNotifier extends ChangeNotifier {
  Color _seedColor;

  ThemeNotifier(this._seedColor);

  Color get seedColor => _seedColor;

  void setSeedColor(Color color) {
    if (_seedColor == color) return;
    _seedColor = color;
    notifyListeners();
  }
}
