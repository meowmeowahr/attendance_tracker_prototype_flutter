import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';

class ThemeController {
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.dark);
  final ValueNotifier<Color> accentColor = ValueNotifier(Colors.blue);

  void updateTheme(String mode) {
    themeMode.value = mode == 'light' ? ThemeMode.light : ThemeMode.dark;
  }

  void updateAccent(String name) {
    final colorMap = {
      'red': Colors.red,
      'green': Colors.green,
      'blue': Colors.blue,
      'yellow': Colors.yellow,
    };
    accentColor.value = colorMap[name] ?? Colors.blue;
  }
}

class SettingsManager {
  static const String _prefix = 'settings.';
  SharedPreferences? prefs;

  final Map<String, dynamic> _defaultSettings = {
    'google.oauth_credentials': '',
    'google.sheet_id': '',
    'app.theme.mode': 'dark',
    'app.theme.accent': 'blue',
    'station.fixed': true,
    'station.locations': [],
    'station.location': null,
    'security.pin': '',
  };

  SettingsManager._privateConstructor();
  static final SettingsManager _instance =
      SettingsManager._privateConstructor();
  factory SettingsManager() => _instance;

  Future<void> init() async {
    prefs = await SharedPreferences.getInstance();
    for (var entry in _defaultSettings.entries) {
      if (prefs == null || !prefs!.containsKey(_prefix + entry.key)) {
        await setValue(entry.key, entry.value);
      }
    }
  }

  T? getValue<T>(String key) {
    String fullKey = _prefix + key;
    if (T == String) {
      return prefs?.getString(fullKey) as T?;
    } else if (T == bool) {
      return prefs?.getBool(fullKey) as T?;
    } else if (T == int) {
      return prefs?.getInt(fullKey) as T?;
    } else if (T == double) {
      return prefs?.getDouble(fullKey) as T?;
    } else if (T == List<String>) {
      return prefs?.getStringList(fullKey) as T?;
    }
    throw Exception('Unsupported type: $T');
  }

  Future<void> setValue(String key, dynamic value) async {
    String fullKey = _prefix + key;
    if (value is String) {
      await prefs?.setString(fullKey, value);
    } else if (value is bool) {
      await prefs?.setBool(fullKey, value);
    } else if (value is int) {
      await prefs?.setInt(fullKey, value);
    } else if (value is double) {
      await prefs?.setDouble(fullKey, value);
    } else if (value is List<String>) {
      await prefs?.setStringList(fullKey, value);
    } else {
      return;
    }
  }

  Future<Map<String, dynamic>> exportSettings() async {
    Map<String, dynamic> settings = {};
    for (var key in _defaultSettings.keys) {
      settings[key] = await getValue<dynamic>(key);
    }
    return settings;
  }

  Future<void> importSettings(Map<String, dynamic> settings) async {
    for (var entry in settings.entries) {
      if (_defaultSettings.containsKey(entry.key)) {
        await setValue(entry.key, entry.value);
      }
    }
  }

  Future<String> exportToJson() async {
    final settings = await exportSettings();
    return jsonEncode(settings);
  }

  Future<void> importFromJson(String jsonString) async {
    try {
      final Map<String, dynamic> settings = jsonDecode(jsonString);
      await importSettings(settings);
    } catch (e) {
      throw Exception('Invalid JSON format');
    }
  }
}
