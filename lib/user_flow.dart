import 'package:attendance_tracker/backend.dart';
import 'package:attendance_tracker/passwords.dart';
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
  bool _isSettingPin = false;
  bool _isResettingPin = false;
  String _newPin = '';
  String _pinError = '';

  @override
  void initState() {
    super.initState();
    _selectedLocation = widget.allowedLocations?.first;
    _loadSettings();
    if (widget.user.passwordHash == null && widget.user.privilege != MemberPrivilege.student) {
      _isSettingPin = true;
    }
  }

  Future<void> _loadSettings() async {
    await _settingsManager.init();
    setState(() {});
  }

  Future<bool> _verifyPin(String enteredPin) async {
    return widget.user.passwordHash == hashPin(enteredPin);
  }

  Widget _buildPinSetter(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Flex(
            direction: orientation == Orientation.portrait
                ? Axis.vertical
                : Axis.horizontal,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _isResettingPin ? "Please Wait" : 'Set a 6-digit PIN',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 16),
                  if (!_isResettingPin)
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
                          color: index < _newPin.length
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.surfaceContainerHigh,
                        ),
                      ),
                    ),
                  ),
                  if (_pinError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        _pinError,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  if (_isResettingPin)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
              SizedBox(
                width: orientation == Orientation.portrait ? 0 : 32,
                height: orientation == Orientation.portrait ? 32 : 0,
              ),
              if (!_isResettingPin)
                PinKeypad(
                  onKeyPressed: (key) async {
                    if (_newPin.length < 6) {
                      setState(() {
                        _newPin += key;
                        _pinError = '';
                      });
                      if (_newPin.length == 6) {
                        setState(() {
                          _isResettingPin = true;
                        });
                        try {
                          await widget.backend.resetPassword(widget.user.id, _newPin);
                          setState(() {
                            _isSettingPin = false;
                            _isResettingPin = false;
                            _enteredPin = '';
                            _pinError = '';
                            _isPinVerified = true;
                          });
                        } catch (e) {
                          setState(() {
                            _pinError = 'Failed to set PIN. Please try again.';
                            _newPin = '';
                            _isResettingPin = false;
                          });
                        }
                      }
                    }
                  },
                  onClear: () {
                    setState(() {
                      _newPin = '';
                      _pinError = '';
                    });
                  },
                  onBackspace: () {
                    if (_newPin.isNotEmpty) {
                      setState(() {
                        _newPin = _newPin.substring(0, _newPin.length - 1);
                        _pinError = '';
                      });
                    }
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPinEntry(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Flex(
            direction: orientation == Orientation.portrait
                ? Axis.vertical
                : Axis.horizontal,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Enter PIN',
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
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(
                width: orientation == Orientation.portrait ? 0 : 32,
                height: orientation == Orientation.portrait ? 32 : 0,
              ),
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
                          SnackBar(
                            content: Text('Invalid PIN'),
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                          ),
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isSettingPin) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
          foregroundColor: Theme.of(context).colorScheme.onSurface,
          title: Text(widget.user.name),
        ),
        body: _buildPinSetter(context),
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: Text(widget.user.name),
      ),
      body:
          !_isPinVerified &&
              widget.user.privilege == MemberPrivilege.admin &&
              (_settingsManager.getValue<bool>("security.pin.require") ??
                  true) &&
              widget.requireAdminPinEntry
          ? _buildPinEntry(context)
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Column(
                  children: [
                    Text("ID: ${widget.user.id}"),
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
                    if (widget.user.status == AttendanceStatus.present)
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
                          initialValue: _selectedLocation,

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
                                widget.user.status == AttendanceStatus.out
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
                              padding: const EdgeInsets.all(18.0),
                              child: Text(
                                "Clock In",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: FilledButton(
                            onPressed:
                                widget.user.status == AttendanceStatus.present
                                ? () {
                                    setState(() {
                                      widget.backend.clockOut(widget.user.id);
                                    });
                                    Navigator.of(context).pop();
                                  }
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.all(18.0),
                              child: Text(
                                "Clock Out",
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
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
