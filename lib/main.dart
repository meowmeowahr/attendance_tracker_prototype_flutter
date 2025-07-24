import 'package:async/async.dart';
import 'dart:async';
import 'dart:convert';

import 'package:attendance_tracker/backend.dart';
import 'package:attendance_tracker/keyboard.dart';
import 'package:attendance_tracker/rfid_event.dart';
import 'package:attendance_tracker/serial.dart';
import 'package:attendance_tracker/settings.dart';
import 'package:attendance_tracker/settings_page.dart';
import 'package:attendance_tracker/state.dart';
import 'package:attendance_tracker/string_ext.dart';
import 'package:attendance_tracker/user_flow.dart';
import 'package:attendance_tracker/util.dart';
import 'package:attendance_tracker/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';

void main() async {
  final settings = SettingsManager();
  await settings.init();

  final controller = ThemeController();
  controller.updateTheme(settings.getValue<String>('app.theme.mode') ?? "dark");
  controller.updateAccent(
    settings.getValue<String>('app.theme.accent') ?? "blue",
  );

  runApp(MyApp(settings, controller));
}

class MyApp extends StatefulWidget {
  const MyApp(this.settingsManager, this.themeController, {super.key});

  final SettingsManager settingsManager;
  final ThemeController themeController;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.themeController.themeMode,
      builder: (context, value, child) {
        return ValueListenableBuilder(
          valueListenable: widget.themeController.accentColor,
          builder: (context, value, child) {
            final adjustedColor = HSVColor.fromColor(
              value,
            ).withSaturation(0.65).toColor();

            final darkColorScheme = ColorScheme.fromSeed(
              seedColor: adjustedColor,
              brightness: Brightness.dark,
              primary: adjustedColor,
            );

            final lightColorScheme = ColorScheme.fromSeed(
              seedColor: adjustedColor,
              brightness: Brightness.light,
              primary: adjustedColor,
            );

            final darkTheme = ThemeData(
              colorScheme: darkColorScheme,
              useMaterial3: true,
              scaffoldBackgroundColor: darkColorScheme.surface,
              appBarTheme: AppBarTheme(
                backgroundColor: darkColorScheme.primary,
                foregroundColor: darkColorScheme.onPrimary,
              ),
            );

            final lightTheme = ThemeData(
              colorScheme: lightColorScheme,
              useMaterial3: true,
              scaffoldBackgroundColor: lightColorScheme.surface,
              appBarTheme: AppBarTheme(
                backgroundColor: lightColorScheme.primary,
                foregroundColor: lightColorScheme.onPrimary,
              ),
            );

            return MaterialApp(
              title: 'Attendance Tracker',
              themeMode: widget.themeController.themeMode.value,
              darkTheme: darkTheme,
              theme: lightTheme,
              home: HomePage(widget.themeController, widget.settingsManager),
            );
          },
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage(this.themeController, this.settingsManager, {super.key});

  final ThemeController themeController;
  final SettingsManager settingsManager;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  // clock
  late ValueNotifier<DateTime> _now;
  late Timer _clockTimer;

  // home screen state
  late ValueNotifier<AppState> _homeScreenState;

  // home tabs
  late RestartableTimer _nameSelectionScreenTimeout;
  late TabController _currentBodyController;

  // backend
  late AttendanceTrackerBackend _backend;

  // name search
  String _searchQuery = '';
  late ValueNotifier<List<Member>> filteredMembers;

  // home screen image
  late ValueNotifier<Uint8List> _homeScreenImage;

  // rfid
  bool rfidScanInActive = true;

  // rfid hid
  late StreamController<RfidEvent> _rfidHidStreamController;
  late Stream<RfidEvent> _rfidHidStream;
  final List<RfidEvent> _rfidHidInWaiting = [];
  late RestartableTimer _rfidHidTimeoutTimer;

  // rfid serial
  final SerialRfidStream _rfidSerialStreamer = SerialRfidStream();

  @override
  void initState() {
    super.initState();
    // backend
    _backend = AttendanceTrackerBackend();
    _backend.initialize();

    // search filter
    filteredMembers = ValueNotifier(
      _backend.attendance.value
          .where(
            (member) =>
                member.name.toLowerCase().contains(_searchQuery.toLowerCase()),
          )
          .toList(),
    );

    // clock
    _now = ValueNotifier(DateTime.now());
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      _now.value = DateTime.now();
    });

    // home screen state
    _homeScreenState = ValueNotifier(AppState.initial);
    Timer.periodic(const Duration(seconds: 10), (Timer timer) {
      _homeScreenState.value = _getStatus();
    });

    // ui
    _currentBodyController = TabController(
      length: 2,
      vsync: this,
      initialIndex: 0,
    );
    _homeScreenImage = ValueNotifier(
      base64.decode(
        widget.settingsManager.getValue<String>("app.theme.logo") ??
            widget.settingsManager.getDefault<String>("app.theme.logo")!,
      ),
    );
    _nameSelectionScreenTimeout = RestartableTimer(Duration(seconds: 10), () {
      _currentBodyController.index = 0;
    });
    _nameSelectionScreenTimeout.cancel();

    // rfid hid
    _rfidHidStreamController = StreamController<RfidEvent>.broadcast();
    _rfidHidStream = _rfidHidStreamController.stream;
    ServicesBinding.instance.keyboard.addHandler((event) {
      if (event is KeyDownEvent &&
          event.character != null &&
          (widget.settingsManager.getValue<String>("rfid.reader") ??
                  widget.settingsManager.getDefault<String>("rfid.reader")!) ==
              "hid") {
        _rfidHidStreamController.sink.add(
          RfidEvent(
            event.character!,
            DateTime.fromMicrosecondsSinceEpoch(event.timeStamp.inMilliseconds),
          ),
        );
      }
      return false; // reject the event, pass to widgets
    });
    _rfidHidTimeoutTimer = RestartableTimer(
      Duration(
        milliseconds:
            (widget.settingsManager.getValue<double>("rfid.hid.timeout") ??
                    widget.settingsManager.getDefault<double>(
                          "rfid.hid.timeout",
                        )! *
                        1000)
                .ceil(),
      ),
      () {
        if (_rfidHidInWaiting.isNotEmpty) {
          // quick sanity check
          final Map<String, String?> eolMap = {
            "SPACE": " ",
            "RETURN": "\r",
            "NONE": null,
          };
          if (_rfidHidInWaiting.last.char ==
              eolMap[widget.settingsManager.getValue<String>("rfid.hid.eol") ??
                  widget.settingsManager.getDefault<String>("rfid.hid.eol")!]) {
            return;
          }

          // process
          _processRfid(
            int.tryParse(_rfidHidInWaiting.map((ev) => ev.char).join("")),
          );
          _rfidHidInWaiting.clear(); // clear the queue
        }
      },
    );
    _rfidHidStream.listen((event) {
      _rfidHidTimeoutTimer.reset(); // reset the timeout
      _rfidHidInWaiting.add(event); // add new event
      final Map<String, String?> eolMap = {
        "SPACE": " ",
        "RETURN": "\r",
        "NONE": null,
      };
      if (event.char ==
          eolMap[widget.settingsManager.getValue<String>("rfid.hid.eol") ??
              widget.settingsManager.getDefault<String>("rfid.hid.eol")!]) {
        // end-of-line
        _processRfid(
          int.tryParse(_rfidHidInWaiting.map((ev) => ev.char).join("")),
        );
        _rfidHidInWaiting.clear(); // clear the queue
      }
    });

    // rfid serial
    if ((widget.settingsManager.getValue<String>("rfid.reader") ??
            widget.settingsManager.getDefault<String>("rfid.reader")!) ==
        "serial") {
      _rfidSerialStreamer.configure(
        portPath:
            widget.settingsManager.getValue<String>("rfid.serial.port") ??
            widget.settingsManager.getDefault<String>("rfid.serial.port")!,
        baudRate:
            widget.settingsManager.getValue<int>("rfid.serial.baud") ??
            widget.settingsManager.getDefault<int>("rfid.serial.baud")!,
        readTimeoutMs:
            ((widget.settingsManager.getValue<double>("rfid.serial.timeout") ??
                        widget.settingsManager.getDefault<double>(
                          "rfid.serial.timeout",
                        )!) *
                    1000)
                .ceil(),
        eolString:
            widget.settingsManager.getValue<String>("rfid.serial.eol") ??
            widget.settingsManager.getDefault<String>("rfid.serial.eol")!,
        solString:
            widget.settingsManager.getValue<String>("rfid.serial.sol") ??
            widget.settingsManager.getDefault<String>("rfid.serial.sol")!,
        dataFormat: DataFormat.values.byName(
          widget.settingsManager.getValue<String>("rfid.serial.format") ??
              widget.settingsManager.getDefault<String>("rfid.serial.format")!,
        ),
        checksumStyle: ChecksumStyle.values.byName(
          widget.settingsManager.getValue<String>("rfid.serial.checksum") ??
              widget.settingsManager.getDefault<String>(
                "rfid.serial.checksum",
              )!,
        ),
        checksumPosition: ChecksumPosition.values.byName(
          widget.settingsManager.getValue<String>("rfid.serial.checksum.pos") ??
              widget.settingsManager.getDefault<String>(
                "rfid.serial.checksum.pos",
              )!,
        ),
      );
      final connOk = _rfidSerialStreamer.connect(); // attempt to connect
      _rfidSerialStreamer.stream.listen((data) => _processRfid(data));
      print("Connection to startup serial port: $connOk");
    }
  }

