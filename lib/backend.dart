import 'dart:collection';
import 'dart:ffi';

import 'package:flutter/cupertino.dart';

enum AttendanceStatus { active, inactive }

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
}

class ClockInEvent {
  final int memberId;
  final DateTime time;
  final String location;

  ClockInEvent(this.memberId, this.time, this.location);
}

class ClockOutEvent {
  final int memberId;
  final DateTime time;

  ClockOutEvent(this.memberId, this.time);
}

class AttendanceTrackerBackend {
  final _clockInQueue = Queue<ClockInEvent>();
  final _clockOutQueue = Queue<ClockOutEvent>();
  ValueNotifier<List<Member>> attendance = ValueNotifier([
    Member(
      1,
      'John Middle Doe',
      AttendanceStatus.active,
      location: "Outreach Event",
      privilege: MemberPrivilege.admin,
    ),
    Member(2, 'Jane Smith', AttendanceStatus.inactive),
    Member(3, 'Alice Johnson', AttendanceStatus.active, location: "Shop"),
  ]);

  void initialize() async {
    _clockInQueue.clear();
    _clockOutQueue.clear();
    attendance.value = [
      Member(
        1,
        'John Middle Doe',
        AttendanceStatus.active,
        location: "Outreach Event",
        privilege: MemberPrivilege.admin,
      ),
      Member(2, 'Jane Smith', AttendanceStatus.inactive),
      Member(3, 'Alice Johnson', AttendanceStatus.active, location: "Shop"),
    ];
  }

  Future<List<String>> fetchNames() async {
    await Future.delayed(Duration(seconds: 1));
    return attendance.value.map((member) => member.name).toList();
  }

  void clockOut(int memberId) {
    if (!attendance.value.any((member) => member.id == memberId)) {
      throw Exception('Member with ID $memberId not found');
    }

    final event = ClockOutEvent(memberId, DateTime.now());
    _clockOutQueue.add(event);
    if (_clockInQueue.map((e) => e.memberId).contains(memberId)) {
      _clockInQueue.removeWhere((e) => e.memberId == memberId);
    }

    final memberIndex = attendance.value.indexWhere(
      (member) => member.id == memberId,
    );
    if (memberIndex != -1) {
      attendance.value[memberIndex] = Member(
        attendance.value[memberIndex].id,
        attendance.value[memberIndex].name,
        AttendanceStatus.inactive,
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
    if (_clockOutQueue.map((e) => e.memberId).contains(memberId)) {
      _clockOutQueue.removeWhere((e) => e.memberId == memberId);
    }

    final memberIndex = attendance.value.indexWhere(
      (member) => member.id == memberId,
    );
    if (memberIndex != -1) {
      attendance.value[memberIndex] = Member(
        attendance.value[memberIndex].id,
        attendance.value[memberIndex].name,
        AttendanceStatus.active,
        location: location,
        privilege: attendance.value[memberIndex].privilege,
      );
      attendance.value = [
        ...attendance.value,
      ]; // I think this is a bug in ValueNotifier
    }
  }
}
