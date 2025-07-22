enum AttendanceStatus { present, absent }

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

class AttendanceTrackerBackend {
  Future<List<Member>> fetchAttendanceData() async {
    await Future.delayed(Duration(seconds: 1));
    return [
      Member(
        1,
        'John Middle Doe',
        AttendanceStatus.present,
        location: "Outreach Event",
        privilege: MemberPrivilege.admin,
      ),
      Member(2, 'Jane Smith', AttendanceStatus.absent),
      Member(3, 'Alice Johnson', AttendanceStatus.present, location: "Shop"),
    ];
  }

  Future<List<String>> fetchNames() async {
    await Future.delayed(Duration(seconds: 1));
    return ['John Doe', 'Jane Smith', 'Alice Johnson'];
  }
}
