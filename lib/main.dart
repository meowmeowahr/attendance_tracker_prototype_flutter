import 'dart:async';

import 'package:attendance_tracker/backend.dart';
import 'package:attendance_tracker/keyboard.dart';
import 'package:attendance_tracker/settings.dart';
import 'package:attendance_tracker/settings_page.dart';
import 'package:attendance_tracker/string_ext.dart';
import 'package:attendance_tracker/widgets.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
              home: HomePage(widget.themeController),
            );
          },
        );
      },
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage(this.themeController, {super.key});

  final ThemeController themeController;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late DateTime _now;
  late Timer _timer;
  late TabController _currentBodyController;

  late AttendanceTrackerBackend _backend;
  late List<Member> _attendance;

  String _searchQuery = '';
  List<Member> filteredMembers = [];

  @override
  void initState() {
    super.initState();
    _backend = AttendanceTrackerBackend();
    _attendance = _backend.fetchAttendanceData();
    filteredMembers = _attendance
        .where(
          (member) =>
              member.name.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();
    _now = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      setState(() {
        _now = DateTime.now();
      });
    });
    _currentBodyController = TabController(
      length: 2,
      vsync: this,
      initialIndex: 0,
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timeString = DateFormat('hh:mm:ss a').format(_now);
    final dateString = DateFormat('MMMM d, yyyy').format(_now);

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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        dateString,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        timeString,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
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
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                SettingsPage(widget.themeController),
                          ),
                        );
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
                Center(child: FlutterLogo(size: 240)),
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
                                    setState(() {
                                      _attendance = _backend
                                          .fetchAttendanceData();
                                    });
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
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.circle,
                                        color: Colors.green,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text("System Ready"),
                                    ],
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
                                        setState(() {
                                          _searchQuery = value;
                                        });
                                      },
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: ListView.builder(
                                      itemCount: filteredMembers.length,
                                      itemBuilder: (context, index) {
                                        final member = filteredMembers[index];
                                        return ListTile(
                                          leading: Stack(
                                            alignment: Alignment.bottomRight,
                                            children: [
                                              CircleAvatar(
                                                backgroundColor:
                                                    HSVColor.fromColor(
                                                          ColorScheme.fromSeed(
                                                            seedColor: Color(
                                                              member.hashCode,
                                                            ).withAlpha(255),

                                                            brightness:
                                                                Brightness.dark,
                                                          ).primary,
                                                        )
                                                        .withAlpha(0.5)
                                                        .withSaturation(0.6)
                                                        .toColor(),
                                                child: Text(
                                                  member.name
                                                      .split(' ')
                                                      .map((part) => part[0])
                                                      .take(2)
                                                      .join(),
                                                ),
                                              ),
                                              Icon(
                                                Icons.circle,
                                                color:
                                                    member.status ==
                                                        AttendanceStatus.active
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
                                          onTap: () {},
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
