import 'package:attendance_tracker/backend.dart';
import 'package:attendance_tracker/settings.dart';
import 'package:attendance_tracker/settings_page.dart';
import 'package:flutter/material.dart';

class UserFlow extends StatefulWidget {
  final Member user;
  final AttendanceTrackerBackend backend;
  final bool requireAdminPinEntry;
  final String? fixedLocation;
  final List<String>? allowedLocations;
  final bool fixed;

  const UserFlow(
    this.user,
    this.backend, {
    super.key,
    this.requireAdminPinEntry = true,
    this.fixedLocation,
    this.allowedLocations,
    this.fixed = false,
  });

  @override
  State<UserFlow> createState() => _UserFlowState();
}

class _UserFlowState extends State<UserFlow> {
  final _settingsManager = SettingsManager();
  String _enteredPin = '';
  bool _isPinVerified = false;
  String? _selectedLocation;

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.allowedLocations?.first;
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
                          : Theme.of(context).colorScheme.surfaceContainerHigh,
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
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Column(
                  children: [
                    Spacer(),
                    CircleAvatar(
                      radius: 128,
                      child: Text(
                        widget.user.name
                            .split(' ')
                            .map((part) => part[0])
                            .take(2)
                            .join(),
                        style: TextStyle(
                          fontSize: 84,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Spacer(),
                    if (widget.user.status == AttendanceStatus.active)
                      Text(
                        "Leaving: ${widget.user.location}",
                        style: Theme.of(context).textTheme.bodyLarge,
                      )
                    else if (widget.fixed)
                      Text(
                        "Location: ${widget.fixedLocation}",
                        style: Theme.of(context).textTheme.bodyLarge,
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(left: 24.0, right: 24.0),
                        child: DropdownButtonFormField<String>(
                          value: _selectedLocation,

                          onChanged: (value) {
                            setState(() {
                              _selectedLocation = value!;
                            });
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: "Location",
                          ),
                          items: widget.allowedLocations!.map((location) {
                            return DropdownMenuItem<String>(
                              value: location,
                              child: Text(location),
                            );
                          }).toList(),
                        ),
                      ),
                    SizedBox(height: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed:
                                widget.user.status == AttendanceStatus.inactive
                                ? () {
                                    setState(() {
                                      widget.backend.clockIn(
                                        widget.user.id,
                                        widget.fixed
                                            ? widget.fixedLocation!
                                            : _selectedLocation!,
                                      );
                                    });
                                    Navigator.of(context).pop();
                                  }
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text("Clock In"),
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed:
                                widget.user.status == AttendanceStatus.active
                                ? () {
                                    setState(() {
                                      widget.backend.clockOut(widget.user.id);
                                    });
                                    Navigator.of(context).pop();
                                  }
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Text("Clock Out"),
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
