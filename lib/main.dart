import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:attendance_tracker/backend.dart';
import 'package:attendance_tracker/keyboard.dart';
import 'package:attendance_tracker/log_printer.dart';
import 'package:attendance_tracker/log_view.dart';
import 'package:attendance_tracker/rfid_event.dart';
import 'package:attendance_tracker/settings.dart';
import 'package:attendance_tracker/settings_page.dart';
import 'package:attendance_tracker/state.dart';
import 'package:attendance_tracker/string_ext.dart';
import 'package:attendance_tracker/user_flow.dart';
import 'package:attendance_tracker/util.dart';
import 'package:attendance_tracker/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import 'package:lottie/lottie.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsManager();
  await settings.init();

  final controller = ThemeController();
  controller.updateTheme(settings.getValue<String>('app.theme.mode') ?? "dark");
  controller.updateAccent(
    settings.getValue<String>('app.theme.accent') ?? "blue",
  );

  var logger = Logger(
    filter: LevelFilter(
      Level.values.firstWhere(
        (level) =>
            level.value ==
            (settings.getValue<int>("app.loglevel") ??
                settings.getDefault<int>("app.loglevel")!),
      ),
    ),
    printer: BoundedMemoryPrinter(),
    output: null, // Use the default LogOutput (-> send everything to console)
  );

  runApp(MyApp(settings, controller, logger));
}

class MyApp extends StatefulWidget {
  const MyApp(
    this.settingsManager,
    this.themeController,
    this.logger, {
    super.key,
  });

