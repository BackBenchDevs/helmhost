import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:helmhost/prefs.dart';
import 'package:helmhost/session_helpers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppPrefs round-trip', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('themeMode', () async {
      final prefs = await AppPrefs.open();
      expect(prefs.themeMode, ThemeMode.system);
      await prefs.setThemeMode(ThemeMode.dark);
      expect(prefs.themeMode, ThemeMode.dark);
      await prefs.setThemeMode(ThemeMode.light);
      expect(prefs.themeMode, ThemeMode.light);
    });

    test('libraryViewMode', () async {
      final prefs = await AppPrefs.open();
      expect(prefs.libraryViewMode, LibraryViewMode.grid);
      await prefs.setLibraryViewMode(LibraryViewMode.list);
      expect(prefs.libraryViewMode, LibraryViewMode.list);
    });

    test('viewScaleMode', () async {
      final prefs = await AppPrefs.open();
      expect(prefs.viewScaleMode, ViewScaleMode.fit);
      await prefs.setViewScaleMode(ViewScaleMode.fill);
      expect(prefs.viewScaleMode, ViewScaleMode.fill);
    });

    test('sessionShell', () async {
      final prefs = await AppPrefs.open();
      expect(prefs.sessionShell, SessionShell.windows);
      await prefs.setSessionShell(SessionShell.tabs);
      expect(prefs.sessionShell, SessionShell.tabs);
    });
  });
}
