import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:async/async.dart';
import 'package:attendance_tracker/string_ext.dart';
import 'package:flutter/material.dart';
import 'package:googleapis/sheets/v4.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

enum AttendanceStatus { present, out }

enum MemberPrivilege { admin, student }

class Member {
  final int id;
  final String name;
  final AttendanceStatus status;
  final String? location;
  final MemberPrivilege privilege;
  Member(
    this.id,
    this.name,
    this.status, {
    this.location,
    this.privilege = MemberPrivilege.student,
  });

  @override
  String toString() {
    return 'Member{id: $id, name: $name, status: $status, location: $location, privilege: $privilege}';
  }
}

class TimeClockEvent {
  final int memberId;
  final DateTime time;
  TimeClockEvent(this.memberId, this.time);
}

class ClockInEvent extends TimeClockEvent {
  final String location;

  ClockInEvent(super.memberId, super.time, this.location);
}

class ClockOutEvent extends TimeClockEvent {
  ClockOutEvent(super.memberId, super.time);
}

class TimeoutClient extends http.BaseClient {
  final http.Client _inner;
  final Duration timeout;

  TimeoutClient(this._inner, this.timeout);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request).timeout(timeout);
  }
}

class AttendanceTrackerBackend {
  static const memberSheetName = "Members";
  static const logSheetName = "Log";
  static const memberSheetContentsRange = "Members!A3:E";
  static const memberSheetIdsRange = "Members!A3:A";

  ValueNotifier<List<Member>> attendance = ValueNotifier([]);

  // google
  Map<String, dynamic>? _oauthCredentials;
  String? _sheetId;
  ServiceAccountCredentials? _credentials;
  AutoRefreshingAuthClient? _authClient;
  SheetsApi? _sheetsClient;
  Spreadsheet? _spreadsheet;

  // tasks
  RestartableTimer? _memberFetchTimer;
  RestartableTimer? _updateTimer;
  RestartableTimer? _googleAttemptBringupTimer;

  final _clockInQueue = Queue<TimeClockEvent>();
  final _clockOutQueue = Queue<TimeClockEvent>();

  // google connected flag
  // this must NOT become false on rate limit
  ValueNotifier<bool?> googleConnected = ValueNotifier(null);

  AttendanceTrackerBackend() {
    googleConnected.addListener(() {
      if (googleConnected.value != true) {
        _onGoogleDisconnected();
      }
    });
  }

  void initialize(
    String sheetId,
    String oauthCredentialString, {
    int memberFetchInterval = 5,
    int updateInterval = 2,
  }) async {
    _oauthCredentials = jsonDecode(oauthCredentialString);
    _sheetId = sheetId;

    _clockInQueue.clear();
    _clockOutQueue.clear();

    attendance.value = [];

    // try to init google
    try {
      final baseClient = http.Client();
      final timeoutClient = TimeoutClient(
        baseClient,
        const Duration(seconds: 5),
      );

      _credentials = ServiceAccountCredentials.fromJson(_oauthCredentials);
      _authClient = await clientViaServiceAccount(_credentials!, [
        SheetsApi.spreadsheetsScope,
      ], baseClient: timeoutClient);

      _sheetsClient = SheetsApi(_authClient!);
      _spreadsheet = await _sheetsClient?.spreadsheets.get(_sheetId!);

      final existingTitles =
          _spreadsheet?.sheets
              ?.map((s) => s.properties?.title)
              .whereType<String>()
              .toList() ??
          [];

      final initRequests = [
        if (!existingTitles.contains(AttendanceTrackerBackend.memberSheetName))
          Request(
            addSheet: AddSheetRequest(
              properties: SheetProperties(
                title: AttendanceTrackerBackend.memberSheetName,
              ),
            ),
          ),
        if (!existingTitles.contains(AttendanceTrackerBackend.logSheetName))
          Request(
            addSheet: AddSheetRequest(
              properties: SheetProperties(
                title: AttendanceTrackerBackend.logSheetName,
              ),
            ),
          ),
      ];
      if (initRequests.isNotEmpty) {
        final request = BatchUpdateSpreadsheetRequest(requests: initRequests);
        await _sheetsClient?.spreadsheets.batchUpdate(request, _sheetId!);
      }

      googleConnected.value = _spreadsheet != null;
      print("Loaded spreadsheet: ${_sheetId!}");
    } catch (e) {
      googleConnected.value = false;
      print('Error initializing SheetsClient: $e');
    }

    if (_memberFetchTimer != null) {
      _memberFetchTimer!.cancel();
    }
    _memberFetchTimer = RestartableTimer(
      Duration(seconds: memberFetchInterval),
      () async {
        await _waitUntilQueuesEmpty();
        await _updateMembers();
        _memberFetchTimer?.reset();
      },
    );
    if (_updateTimer != null) {
      _updateTimer!.cancel();
    }
    _updateTimer = RestartableTimer(
      Duration(seconds: memberFetchInterval),
      () async {
        await _update();
        _updateTimer?.reset();
      },
    );
    _updateMembers(); // no await = schedule for background
  }

