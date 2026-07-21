import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'library/hub_page.dart';
import 'prefs.dart';
import 'session/session_ipc.dart';
import 'session/session_page.dart';
import 'session_helpers.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  final controller = await WindowController.fromCurrentEngine();
  final raw = controller.arguments.trim();
  Map<String, dynamic> winArgs = {};
  if (raw.isNotEmpty) {
    try {
      winArgs = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      winArgs = {};
    }
  }

  final prefs = await AppPrefs.open();
  final role = winArgs['role'] as String? ?? 'hub';
  if (role == 'session') {
    await controller.setWindowMethodHandler((call) async {
      switch (call.method) {
        case kMethodWindowClose:
          await windowManager.close();
          return null;
        default:
          throw MissingPluginException(call.method);
      }
    });
    final sessionId = (winArgs['sessionId'] as num).toInt();
    final title = winArgs['title'] as String? ?? 'Session';
    final entryId = winArgs['entryId'] as String? ?? title;
    final host = winArgs['host'] as String? ??
        (entryId.contains(':') ? entryId.split(':').first : entryId);
    final port = (winArgs['port'] as num?)?.toInt() ??
        (entryId.contains(':')
            ? int.tryParse(entryId.split(':').last) ?? 5900
            : 5900);
    final username = winArgs['username'] as String?;
    final preferVencrypt = winArgs['prefer_vencrypt'] as bool? ?? false;
    final acceptInvalidCerts =
        winArgs['accept_invalid_certs'] as bool? ?? false;
    await windowManager.setTitle(title);
    runApp(SessionApp(
      sessionId: sessionId,
      title: title,
      entryId: entryId,
      host: host,
      port: port,
      username: username,
      preferVencrypt: preferVencrypt,
      acceptInvalidCerts: acceptInvalidCerts,
      themeMode: prefs.themeMode,
      prefs: prefs,
    ));
  } else {
    await windowManager.setTitle('Helmhost');
    runApp(HubApp(prefs: prefs));
  }
}

class HubApp extends StatefulWidget {
  const HubApp({super.key, required this.prefs});

  final AppPrefs prefs;

  @override
  State<HubApp> createState() => _HubAppState();
}

class _HubAppState extends State<HubApp> {
  late ThemeMode _themeMode;
  late LibraryViewMode _viewMode;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.prefs.themeMode;
    _viewMode = widget.prefs.libraryViewMode;
  }

  Future<void> _setTheme(ThemeMode mode) async {
    setState(() => _themeMode = mode);
    await widget.prefs.setThemeMode(mode);
  }

  Future<void> _setViewMode(LibraryViewMode mode) async {
    setState(() => _viewMode = mode);
    await widget.prefs.setLibraryViewMode(mode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Helmhost',
      theme: helmTheme(Brightness.light),
      darkTheme: helmTheme(Brightness.dark),
      themeMode: _themeMode,
      home: HubPage(
        themeMode: _themeMode,
        onThemeModeChanged: _setTheme,
        viewMode: _viewMode,
        onViewModeChanged: _setViewMode,
      ),
    );
  }
}

class SessionApp extends StatelessWidget {
  const SessionApp({
    super.key,
    required this.sessionId,
    required this.title,
    required this.host,
    required this.port,
    this.entryId,
    this.username,
    this.preferVencrypt = false,
    this.acceptInvalidCerts = false,
    this.themeMode = ThemeMode.system,
    this.prefs,
  });

  final int sessionId;
  final String title;
  final String host;
  final int port;
  final String? entryId;
  final String? username;
  final bool preferVencrypt;
  final bool acceptInvalidCerts;
  final ThemeMode themeMode;
  final AppPrefs? prefs;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      theme: helmTheme(Brightness.light),
      darkTheme: helmTheme(Brightness.dark),
      themeMode: themeMode,
      home: SessionPage(
        sessionId: sessionId,
        title: title,
        entryId: entryId,
        host: host,
        port: port,
        username: username,
        preferVencrypt: preferVencrypt,
        acceptInvalidCerts: acceptInvalidCerts,
        closeOnExit: true,
        prefs: prefs,
      ),
    );
  }
}
