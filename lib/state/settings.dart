import 'dart:ui';

import 'package:flutter/material.dart';

import '../api/storage.dart';

/// Language and light/dark, saved on the device.
class Settings extends ChangeNotifier {
  Settings(this._storage)
      : language = _initialLanguage(_storage.getString(Storage.language)),
        themeMode = switch (_storage.getString(Storage.theme)) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };

  final Storage _storage;
  String language;
  ThemeMode themeMode;

  static String _initialLanguage(String? saved) {
    const known = ['uz', 'ru', 'en'];
    if (known.contains(saved)) return saved!;
    final device = PlatformDispatcher.instance.locale.languageCode;
    return known.contains(device) ? device : 'uz';
  }

  void setLanguage(String code) {
    language = code;
    _storage.setString(Storage.language, code);
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    themeMode = mode;
    _storage.setString(
        Storage.theme, mode == ThemeMode.system ? null : mode.name);
    notifyListeners();
  }
}
