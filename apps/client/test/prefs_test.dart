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

    test('libraryGridSize defaults to medium', () async {
      final prefs = await AppPrefs.open();
      expect(prefs.libraryGridSize, LibraryGridSize.medium);
      await prefs.setLibraryGridSize(LibraryGridSize.small);
      expect(prefs.libraryGridSize, LibraryGridSize.small);
      await prefs.setLibraryGridSize(LibraryGridSize.large);
      expect(prefs.libraryGridSize, LibraryGridSize.large);
      await prefs.setLibraryGridSize(LibraryGridSize.medium);
      expect(prefs.libraryGridSize, LibraryGridSize.medium);
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

    test('librarySort defaults to name', () async {
      final prefs = await AppPrefs.open();
      expect(prefs.librarySort, LibrarySort.name);
      await prefs.setLibrarySort(LibrarySort.host);
      expect(prefs.librarySort, LibrarySort.host);
      await prefs.setLibrarySort(LibrarySort.lastConnected);
      expect(prefs.librarySort, LibrarySort.lastConnected);
      await prefs.setLibrarySort(LibrarySort.openFirst);
      expect(prefs.librarySort, LibrarySort.openFirst);
    });

    test('libraryThumbRefresh defaults to normal', () async {
      final prefs = await AppPrefs.open();
      expect(prefs.libraryThumbRefresh, LibraryThumbRefresh.normal);
      await prefs.setLibraryThumbRefresh(LibraryThumbRefresh.off);
      expect(prefs.libraryThumbRefresh, LibraryThumbRefresh.off);
      await prefs.setLibraryThumbRefresh(LibraryThumbRefresh.slow);
      expect(prefs.libraryThumbRefresh, LibraryThumbRefresh.slow);
    });

    test('libraryGridExtent get/set/clear', () async {
      final prefs = await AppPrefs.open();
      expect(prefs.libraryGridExtent, isNull);
      await prefs.setLibraryGridExtent(280.0);
      expect(prefs.libraryGridExtent, 280.0);
      await prefs.clearLibraryGridExtent();
      expect(prefs.libraryGridExtent, isNull);
    });

    test('setLibraryGridExtent stores raw value without clamping', () async {
      // Prefs stores the raw double; clamping is in clampLibraryGridExtent.
      final prefs = await AppPrefs.open();
      await prefs.setLibraryGridExtent(500.0);
      expect(prefs.libraryGridExtent, 500.0);
    });
  });
}
