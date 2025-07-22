import 'package:attendance_tracker/backend.dart';
import 'package:attendance_tracker/settings.dart';
import 'package:attendance_tracker/settings_page.dart';
import 'package:flutter/material.dart';

class UserFlow extends StatefulWidget {
  final Member user;
  final bool requireAdminPinEntry;

  const UserFlow(this.user, {super.key, this.requireAdminPinEntry = true});

  @override
  State<UserFlow> createState() => _UserFlowState();
}

class _UserFlowState extends State<UserFlow> {
  final _settingsManager = SettingsManager();
  String _enteredPin = '';
  bool _isPinVerified = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    await _settingsManager.init();
    setState(() {});
  }

  Future<bool> _verifyPin(String enteredPin) async {
    final storedPin = _settingsManager.getValue<String>('security.pin') ?? '';
    return storedPin.isEmpty || storedPin == enteredPin;
  }

  Widget _buildPinEntry(BuildContext context) {
    return Padding(
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
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.surfaceBright,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 32),
          PinKeypad(
            onKeyPressed: (key) async {
              if (_enteredPin.length < 6) {
                setState(() {
                  _enteredPin += key;
                });
                if (_enteredPin.length == 6) {
                  if (await _verifyPin(_enteredPin)) {
                    setState(() {
                      _isPinVerified = true;
                    });
                  } else {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Invalid PIN')),
                    );
                    setState(() {
                      _enteredPin = '';
                    });
                  }
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: Text(widget.user.name),
      ),
      body: !_isPinVerified && widget.user.privilege == MemberPrivilege.admin
          ? _buildPinEntry(context)
          : Placeholder(),
    );
  }
}
