import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_helpers.dart';

const _kThemeMode = 'helmhost.themeMode';
const _kLibraryViewMode = 'helmhost.libraryViewMode';
const _kViewScaleMode = 'helmhost.viewScaleMode';
const _kSessionShell = 'helmhost.sessionShell';

class AppPrefs {
  AppPrefs._(this._p);
  final SharedPreferences _p;

  static Future<AppPrefs> open() async {
    final p = await SharedPreferences.getInstance();
    return AppPrefs._(p);
  }

  ThemeMode get themeMode {
    switch (_p.getString(_kThemeMode)) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final v = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _p.setString(_kThemeMode, v);
  }

  LibraryViewMode get libraryViewMode {
    switch (_p.getString(_kLibraryViewMode)) {
      case 'list':
        return LibraryViewMode.list;
      default:
        return LibraryViewMode.grid;
    }
  }

  Future<void> setLibraryViewMode(LibraryViewMode mode) async {
    final v = mode == LibraryViewMode.list ? 'list' : 'grid';
    await _p.setString(_kLibraryViewMode, v);
  }

  ViewScaleMode get viewScaleMode =>
      ViewScaleModeX.fromPrefs(_p.getString(_kViewScaleMode));

  Future<void> setViewScaleMode(ViewScaleMode mode) async {
    await _p.setString(_kViewScaleMode, mode.prefsKey);
  }

  SessionShell get sessionShell =>
      SessionShellX.fromPrefs(_p.getString(_kSessionShell));

  Future<void> setSessionShell(SessionShell shell) async {
    await _p.setString(_kSessionShell, shell.prefsKey);
  }
}

ThemeData helmTheme(Brightness brightness) {
  const seed = Color(0xFF1B4D3E);
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.tertiaryContainer,
      labelStyle: TextStyle(color: scheme.onTertiaryContainer),
    ),
  );
}