  Future<void> _waitUntilQueuesEmpty({
    Duration checkInterval = const Duration(milliseconds: 100),
  }) async {
    while (_clockInQueue.isNotEmpty || _clockOutQueue.isNotEmpty) {
      await Future.delayed(checkInterval);
    }
  }

  Future<void> _onGoogleDisconnected() async {
    // we will re-authenticate
    try {
      final baseClient = http.Client();
      final timeoutClient = TimeoutClient(
        baseClient,
        const Duration(seconds: 5),
      );

      _credentials = ServiceAccountCredentials.fromJson(_oauthCredentials);
      _authClient = await clientViaServiceAccount(_credentials!, [
        SheetsApi.spreadsheetsScope,
      ], baseClient: timeoutClient);

      _sheetsClient = SheetsApi(_authClient!);
      _spreadsheet = await _sheetsClient?.spreadsheets.get(_sheetId!);

      final existingTitles =
          _spreadsheet?.sheets
              ?.map((s) => s.properties?.title)
              .whereType<String>()
              .toList() ??
          [];

      final initRequests = [
        if (!existingTitles.contains(AttendanceTrackerBackend.memberSheetName))
          Request(
            addSheet: AddSheetRequest(
              properties: SheetProperties(
                title: AttendanceTrackerBackend.memberSheetName,
              ),
            ),
          ),
        if (!existingTitles.contains(AttendanceTrackerBackend.logSheetName))
          Request(
            addSheet: AddSheetRequest(
              properties: SheetProperties(
                title: AttendanceTrackerBackend.logSheetName,
              ),
            ),
          ),
      ];
      if (initRequests.isNotEmpty) {
        final request = BatchUpdateSpreadsheetRequest(requests: initRequests);
        await _sheetsClient?.spreadsheets.batchUpdate(request, _sheetId!);
      }

      googleConnected.value = _spreadsheet != null;
      print("Loaded spreadsheet: ${_sheetId!}");
    } catch (e) {
      googleConnected.value = false;
      print('Error initializing SheetsClient: $e');
      if (_googleAttemptBringupTimer == null) {
        _googleAttemptBringupTimer = RestartableTimer(Duration(seconds: 1), () {
          _onGoogleDisconnected();
        });
      } else {
        _googleAttemptBringupTimer?.reset();
      }
    }
  }

  Future<void> _updateMembers() async {
    if (googleConnected.value != true) {
      return;
    }

    ValueRange? membersTableResponse;
    try {
      membersTableResponse = await _sheetsClient?.spreadsheets.values.get(
        _sheetId ?? "",
        AttendanceTrackerBackend.memberSheetContentsRange,
      );
    } on SocketException catch (e) {
      print("Google is down!!! $e");
      googleConnected.value = false;
      return;
    } on TimeoutException catch (e) {
      print("Google is down with timeout!!! $e");
      googleConnected.value = false;
      return;
    }

    if (membersTableResponse == null || membersTableResponse.values == null) {
      return;
    }

    // apply members
    List<Member> newMembers = [];
    for (List<dynamic> googleMember in membersTableResponse.values!) {
      // ID, Name, Privilege, Status, Location
      newMembers.add(
        Member(
          int.tryParse(googleMember[0] as String) ?? -1,
          googleMember[1] as String,
          AttendanceStatus.values.byName(
            (googleMember[3] as String).toLowerCase(),
          ),
          location: googleMember[4] as String,
          privilege: MemberPrivilege.values.byName(
            (googleMember[2] as String).toLowerCase(),
          ),
        ),
      );
    }
    attendance.value = newMembers;
  }