  final SettingsManager settingsManager;
  final ThemeController themeController;
  final Logger logger;

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
            ).withSaturation(0.52).toColor();

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
              home: HomePage(
                widget.themeController,
                widget.settingsManager,
                widget.logger,
              ),
            );
          },
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage(
    this.themeController,
    this.settingsManager,
    this.logger, {
    super.key,
  });

  final ThemeController themeController;
  final SettingsManager settingsManager;
  final Logger logger;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const lockdownPlatform = MethodChannel(
    'com.example.attendance_tracker/lockdown',
  );

  // clock
  late ValueNotifier<DateTime> _now;
  late Timer _clockTimer;

  // home screen state
  late ValueNotifier<AppState> _homeScreenState;

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

  SoLoud? player;
  AudioSource? successSfx;
  AudioSource? failureSfx;

  @override
  void initState() {
    super.initState();
    // backend
    _backend = AttendanceTrackerBackend(widget.logger);
    _backend.initialize(
      widget.settingsManager.getValue<String>('google.sheet_id') ?? '',
      widget.settingsManager.getValue<String>('google.oauth_credentials') ??
          '{}',
      memberFetchInterval: widget.settingsManager.getValue<int>('backend.interval.memberPolling') ?? widget.settingsManager.getDefault<int>('backend.interval.memberPolling')!,
      updateInterval: widget.settingsManager.getValue<int>('backend.interval.statusPush') ?? widget.settingsManager.getDefault<int>('backend.interval.statusPush')!,
      updateLogInterval: widget.settingsManager.getValue<int>('backend.interval.logPush') ?? widget.settingsManager.getDefault<int>('backend.interval.logPush')!,
    );

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
    Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      _homeScreenState.value = _getStatus();
    });

    // ui
    _homeScreenImage = ValueNotifier(
      base64.decode(
        widget.settingsManager.getValue<String>("app.theme.logo") ??
            widget.settingsManager.getDefault<String>("app.theme.logo")!,
      ),
    );

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
      } else if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter && (widget.settingsManager.getValue<String>("rfid.reader") ??
          widget.settingsManager.getDefault<String>("rfid.reader")!) ==
          "hid") { // workaround for bug on web
        _rfidHidStreamController.sink.add(
          RfidEvent(
            "\n",
            DateTime.fromMicrosecondsSinceEpoch(event.timeStamp.inMilliseconds),
          ),
        );
      }
      return false; // reject the event, pass to widgets
    });
    _rfidHidTimeoutTimer = RestartableTimer(
      Duration(
        milliseconds:
            ((widget.settingsManager.getValue<double>("rfid.hid.timeout") ??
                        widget.settingsManager.getDefault<double>(
                          "rfid.hid.timeout",
                        )!) *
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
          switch (DataFormat.values.byName(
            widget.settingsManager.getValue<String>("rfid.hid.format") ??
                widget.settingsManager.getDefault<String>("rfid.hid.format")!,
          )) {
            case DataFormat.decAscii:
              _processRfid(
                int.tryParse(_rfidHidInWaiting.map((ev) => ev.char).join("")),
              );
              break;
            case DataFormat.hexAscii:
              _processRfid(
                int.tryParse(
                  _rfidHidInWaiting.map((ev) => ev.char).join(""),
                  radix: 16,
                ),
              );
              break;
          }
          _rfidHidInWaiting.clear(); // clear the queue
        }
      },
    );
    _rfidHidStream.listen((event) => _rfidHidEventListener(event));

    // kiosk
    if (!kIsWeb && Platform.isAndroid) {
      if (widget.settingsManager.getValue<bool>("android.immersive") ??
          widget.settingsManager.getDefault<bool>("android.immersive")!) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }

      if (widget.settingsManager.getValue<bool>("android.absorbvolume") ??
          widget.settingsManager.getDefault<bool>("android.absorbvolume")!) {
        lockdownPlatform.invokeMethod('setAbsorbVolumeKeys', {'enabled': true});
      } else {
        lockdownPlatform.invokeMethod('setAbsorbVolumeKeys', {
          'enabled': false,
        });
      }
    }

    initAudioSubsystem();
  }

  Future<void> initAudioSubsystem() async {
    await SoLoud.instance.init();
    player = SoLoud.instance;
    successSfx = await player?.loadAsset("assets/sounds/success.wav");
    failureSfx = await player?.loadAsset("assets/sounds/error.wav");
  }

  Future<void> _rfidHidEventListener(RfidEvent event) async {
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
      switch (DataFormat.values.byName(
        widget.settingsManager.getValue<String>("rfid.hid.format") ??
            widget.settingsManager.getDefault<String>("rfid.hid.format")!,
      )) {
        case DataFormat.decAscii:
          _processRfid(
            int.tryParse(_rfidHidInWaiting.map((ev) => ev.char).join("")),
          );
          break;
        case DataFormat.hexAscii:
          _processRfid(
            int.tryParse(
              _rfidHidInWaiting.map((ev) => ev.char).join(""),
              radix: 16,
            ),
          );
          break;
      }

      _rfidHidInWaiting.clear(); // clear the queue
    }
  }

  void _processRfid(int? code) {
    if (!rfidScanInActive) {
      widget.logger.i("RFID processing paused. Tag = $code");
      return;
    }
    widget.logger.i("Process RFID Tag: $code");
    if (code == null) {
      widget.logger.w("Invalid RFID tag, please try again");
      _displayErrorPopup("Badge Read Error");
      return;
    }
    if (!_backend.isMember(code)) {
      _displayErrorPopup("Member Not Found");
      widget.logger.w("Member not found: $code");
      return;
    }
    beginUserFlow(context, _backend.getMemberById(code), true);
  }

  void _displayErrorPopup(String error) {
    if (failureSfx != null) {
      player?.play(failureSfx!);
    }
    final rootContext = context; // capture once from the widget
    showDialog(
      barrierColor: Colors.red.withAlpha(40),
      barrierDismissible: true,
      context: rootContext,
      builder: (dialogContext) {
        // Schedule dismissal using the rootContext, not dialogContext
        Timer(const Duration(seconds: 1), () {
          if (mounted &&
              Navigator.of(rootContext, rootNavigator: true).canPop()) {
            Navigator.of(rootContext, rootNavigator: true).pop();
          }
        });

        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset('assets/animations/fail.json', reverse: true),
              Text(error, style: Theme.of(rootContext).textTheme.titleLarge),
            ],
          ),
          actionsPadding: EdgeInsets.zero,
        );
      },
    );
  }

  void _displaySuccessPopup() async {
    if (successSfx != null) {
      player?.play(successSfx!);
    }
    showDialog(
      barrierColor: Colors.green.withAlpha(40),
      barrierDismissible: true,
      context: context,
      builder: (context) {
        Timer(Duration(seconds: 1), () {
          Navigator.of(context).maybePop();
        });
        return AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Lottie.asset('assets/animations/success.json', reverse: true),
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
      if (_backend.getMemberById(user.id).status != user.status) {
        _displaySuccessPopup();
      }
    });
  }

  AppState _getStatus() {
    if (_backend.googleConnected.value == false) {
      return AppState(Colors.amber, "Connection Lost");
    } else {
      return AppState(Colors.green, "System Ready");
    }
  }

  List<Widget> _buildContentSections(double iconSize, bool controls) {
    final theme = Theme.of(context);

    return [
      // logo
      if (!controls)
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              if (!controls)
                Row(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.center,
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
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                timeString,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    Spacer(flex: 2,),
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
                                builder: (context) => SettingsPage(
                                  widget.themeController,
                                  widget.logger,
                                ),
                              ),
                            ).then((_) {
                              // navigate back
                              rfidScanInActive = true;
                              setState(() {
                                _homeScreenImage.value = base64.decode(
                                  widget.settingsManager.getValue<String>(
                                    "app.theme.logo",
                                  ) ??
                                      widget.settingsManager
                                          .getDefault<String>(
                                        "app.theme.logo",
                                      )!,
                                );
                              });

                              // backend
                              _backend.initialize(
                                widget.settingsManager.getValue<String>(
                                  'google.sheet_id',
                                ) ??
                                    '',
                                widget.settingsManager.getValue<String>(
                                  'google.oauth_credentials',
                                ) ??
                                    '{}',
                                memberFetchInterval: widget.settingsManager.getValue<int>('backend.interval.memberPolling') ?? widget.settingsManager.getDefault<int>('backend.interval.memberPolling')!,
                                updateInterval: widget.settingsManager.getValue<int>('backend.interval.statusPush') ?? widget.settingsManager.getDefault<int>('backend.interval.statusPush')!,
                                updateLogInterval: widget.settingsManager.getValue<int>('backend.interval.logPush') ?? widget.settingsManager.getDefault<int>('backend.interval.logPush')!,
                              );
                            });
                          },
                        ),
                        PopupMenuItem(
                          value: 'logger',
                          child: Text('App Logs'),
                          onTap: () {
                            rfidScanInActive = false;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => LoggerView(
                                  settings: widget.settingsManager,
                                ),
                              ),
                            ).then((_) {
                              rfidScanInActive = true;
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
                  ],
                ),
              Spacer(),
              ValueListenableBuilder(
                valueListenable: _homeScreenImage,
                builder: (context, image, widget) {
                  return Image.memory(
                    image,
                    width: iconSize,
                    fit: BoxFit.fill,
                  );
                },
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
                          Icon(Icons.circle, color: value.color, size: 18),
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
        )
      else
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              ValueListenableBuilder(
                valueListenable: _homeScreenImage,
                builder: (context, image, widget) {
                  return Image.memory(image, width: iconSize, fit: BoxFit.fill);
                },
              ),
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
                        Card.filled(
                          child: Padding(
                            padding: const EdgeInsets.all(6.0),
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
                        SizedBox(height: 8),
                        Text(dateString, style: theme.textTheme.titleMedium),
                        Text(
                          timeString,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontFamily: 'monospace',
                          ),
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
                          builder: (context) => SettingsPage(
                            widget.themeController,
                            widget.logger,
                          ),
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

                        // backend
                        _backend.initialize(
                          widget.settingsManager.getValue<String>(
                                'google.sheet_id',
                              ) ??
                              '',
                          widget.settingsManager.getValue<String>(
                                'google.oauth_credentials',
                              ) ??
                              '{}',
                          memberFetchInterval: widget.settingsManager.getValue<int>('backend.interval.memberPolling') ?? widget.settingsManager.getDefault<int>('backend.interval.memberPolling')!,
                          updateInterval: widget.settingsManager.getValue<int>('backend.interval.statusPush') ?? widget.settingsManager.getDefault<int>('backend.interval.statusPush')!,
                          updateLogInterval: widget.settingsManager.getValue<int>('backend.interval.logPush') ?? widget.settingsManager.getDefault<int>('backend.interval.logPush')!,
                        );
                      });
                    },
                  ),
                  PopupMenuItem(
                    value: 'logger',
                    child: Text('App Logs'),
                    onTap: () {
                      rfidScanInActive = false;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              LoggerView(settings: widget.settingsManager),
                        ),
                      ).then((_) {
                        rfidScanInActive = true;
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
      Flexible(
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.settingsManager.getValue<String>(
                            "rfid.reader",
                          ) !=
                          "disable")
                        RfidTapCard(),
                      if (widget.settingsManager.getValue<String>(
                            "rfid.reader",
                          ) !=
                          "disable")
                        const SizedBox(height: 8),
                      Expanded(
                        child: Material(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(4.0),
                                child: VirtualTextField(
                                  decoration: InputDecoration(
                                    hintText: 'Search name...',
                                    prefixIcon: Icon(Icons.search),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
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
                                                _searchQuery.toLowerCase(),
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
                                                _searchQuery.toLowerCase(),
                                              ),
                                        )
                                        .toList();
                                    return ValueListenableBuilder(
                                      valueListenable: filteredMembers,
                                      builder: (context, filterValue, child) {
                                        return ListView.builder(
                                          itemCount: filterValue.length,
                                          itemBuilder: (context, index) {
                                            final member = filterValue[index];
                                            return ListTile(
                                              leading: Stack(
                                                alignment:
                                                    Alignment.bottomRight,
                                                children: [
                                                  CircleAvatar(
                                                    child: Text(
                                                      member.name
                                                          .split(' ')
                                                          .map(
                                                            (part) => part[0],
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
                                                                .present
                                                        ? Colors.green
                                                        : Colors.red,
                                                    size: 12,
                                                  ),
                                                ],
                                              ),
                                              title: Text(member.name),
                                              subtitle: Text(
                                                member.status ==
                                                        AttendanceStatus.out
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
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 200,
                child: Container(
                  color: Theme.of(context).colorScheme.surfaceContainerLowest,
                  child: Center(
                    child: VirtualKeyboard(
                      rootLayoutPath: "assets/layouts/en-US.xml",
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return SafeArea(
      child: OrientationBuilder(
        builder: (context, orientation) {
          return Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: OrientationBuilder(
                    builder: (BuildContext context, Orientation orientation) {
                      if (orientation == Orientation.landscape) {
                        final sections = _buildContentSections(240, false);
                        return Row(children: [
                          SizedBox(width: 300, child: sections[0]),
                          Expanded(
                            flex: 2,
                            child: Column(
                              children: sections.sublist(1),
                            ),
                          ),
                        ]);
                      } else {
                        return Column(
                          children: _buildContentSections(120, true),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
