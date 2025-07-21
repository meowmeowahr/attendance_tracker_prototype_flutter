import 'dart:convert';
import 'dart:io';
import 'package:attendance_tracker/settings.dart';
import 'package:attendance_tracker/string_ext.dart';
import 'package:attendance_tracker/widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class PinKeypad extends StatelessWidget {
  final Function(String) onKeyPressed;
  final Function() onClear;
  final Function() onBackspace;

  const PinKeypad({
    super.key,
    required this.onKeyPressed,
    required this.onClear,
    required this.onBackspace,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKey(context, '1'),
            const SizedBox(width: 8),
            _buildKey(context, '2'),
            const SizedBox(width: 8),
            _buildKey(context, '3'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKey(context, '4'),
            const SizedBox(width: 8),
            _buildKey(context, '5'),
            const SizedBox(width: 8),
            _buildKey(context, '6'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKey(context, '7'),
            const SizedBox(width: 8),
            _buildKey(context, '8'),
            const SizedBox(width: 8),
            _buildKey(context, '9'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildKey(context, 'C', onPressed: onClear),
            const SizedBox(width: 8),
            _buildKey(context, '0'),
            const SizedBox(width: 8),
            _buildKey(context, '⌫', onPressed: onBackspace),
          ],
        ),
      ],
    );
  }

  Widget _buildKey(
    BuildContext context,
    String label, {
    VoidCallback? onPressed,
  }) {
    return ElevatedButton(
      onPressed: onPressed ?? () => onKeyPressed(label),
      style: ElevatedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        fixedSize: const Size(64, 64),
        padding: const EdgeInsets.all(8),
        backgroundColor: Theme.of(context).primaryColor.withAlpha(200),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage(this.themeController, {super.key});

  final ThemeController themeController;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _settingsManager = SettingsManager();
  final _oauthController = TextEditingController();
  final _sheetIdController = TextEditingController();
  final _pinController = TextEditingController();
  String? _currentTheme;
  String? _currentAccentColor;
  String _enteredPin = '';
  bool _isPinVerified = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _settingsManager.init();
    _oauthController.text =
        (await _settingsManager.getValue<String>('google.oauth_credentials')) ??
        '';
    _sheetIdController.text =
        (await _settingsManager.getValue<String>('google.sheet_id')) ?? '';
    _pinController.text =
        (await _settingsManager.getValue<String>('security.pin')) ?? '';
    _currentTheme =
        (await _settingsManager.getValue<String>('app.theme.mode')) ?? 'light';
    _currentAccentColor =
        (await _settingsManager.getValue<String>('app.theme.accent')) ?? 'blue';
    setState(() {});
  }

  Future<bool> _verifyPin(String enteredPin) async {
    final storedPin =
        await _settingsManager.getValue<String>('security.pin') ?? '';
    return storedPin.isEmpty || storedPin == enteredPin;
  }

  Widget _buildPinEntry(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings Lock')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Enter PIN or Scan Admin Badge',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    6,
                    (index) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index < _enteredPin.length
                            ? Theme.of(context).primaryColor
                            : Colors.grey.withOpacity(0.3),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 32),
            PinKeypad(
              onKeyPressed: (key) {
                if (_enteredPin.length < 6) {
                  setState(() {
                    _enteredPin += key;
                  });
                  if (_enteredPin.length == 6) {
                    _verifyAndProceed();
                  }
                }
              },
              onClear: () {
                setState(() {
                  _enteredPin = '';
                });
              },
              onBackspace: () {
                if (_enteredPin.isNotEmpty) {
                  setState(() {
                    _enteredPin = _enteredPin.substring(
                      0,
                      _enteredPin.length - 1,
                    );
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _verifyAndProceed() async {
    if (await _verifyPin(_enteredPin)) {
      setState(() {
        _isPinVerified = true;
      });
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid PIN')));
      setState(() {
        _enteredPin = '';
      });
    }
  }

  Future<void> _editSheetId(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google Sheet ID'),
        content: TextField(
          controller: _sheetIdController,
          decoration: const InputDecoration(hintText: 'Enter Sheet ID'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _settingsManager.setValue(
                'google.sheet_id',
                _sheetIdController.text,
              );
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editGoogleOauth(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Google OAuth Credentials'),
        content: TextField(
          controller: _oauthController,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Enter OAuth JSON'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                jsonDecode(_oauthController.text);
                await _settingsManager.setValue(
                  'google.oauth_credentials',
                  _oauthController.text,
                );
                Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid JSON format')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editAppTheme(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'light', label: Text('Light')),
                ButtonSegment(value: 'dark', label: Text('Dark')),
              ],
              selected: {_currentTheme ?? 'dark'},
              onSelectionChanged: (newSelection) {
                final selectedTheme = newSelection.first;
                setState(() => _currentTheme = selectedTheme);
                _settingsManager.setValue('app.theme.mode', selectedTheme);
                widget.themeController.updateTheme(selectedTheme);
              },
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'red', label: Text('Red')),
                ButtonSegment(value: 'green', label: Text('Green')),
                ButtonSegment(value: 'blue', label: Text('Blue')),
                ButtonSegment(value: 'yellow', label: Text('Yellow')),
              ],
              selected: {_currentAccentColor ?? 'blue'},
              onSelectionChanged: (newSelection) {
                final selectedColor = newSelection.first;
                setState(() => _currentAccentColor = selectedColor);
                _settingsManager.setValue('app.theme.accent', selectedColor);
                widget.themeController.updateAccent(selectedColor);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPin(BuildContext context) async {
    final _formKey = GlobalKey<FormState>();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset PIN'),
        content: Form(
          key: _formKey,
          child: TextFormField(
            controller: _pinController,
            decoration: const InputDecoration(
              hintText: 'Enter new PIN',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
            obscureText: true,
            maxLength: 6,
            validator: (value) {
              if (value == null || value.length != 6) {
                return 'PIN must be 6 digits';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              if (_formKey.currentState?.validate() ?? false) {
                await _settingsManager.setValue(
                  'security.pin',
                  _pinController.text,
                );
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportSettings(BuildContext context) async {
    try {
      final json = await _settingsManager.exportToJson();
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Settings',
        fileName: 'settings.json',
      );
      if (result != null) {
        final file = File(result);
        await file.writeAsString(json);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings exported successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to export settings')),
      );
    }
  }

  Future<void> _importSettings(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final json = await file.readAsString();
        await _settingsManager.importFromJson(json);
        await _loadSettings();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings imported successfully')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to import settings')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isPinVerified) {
      return _buildPinEntry(context);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  title: const Text("Google OAuth JSON Credentials"),
                  subtitle: const Text(
                    "The JSON file containing your Google OAuth credentials for accessing the Google Sheets API.",
                  ),
                  leading: const Icon(Icons.cloud),
                  trailing: IconButton(
                    onPressed: () => _editGoogleOauth(context),
                    icon: const Icon(Icons.edit),
                  ),
                ),
                ListTile(
                  tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                  title: const Text('Google Sheet Spreadsheet ID'),
                  subtitle: const Text(
                    'The ID of the Google Sheet used for attendance tracking.',
                  ),
                  leading: const Icon(Icons.pages),
                  trailing: IconButton(
                    onPressed: () => _editSheetId(context),
                    icon: const Icon(Icons.edit),
                  ),
                ),
                ListTile(
                  title: const Text("App Theme"),
                  subtitle: Text(
                    "Mode: ${_currentTheme?.capitalize() ?? ''}, Accent: ${_currentAccentColor?.capitalize() ?? ''}",
                  ),
                  leading: const Icon(Icons.color_lens),
                  trailing: IconButton(
                    onPressed: () => _editAppTheme(context),
                    icon: const Icon(Icons.edit),
                  ),
                ),
                ListTile(
                  tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                  title: const Text("Reset PIN"),
                  subtitle: const Text(
                    "Reset the PIN used for accessing admin settings.",
                  ),
                  leading: const Icon(Icons.lock),
                  trailing: IconButton(
                    onPressed: () => _resetPin(context),
                    icon: const Icon(Icons.edit),
                  ),
                ),
                ListTile(
                  title: const Text("Export Settings"),
                  subtitle: const Text("Export settings as JSON file"),
                  leading: const Icon(Icons.download),
                  trailing: IconButton(
                    onPressed: () => _exportSettings(context),
                    icon: const Icon(Icons.downloading),
                  ),
                ),
                ListTile(
                  tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                  title: const Text("Import Settings"),
                  subtitle: const Text("Import settings from JSON file"),
                  leading: const Icon(Icons.upload),
                  trailing: IconButton(
                    onPressed: () => _importSettings(context),
                    icon: const Icon(Icons.upload_file),
                  ),
                ),
              ],
            ),
          ),
          AdminStriper(),
        ],
      ),
    );
  }
}
