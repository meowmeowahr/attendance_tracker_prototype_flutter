import 'dart:io' show Platform;
import 'package:attendance_tracker/settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/services.dart';

class AndroidLockdownPage extends StatefulWidget {
  const AndroidLockdownPage({super.key});

  @override
  State<AndroidLockdownPage> createState() => _AndroidLockdownPageState();
}

class _AndroidLockdownPageState extends State<AndroidLockdownPage> {
  static const platform = MethodChannel(
    'org.mckinneysteamacademy.second/lockdown',
  );

  bool _isDefaultLauncher = false;
  final _settingsManager = SettingsManager();

  @override
  void initState() {
    super.initState();
    _checkDefaultLauncher();
  }

  Future<void> _checkDefaultLauncher() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      final bool result = await platform.invokeMethod('isDefaultLauncher');
      setState(() {
        _isDefaultLauncher = result;
      });
    } on PlatformException {
      setState(() {
        _isDefaultLauncher = false;
      });
    }
  }

  void _openHomeSettings() {
    if (!kIsWeb && Platform.isAndroid) {
      final intent = AndroidIntent(action: 'android.settings.HOME_SETTINGS');
      intent.launch().then((_) async {
        await platform.invokeMethod('restartToHome');
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Launcher settings are only available on Android'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Android Lockdown')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Default Launcher'),
            subtitle: Text(
              _isDefaultLauncher
                  ? '🎉 This app is the default launcher'
                  : 'Not the default launcher',
            ),
            trailing: IconButton(
              onPressed: _openHomeSettings,
              icon: const Icon(Icons.settings),
            ),
            leading: const Icon(Icons.rocket),
          ),
          ListTile(
            title: const Text("Enable Immersive/Fullscreen UI"),
            subtitle: const Text(
              "Hide system bars for a fullscreen experience",
            ),
            leading: const Icon(Icons.pin),
            trailing: Switch(
              value:
                  _settingsManager.getValue<bool>("android.immersive") ?? false,
              onChanged: (value) {
                setState(() {
                  _settingsManager.setValue("android.immersive", value);
                });
                if (_settingsManager.getValue<bool>("android.immersive") ??
                    _settingsManager.getDefault<bool>("android.immersive")!) {
                  SystemChrome.setEnabledSystemUIMode(
                    SystemUiMode.immersiveSticky,
                  );
                } else {
                  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
                }
              },
            ),
          ),
          ListTile(
            title: const Text("Absorb Volume Keys"),
            subtitle: const Text(
              "Disable volume button functionality (prevent settings access)",
            ),
            leading: const Icon(Icons.volume_off),
            trailing: Switch(
              value:
                  _settingsManager.getValue<bool>("android.absorbvolume") ??
                  false,
              onChanged: (value) async {
                setState(() {
                  _settingsManager.setValue("android.absorbvolume", value);
                });
                await platform.invokeMethod('setAbsorbVolumeKeys', {
                  'enabled': value,
                });
              },
            ),
          ),
        ],
      ),
    );
  }
}