  void _processRfid(int? code) {
    if (!rfidScanInActive) {
      print("RFID processing paused. Ignoring tag");
      return;
    }
    print("Process RFID Tag: $code");
    if (code == null) {
      print("Invalid RFID tag, please try again");
      _displayErrorPopup("Badge Read Error");
      return;
    }
    if (!_backend.isMember(code)) {
      _displayErrorPopup("Member Not Found");
      return;
    }
    beginUserFlow(context, _backend.getMemberById(code), true);
  }

  void _displayErrorPopup(String error) {
    showDialog(
      barrierColor: Colors.red.withAlpha(40),
      barrierDismissible: false,
      context: context,
      builder: (context) {
        Timer(Duration(seconds: 1), () {
          Navigator.of(context).pop();
        });
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset('assets/animations/fail.json', reverse: true),
              Text(error, style: Theme.of(context).textTheme.titleLarge),
            ],
          ),
          actionsPadding: EdgeInsets.zero,
          actions: [],
        );
      },
    );
  }

  @override
  bool get wantKeepAlive {
    return true;
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _rfidSerialStreamer.disconnect();
    super.dispose();
  }

  void beginUserFlow(BuildContext context, Member user, bool fromRfid) {
    rfidScanInActive = false;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserFlow(
          user,
          _backend,
          allowedLocations:
              widget.settingsManager.getValue<List<String>>(
                'station.locations',
              ) ??
              ["Shop"],
          fixed:
              widget.settingsManager.getValue<bool>('station.fixed') ?? false,
          fixedLocation:
              widget.settingsManager.getValue<String>('station.location') ??
              "Shop",
          requireAdminPinEntry: !fromRfid,
        ),
      ),
    ).then((_) {
      rfidScanInActive = true;
    });
  }

  AppState _getStatus() {
    if ((widget.settingsManager.getValue<String>("rfid.reader") ??
                widget.settingsManager.getDefault<String>("rfid.reader")!) ==
            "serial" &&
        !_rfidSerialStreamer.isConnected &&
        _rfidSerialStreamer.portError != null) {
      return AppState(
        Colors.red,
        "RFID Reader Connection Error: ${_rfidSerialStreamer.portError}",
      );
    } else if ((widget.settingsManager.getValue<String>("rfid.reader") ??
                widget.settingsManager.getDefault<String>("rfid.reader")!) ==
            "serial" &&
        !_rfidSerialStreamer.isConnected) {
      return AppState(Colors.red, "RFID Reader Connection Lost");
    } else {
      return AppState(Colors.green, "System Ready");
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      body: Column(
        children: [
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            height: 60,
            child: Row(
              children: [
                Spacer(),
                Center(
                  child: ValueListenableBuilder(
                    valueListenable: _now,
                    builder: (context, value, child) {
                      final timeString = DateFormat(
                        'hh:mm:ss a',
                      ).format(_now.value);
                      final dateString = DateFormat(
                        'MMMM d, yyyy',
                      ).format(_now.value);
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            dateString,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            timeString,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontFamily: 'monospace'),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Spacer(),
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert),
                  tooltip: "",
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'settings',
                      child: Text('Settings'),
                      onTap: () {
                        rfidScanInActive = false;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                SettingsPage(widget.themeController),
                          ),
                        ).then((_) {
                          // navigate back
                          rfidScanInActive = true;
                          setState(() {
                            _homeScreenImage.value = base64.decode(
                              widget.settingsManager.getValue<String>(
                                    "app.theme.logo",
                                  ) ??
                                  widget.settingsManager.getDefault<String>(
                                    "app.theme.logo",
                                  )!,
                            );
                          });
                          // rfid serial
                          if ((widget.settingsManager.getValue<String>(
                                    "rfid.reader",
                                  ) ??
                                  widget.settingsManager.getDefault<String>(
                                    "rfid.reader",
                                  )!) ==
                              "serial") {
                            _rfidSerialStreamer.configure(
                              portPath:
                                  widget.settingsManager.getValue<String>(
                                    "rfid.serial.port",
                                  ) ??
                                  widget.settingsManager.getDefault<String>(
                                    "rfid.serial.port",
                                  )!,
                              baudRate:
                                  widget.settingsManager.getValue<int>(
                                    "rfid.serial.baud",
                                  ) ??
                                  widget.settingsManager.getDefault<int>(
                                    "rfid.serial.baud",
                                  )!,
                              readTimeoutMs:
                                  ((widget.settingsManager.getValue<double>(
                                                "rfid.serial.timeout",
                                              ) ??
                                              widget.settingsManager
                                                  .getDefault<double>(
                                                    "rfid.serial.timeout",
                                                  )!) *
                                          1000)
                                      .ceil(),
                              eolString:
                                  widget.settingsManager.getValue<String>(
                                    "rfid.serial.eol",
                                  ) ??
                                  widget.settingsManager.getDefault<String>(
                                    "rfid.serial.eol",
                                  )!,
                              solString:
                                  widget.settingsManager.getValue<String>(
                                    "rfid.serial.sol",
                                  ) ??
                                  widget.settingsManager.getDefault<String>(
                                    "rfid.serial.sol",
                                  )!,
                              dataFormat: DataFormat.values.byName(
                                widget.settingsManager.getValue<String>(
                                      "rfid.serial.format",
                                    ) ??
                                    widget.settingsManager.getDefault<String>(
                                      "rfid.serial.format",
                                    )!,
                              ),
                              checksumStyle: ChecksumStyle.values.byName(
                                widget.settingsManager.getValue<String>(
                                      "rfid.serial.checksum",
                                    ) ??
                                    widget.settingsManager.getDefault<String>(
                                      "rfid.serial.checksum",
                                    )!,
                              ),
                              checksumPosition: ChecksumPosition.values.byName(
                                widget.settingsManager.getValue<String>(
                                      "rfid.serial.checksum.pos",
                                    ) ??
                                    widget.settingsManager.getDefault<String>(
                                      "rfid.serial.checksum.pos",
                                    )!,
                              ),
                            );
                            final connOk = _rfidSerialStreamer
                                .connect(); // attempt to connect
                            print(
                              "Connection to post-setup serial port: $connOk",
                            );
                          }
                        });
                      },
                    ),
                    PopupMenuItem(
                      value: 'about',
                      child: Text('About'),
                      onTap: () {
                        showAboutDialog(
                          context: context,
                          applicationName: 'Attendance Tracker',
                          applicationVersion: '1.0.0',
                          applicationIcon: FlutterLogo(size: 64),
                          children: [],
                        );
                      },
                    ),
                  ],
                ),
                SizedBox(width: 8),
              ],
            ),
          ),
          Expanded(
            child: Row(
              children: [
                // logo
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: ValueListenableBuilder(
                      valueListenable: _homeScreenImage,
                      builder: (context, image, widget) {
                        return Image.memory(
                          image,
                          width: 240,
                          fit: BoxFit.fill,
                        );
                      },
                    ),
                  ),
                ),
                Flexible(
                  child: TabBarView(
                    controller: _currentBodyController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      Material(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerLow,
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Spacer(),
                              RfidTapCard(),
                              Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: FilledButton(
                                  onPressed: () {
                                    _nameSelectionScreenTimeout.reset();
                                    setState(() {
                                      _currentBodyController.index = 1;
                                    });
                                  },
                                  style: ButtonStyle(
                                    minimumSize: WidgetStateProperty.all(
                                      const Size.fromHeight(60),
                                    ),
                                    shape: WidgetStateProperty.all(
                                      RoundedRectangleBorder(
                                        borderRadius: BorderRadius.all(
                                          Radius.circular(8),
                                        ),
                                      ),
                                    ),
                                    textStyle: WidgetStateProperty.all(
                                      Theme.of(
                                        context,
                                      ).textTheme.bodyLarge?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  child: const Text("Select Name"),
                                ),
                              ),
                              Spacer(),
                              Card.filled(
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: ValueListenableBuilder(
                                    valueListenable: _homeScreenState,
                                    builder: (context, value, child) {
                                      return Row(
                                        children: [
                                          Icon(
                                            Icons.circle,
                                            color: value.color,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text(value.description),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Column(
                        children: [
                          Container(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHigh,
                            height: 48,
                            child: Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(width: 8),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _currentBodyController.index = 0;
                                      });
                                    },
                                    icon: Icon(Icons.arrow_back),
                                  ),
                                  Spacer(),
                                  Text(
                                    "Manual Name Selection",
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Spacer(),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Listener(
                              behavior: HitTestBehavior.translucent,
                              onPointerDown: (ev) {
                                _nameSelectionScreenTimeout.cancel();
                              },
                              onPointerUp: (ev) {
                                _nameSelectionScreenTimeout.reset();
                              },
                              onPointerSignal: (ev) {
                                _nameSelectionScreenTimeout.reset();
                              },
                              child: Material(
                                color: Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerLow,
                                child: Column(
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.all(8.0),
                                      child: VirtualTextField(
                                        decoration: InputDecoration(
                                          hintText: 'Search name...',
                                          prefixIcon: Icon(Icons.search),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                        ),
                                        onChanged: (value) {
                                          _searchQuery = value;
                                          filteredMembers.value = _backend
                                              .attendance
                                              .value
                                              .where(
                                                (member) => member.name
                                                    .toLowerCase()
                                                    .contains(
                                                      _searchQuery
                                                          .toLowerCase(),
                                                    ),
                                              )
                                              .toList();
                                        },
                                      ),
                                    ),
                                    Expanded(
                                      flex: 2,
                                      child: ValueListenableBuilder<List<Member>>(
                                        valueListenable: _backend.attendance,
                                        builder: (context, attendanceValue, child) {
                                          filteredMembers.value = _backend
                                              .attendance
                                              .value
                                              .where(
                                                (member) => member.name
                                                    .toLowerCase()
                                                    .contains(
                                                      _searchQuery
                                                          .toLowerCase(),
                                                    ),
                                              )
                                              .toList();
                                          return ValueListenableBuilder(
                                            valueListenable: filteredMembers,
                                            builder: (context, filterValue, child) {
                                              return ListView.builder(
                                                itemCount: filterValue.length,
                                                itemBuilder: (context, index) {
                                                  final member =
                                                      filterValue[index];
                                                  return ListTile(
                                                    leading: Stack(
                                                      alignment:
                                                          Alignment.bottomRight,
                                                      children: [
                                                        CircleAvatar(
                                                          backgroundColor:
                                                              HSVColor.fromColor(
                                                                    ColorScheme.fromSeed(
                                                                      seedColor:
                                                                          Color(
                                                                            member.hashCode,
                                                                          ).withAlpha(
                                                                            255,
                                                                          ),

                                                                      brightness:
                                                                          Brightness
                                                                              .dark,
                                                                    ).primary,
                                                                  )
                                                                  .withAlpha(
                                                                    0.5,
                                                                  )
                                                                  .withSaturation(
                                                                    0.6,
                                                                  )
                                                                  .toColor(),
                                                          child: Text(
                                                            member.name
                                                                .split(' ')
                                                                .map(
                                                                  (part) =>
                                                                      part[0],
                                                                )
                                                                .take(2)
                                                                .join(),
                                                          ),
                                                        ),
                                                        Icon(
                                                          Icons.circle,
                                                          color:
                                                              member.status ==
                                                                  AttendanceStatus
                                                                      .active
                                                              ? Colors.green
                                                              : Colors.red,
                                                          size: 12,
                                                        ),
                                                      ],
                                                    ),
                                                    title: Text(member.name),
                                                    subtitle: Text(
                                                      member.location == null
                                                          ? member.privilege
                                                                .toString()
                                                                .split('.')
                                                                .last
                                                                .capitalize()
                                                          : "${member.privilege.toString().split('.').last.capitalize()} · ${member.location!}",
                                                    ),
                                                    onTap: () {
                                                      beginUserFlow(
                                                        context,
                                                        member,
                                                        false,
                                                      );
                                                    },
                                                  );
                                                },
                                              );
                                            },
                                          );
                                        },
                                      ),
                                    ),
                                    SizedBox(
                                      height: 200,
                                      child: Container(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerLowest,
                                        child: Center(
                                          child: VirtualKeyboard(
                                            rootLayoutPath:
                                                "assets/layouts/en-US.xml",
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