  Future<void> _update() async {
    if (googleConnected.value != true) {
      return;
    }

    // these will be used in the log for full data
    final frozedClockInQueue = _clockInQueue.toList();
    final frozedClockOutQueue = _clockOutQueue.toList();
    List<TimeClockEvent> timeClockEvents =
        (frozedClockInQueue + frozedClockOutQueue)
          ..sort((a, b) => a.time.compareTo(b.time));
    print(timeClockEvents);

    // these will be used in the member table for current data
    Map<int, AttendanceStatus> userStatusUpdates = {};
    Map<int, String> userLocationUpdates = {};

    ValueRange? memberIdTableResponse;
    try {
      memberIdTableResponse = await _sheetsClient?.spreadsheets.values.get(
        _sheetId ?? "",
        AttendanceTrackerBackend.memberSheetIdsRange,
      );
    } on SocketException catch (e) {
      print("Google is down!!! $e");
      googleConnected.value = false;
      return;
    } on TimeoutException catch (e) {
      print("Google is down with timeout!!! $e");
      googleConnected.value = false;
      return;
    }

    if (memberIdTableResponse == null || memberIdTableResponse.values == null) {
      return;
    }
    List<int> memberIds = [];
    for (var item in memberIdTableResponse.values!) {
      memberIds.add(int.parse(item[0].toString()));
    }

    for (TimeClockEvent event in timeClockEvents) {
      if (!memberIds.contains(event.memberId)) {
        print(
          "Member ID ${event.memberId} not found in table, maybe the member list was remotely updated?",
        );
        return;
      }
      userStatusUpdates[event.memberId] = event is ClockInEvent
          ? AttendanceStatus.present
          : AttendanceStatus.out;
      if (event is ClockInEvent) {
        userLocationUpdates[event.memberId] = event.location;
      } else {
        userLocationUpdates[event.memberId] = "NULL";
      }
    }

    try {
      // Build ValueRange updates
      final List<ValueRange> updates = [];

      for (final entry in userStatusUpdates.entries) {
        final memberId = entry.key;
        final status = entry.value;

        final index = memberIds.indexOf(memberId);

        if (index == -1) continue; // skip if ID not found

        final row = index + 3;
        final range =
            '${memberSheetContentsRange.split("!").first}!D$row'; // Adjust sheet name if needed
        updates.add(
          ValueRange(
            range: range,
            values: [
              [status.toString().split('.').last.capitalize()],
            ],
          ),
        );
      }

      final batchRequest = BatchUpdateValuesRequest(
        valueInputOption: 'USER_ENTERED',
        data: updates,
      );

      await _sheetsClient?.spreadsheets.values.batchUpdate(
        batchRequest,
        _sheetId ?? "",
      );
    } on SocketException catch (e) {
      print("Google is down!!! $e");
      googleConnected.value = false;
      return;
    } on TimeoutException catch (e) {
      print("Google is down with timeout!!! $e");
      googleConnected.value = false;
      return;
    }

    _clockInQueue.removeWhere(
      (element) => frozedClockInQueue.contains(element),
    );
    _clockOutQueue.removeWhere(
      (element) => frozedClockOutQueue.contains(element),
    );
  }

  List<String> getNames() {
    return attendance.value.map((member) => member.name).toList();
  }

  Member getMemberById(int id) {
    return attendance.value.firstWhere((member) => member.id == id);
  }

  bool isMember(int id) {
    return attendance.value.any((member) => member.id == id);
  }

  void clockOut(int memberId) {
    if (!attendance.value.any((member) => member.id == memberId)) {
      throw Exception('Member with ID $memberId not found');
    }

    final event = ClockOutEvent(memberId, DateTime.now());
    _clockOutQueue.add(event);
    if (_clockInQueue
        .map((e) => e is ClockInEvent ? e.memberId : null)
        .contains(memberId)) {
      _clockInQueue.removeWhere(
        (e) => (e is ClockInEvent ? e.memberId : null) == memberId,
      );
    }

    final memberIndex = attendance.value.indexWhere(
      (member) => member.id == memberId,
    );
    if (memberIndex != -1) {
      attendance.value[memberIndex] = Member(
        attendance.value[memberIndex].id,
        attendance.value[memberIndex].name,
        AttendanceStatus.out,
        location: null,
        privilege: attendance.value[memberIndex].privilege,
      );
      attendance.value = [
        ...attendance.value,
      ]; // I think this is a bug in ValueNotifier
    }
  }

  void clockIn(int memberId, String location) {
    if (!attendance.value.any((member) => member.id == memberId)) {
      throw Exception('Member with ID $memberId not found');
    }

    final event = ClockInEvent(memberId, DateTime.now(), location);
    _clockInQueue.add(event);
    if (_clockOutQueue
        .map((e) => e is ClockOutEvent ? e.memberId : null)
        .contains(memberId)) {
      _clockOutQueue.removeWhere(
        (e) => (e is ClockOutEvent ? e.memberId : null) == memberId,
      );
    }

    final memberIndex = attendance.value.indexWhere(
      (member) => member.id == memberId,
    );
    if (memberIndex != -1) {
      attendance.value[memberIndex] = Member(
        attendance.value[memberIndex].id,
        attendance.value[memberIndex].name,
        AttendanceStatus.present,
        location: location,
        privilege: attendance.value[memberIndex].privilege,
      );
      attendance.value = [
        ...attendance.value,
      ]; // I think this is a bug in ValueNotifier
    }
  }
}
