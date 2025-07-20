enum AttendanceStatus { present, absent }

enum MemberPrivilege { admin, student }

class Member {
  final int id;
  final String name;
  final AttendanceStatus status;
  final MemberPrivilege privilege;
  Member(
    this.id,
    this.name,
    this.status, {
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
        privilege: MemberPrivilege.admin,
      ),
      Member(2, 'Jane Smith', AttendanceStatus.absent),
      Member(3, 'Alice Johnson', AttendanceStatus.present),
    ];
  }

  Future<List<String>> fetchNames() async {
    await Future.delayed(Duration(seconds: 1));
    return ['John Doe', 'Jane Smith', 'Alice Johnson'];
  }
}
