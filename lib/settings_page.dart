import 'dart:convert';
import 'dart:io';
import 'package:attendance_tracker/image_util.dart';
import 'package:attendance_tracker/serial.dart';
import 'package:attendance_tracker/settings.dart';
import 'package:attendance_tracker/string_ext.dart';
import 'package:attendance_tracker/util.dart';
import 'package:attendance_tracker/widgets.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
        (_settingsManager.getValue<String>('google.oauth_credentials')) ?? '';
    _sheetIdController.text =
        (_settingsManager.getValue<String>('google.sheet_id')) ?? '';
    _pinController.text =
        (_settingsManager.getValue<String>('security.pin')) ?? '';
    _currentTheme =
        (_settingsManager.getValue<String>('app.theme.mode')) ?? 'light';
    _currentAccentColor =
        (_settingsManager.getValue<String>('app.theme.accent')) ?? 'blue';
    setState(() {});
  }

  Future<bool> _verifyPin(String enteredPin) async {
    final storedPin = _settingsManager.getValue<String>('security.pin') ?? '';
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid PIN'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
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
              if (!context.mounted) return;
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
        content: const Text('Select your Google OAuth JSON credentials file.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                final result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['json'],
                );
                if (result == null || result.files.single.path == null) return;

                final file = File(result.files.single.path!);
                final contents = await file.readAsString();

                // Validate JSON
                jsonDecode(contents);

                await _settingsManager.setValue(
                  'google.oauth_credentials',
                  contents,
                );
                if (!context.mounted) return;
                Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid JSON file')),
                );
              }
            },
            child: const Text('Select File'),
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

  Future<void> _editAppLogo(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("App Logo"),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.memory(
                base64.decode(
                  _settingsManager.getValue<String>("app.theme.logo") ??
                      _settingsManager.getDefault<String>("app.theme.logo")!,
                ),
                height: 128,
              ),
              SizedBox(height: 8.0),
              ElevatedButton.icon(
                icon: Icon(Icons.upload),
                label: Text("Upload Image"),
                onPressed: () async {
                  try {
                    final result = await FilePicker.platform.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp'],
                    );
                    if (result != null && result.files.single.path != null) {
                      setState(() {
                        _settingsManager.setValue(
                          "app.theme.logo",
                          pngToBase64(result.files.single.path!),
                        );
                      });
                    }
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Failed to import image')),
                    );
                  }
                },
              ),
            ],
          ),
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

  Future<void> _editStationLocation(BuildContext context) async {
    bool isFixed =
        _settingsManager.getValue<bool>("station.fixed") ??
        false; // Default value for fixed station
    final locationController = TextEditingController(
      text: _settingsManager.getValue<String>("station.location") ?? "",
    ); // For fixed location
    final newLocationController =
        TextEditingController(); // For adding new non-fixed locations
    List<String> locations =
        _settingsManager.getValue<List<String>>("station.locations") ??
        ["Shop"]; // List for non-fixed locations

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Station Settings'),
        content: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: Column(
              children: [
                CheckboxListTile(
                  title: const Text('Fixed Station'),
                  subtitle: const Text('Permanent location?'),
                  value: isFixed,
                  onChanged: (value) {
                    setState(() {
                      isFixed = value ?? false;
                    });
                  },
                ),
                if (isFixed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: TextField(
                      controller: locationController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Enter Fixed Station Location',
                        labelText: 'Fixed Location',
                      ),
                    ),
                  ),

                if (!isFixed) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Mobile Station Locations',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ...locations.asMap().entries.map((entry) {
                    final index = entry.key;
                    final location = entry.value;
                    return ListTile(
                      title: Text(location),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () {
                          setState(() {
                            locations.removeAt(index);
                          });
                        },
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: newLocationController,
                            decoration: const InputDecoration(
                              hintText: 'Add New Location',
                              labelText: 'New Location',
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add),
                          onPressed: () {
                            if (newLocationController.text.isNotEmpty) {
                              setState(() {
                                locations.add(newLocationController.text);
                                newLocationController.clear();
                              });
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _settingsManager.setValue(
                'station.location',
                locationController.text,
              );
              await _settingsManager.setValue('station.fixed', isFixed);
              await _settingsManager.setValue(
                'station.locations',
                isFixed ? [] : locations,
              );
              if (!context.mounted) return;
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPin(BuildContext context) async {
    final formKey = GlobalKey<FormState>();

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset PIN'),
        content: Form(
          key: formKey,
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
              if (formKey.currentState?.validate() ?? false) {
                await _settingsManager.setValue(
                  'security.pin',
                  _pinController.text,
                );
                if (!context.mounted) return;
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _editRfidSettings(BuildContext context) async {
    return showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: Text("RFID Reader"),
            content: SingleChildScrollView(
              // mainAxisSize: MainAxisSize.min,
              child: Column(
                children: [
                  SegmentedButton(
                    segments: [
                      ButtonSegment(
                        value: "hid",
                        label: Text("HID"),
                        icon: Icon(Icons.keyboard),
                      ),
                      ButtonSegment(
                        value: "serial",
                        label: Text("Serial"),
                        icon: Icon(Icons.cable),
                      ),
                    ],
                    selected: {
                      _settingsManager.getValue<String>("rfid.reader") ??
                          _settingsManager.getDefault<String>("rfid.reader")!,
                    },
                    onSelectionChanged: (selection) {
                      setState(() {
                        _settingsManager.setValue(
                          "rfid.reader",
                          selection.first,
                        );
                      });
                    },
                  ),
                  if ((_settingsManager.getValue<String>("rfid.reader") ??
                          _settingsManager.getDefault<String>(
                            "rfid.reader",
                          )!) ==
                      "serial")
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 16.0),
                        FutureBuilder<List<String>>(
                          future: listPortPaths,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            } else if (snapshot.hasData) {
                              final List<String> availablePorts =
                                  snapshot.data!;

                              String? currentSelectedPort =
                                  _settingsManager.getValue<String>(
                                    "rfid.serial.port",
                                  ) ??
                                  _settingsManager.getDefault<String>(
                                    "rfid.serial.port",
                                  );

                              if (currentSelectedPort != null &&
                                  !availablePorts.contains(
                                    currentSelectedPort,
                                  )) {
                                currentSelectedPort = null;
                              }
                              return DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  label: Text("Port Path"),
                                ),
                                items: availablePorts
                                    .map(
                                      (path) => DropdownMenuItem<String>(
                                        value: path,
                                        child: Text(path),
                                      ),
                                    )
                                    .toList(),
                                value: currentSelectedPort,
                                onChanged: (newPath) {
                                  setState(() {
                                    _settingsManager.setValue(
                                      "rfid.serial.port",
                                      newPath,
                                    );
                                  });
                                },
                                hint: availablePorts.isEmpty
                                    ? const Text("No ports available")
                                    : null,
                              );
                            } else {
                              return const Text('No ports found');
                            }
                          },
                        ),
                        SizedBox(height: 8.0),
                        TextField(
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: "Baudrate",
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          controller: TextEditingController(
                            text:
                                (_settingsManager.getValue<int>(
                                          "rfid.serial.baud",
                                        ) ??
                                        _settingsManager.getDefault<int>(
                                          "rfid.serial.baud",
                                        )!)
                                    .toString(),
                          ),
                          onChanged: (newBaudrate) {
                            _settingsManager.setValue(
                              "rfid.serial.baud",
                              int.tryParse(newBaudrate),
                            );
                          },
                        ),
                        SizedBox(height: 8.0),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField(
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(),
                                  label: Text("EOI Character"),
                                ),
                                items: ["\\n", "\\r", "\\r\\n", "\\x03"]
                                    .map(
                                      (eol) => DropdownMenuItem<String>(
                                        value: eol,
                                        child: Text(eol),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (newEOL) {
                                  _settingsManager.setValue(
                                    "rfid.serial.eol",
                                    newEOL,
                                  );
                                },
                                value:
                                    _settingsManager.getValue<String>(
                                      "rfid.serial.eol",
                                    ) ??
                                    _settingsManager.getDefault<String>(
                                      "rfid.serial.eol",
                                    )!,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8.0),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField(
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(),
                                  label: Text("Checksum"),
                                ),
                                items: ChecksumStyle.values.map((style) {
                                  return DropdownMenuItem<String>(
                                    value: style.toString().split('.').last,
                                    child: Text(
                                      style.toString().split('.').last,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (newCsum) {
                                  _settingsManager.setValue(
                                    "rfid.serial.checksum",
                                    newCsum,
                                  );
                                },
                                value:
                                    _settingsManager.getValue<String>(
                                      "rfid.serial.checksum",
                                    ) ??
                                    _settingsManager.getDefault<String>(
                                      "rfid.serial.checksum",
                                    )!,
                              ),
                            ),
                            SizedBox(width: 8.0),
                            Expanded(
                              child: DropdownButtonFormField(
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(),
                                  label: Text("Pos"),
                                ),
                                items: ChecksumPosition.values.map((style) {
                                  return DropdownMenuItem<String>(
                                    value: style.toString().split('.').last,
                                    child: Text(
                                      style.toString().split('.').last,
                                    ),
                                  );
                                }).toList(),
                                onChanged: (newCsum) {
                                  _settingsManager.setValue(
                                    "rfid.serial.checksum.pos",
                                    newCsum,
                                  );
                                },
                                value:
                                    _settingsManager.getValue<String>(
                                      "rfid.serial.checksum.pos",
                                    ) ??
                                    _settingsManager.getDefault<String>(
                                      "rfid.serial.checksum.pos",
                                    )!,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8.0),
                        DropdownButtonFormField(
                          decoration: InputDecoration(
                            border: OutlineInputBorder(),
                            label: Text("Data Format"),
                          ),
                          items: DataFormat.values.map((style) {
                            return DropdownMenuItem<String>(
                              value: style.toString().split('.').last,
                              child: Text(style.toString().split('.').last),
                            );
                          }).toList(),
                          onChanged: (newCsum) {
                            _settingsManager.setValue(
                              "rfid.serial.format",
                              newCsum,
                            );
                          },
                          value:
                              _settingsManager.getValue<String>(
                                "rfid.serial.format",
                              ) ??
                              _settingsManager.getDefault<String>(
                                "rfid.serial.format",
                              )!,
                        ),
                        SizedBox(height: 4.0),
                        Text(
                          "Timeout (seconds):",
                          textAlign: TextAlign.left,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        DoubleSpinBox(
                          initialValue:
                              _settingsManager.getValue<double>(
                                "rfid.serial.timeout",
                              ) ??
                              _settingsManager.getDefault<double>(
                                "rfid.serial.timeout",
                              )!,
                          min: 0.1,
                          max: 10.0,
                          step: 0.1,
                          onChanged: (newTimeout) {
                            _settingsManager.setValue(
                              "rfid.serial.timeout",
                              newTimeout,
                            );
                          },
                        ),
                      ],
                    ),
                  if ((_settingsManager.getValue<String>("rfid.reader") ??
                          _settingsManager.getDefault<String>(
                            "rfid.reader",
                          )!) ==
                      "hid")
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 12.0),
                        Text(
                          "Timeout (seconds):",
                          textAlign: TextAlign.left,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        DoubleSpinBox(
                          initialValue:
                              _settingsManager.getValue<double>(
                                "rfid.hid.timeout",
                              ) ??
                              _settingsManager.getDefault<double>(
                                "rfid.hid.timeout",
                              )!,
                          min: 0.1,
                          max: 3.0,
                          step: 0.1,
                          onChanged: (newTimeout) {
                            _settingsManager.setValue(
                              "rfid.hid.timeout",
                              newTimeout,
                            );
                          },
                        ),
                        SizedBox(height: 8.0),
                        DropdownButtonFormField(
                          decoration: InputDecoration(
                            border: OutlineInputBorder(),
                            label: Text("End-of-Input Character"),
                          ),
                          items: ["NONE", "RETURN", "SPACE"]
                              .map(
                                (eol) => DropdownMenuItem<String>(
                                  value: eol,
                                  child: Text(eol),
                                ),
                              )
                              .toList(),
                          onChanged: (newEOL) {
                            _settingsManager.setValue("rfid.hid.eol", newEOL);
                          },
                          value:
                              _settingsManager.getValue<String>(
                                "rfid.hid.eol",
                              ) ??
                              _settingsManager.getDefault<String>(
                                "rfid.hid.eol",
                              )!,
                        ),
                        SizedBox(height: 8.0),
                        DropdownButtonFormField(
                          decoration: InputDecoration(
                            border: OutlineInputBorder(),
                            label: Text("Data Format"),
                          ),
                          items: DataFormat.values.map((style) {
                            return DropdownMenuItem<String>(
                              value: style.toString().split('.').last,
                              child: Text(style.toString().split('.').last),
                            );
                          }).toList(),
                          onChanged: (newCsum) {
                            _settingsManager.setValue(
                              "rfid.hid.format",
                              newCsum,
                            );
                          },
                          value:
                              _settingsManager.getValue<String>(
                                "rfid.hid.format",
                              ) ??
                              _settingsManager.getDefault<String>(
                                "rfid.hid.format",
                              )!,
                        ),
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
      },
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
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings exported successfully')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to export settings $e')));
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
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings imported successfully')),
        );
      }
    } catch (e) {
      if (!context.mounted) return;
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
                  title: const Text("App Logo"),
                  subtitle: Text("Logo used in the home screen."),
                  leading: const Icon(Icons.image),
                  trailing: IconButton(
                    onPressed: () => _editAppLogo(context),
                    icon: const Icon(Icons.edit),
                  ),
                ),
                ListTile(
                  title: const Text("Station Location Options"),
                  subtitle: const Text(
                    "Options for if the station is fixed, or floating, and the locations available.",
                  ),
                  leading: const Icon(Icons.location_on),
                  trailing: IconButton(
                    onPressed: () => _editStationLocation(context),
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
                  title: Text("Require PIN for Admin Sign-in"),
                  subtitle: Text(
                    "Request the PIN if an ADMIN user signs in/out without a badge",
                  ),
                  leading: Icon(Icons.pin),
                  trailing: Switch(
                    value:
                        _settingsManager.getValue<bool>(
                          "security.pin.require",
                        ) ??
                        true,
                    onChanged: (value) {
                      setState(() {
                        _settingsManager.setValue(
                          "security.pin.require",
                          value,
                        );
                      });
                    },
                  ),
                ),
                ListTile(
                  tileColor: Theme.of(context).colorScheme.surfaceContainerLow,
                  title: Text("RFID Card Reader Settings"),
                  subtitle: Text(
                    "Settings for the Serial/HID RFID Card Reader",
                  ),
                  leading: Icon(Icons.contactless),
                  trailing: IconButton(
                    onPressed: () => _editRfidSettings(context),
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
