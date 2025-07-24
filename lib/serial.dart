import 'dart:io' show Platform, Directory, FileSystemEntity;

import 'package:flutter_libserialport/flutter_libserialport.dart'
    if (dart.library.io) 'package:flutter_libserialport/flutter_libserialport.dart';

List<String> get listPortPaths {
  // Linux: Custom port search for /dev/ttyS*, /dev/ttyAMA*, /dev/ttyACM*
  if (Platform.isLinux) {
    try {
      final devDir = Directory('/dev');
      final portPatterns = RegExp(r'^tty(S|AMA|ACM|USB)');
      final ports = devDir
          .listSync(recursive: false)
          .whereType<FileSystemEntity>()
          .map((entity) => entity.path)
          .where((path) => portPatterns.hasMatch(path.split('/').last))
          .toList();
      return ports..sort(); // Sort for consistent ordering
    } catch (e) {
      print('Error listing serial ports on Linux: $e');
      return [];
    }
  }
  // Windows and macOS: Use flutter_libserialport
  else if (Platform.isWindows || Platform.isMacOS) {
    try {
      return SerialPort.availablePorts;
    } catch (e) {
      print('Error accessing serial ports: $e');
      return [];
    }
  }
  // Unsupported platforms (Android, iOS, web): Return empty list
  return [];
}
