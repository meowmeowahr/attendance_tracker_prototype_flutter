import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, Directory, FileSystemEntity;
import 'dart:typed_data';

import 'package:attendance_tracker/state.dart';
import 'package:attendance_tracker/util.dart';
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

class SerialRfidStream {
  SerialPort? _port;
  SerialPortReader? _reader;
  late StreamController<int?> _controller;
  List<int> _inWaiting = [];
  String? eolString;
  String? solString;

  String? _currentPortPath;
  int _baudRate = 9600;
  int _readTimeoutMs = 100;
  int _writeTimeoutMs = 100;

  // Stream getter
  Stream<int?> get stream => _controller.stream;

  // RFID format
  ChecksumStyle checksumStyle = ChecksumStyle.none;
  ChecksumPosition checksumPosition = ChecksumPosition.end;
  DataFormat dataFormat = DataFormat.decAscii;

  // Configuration getters
  String? get portPath => _currentPortPath;
  int get baudRate => _baudRate;
  int get readTimeoutMs => _readTimeoutMs;
  int get writeTimeoutMs => _writeTimeoutMs;
  bool get isConnected => _port?.isOpen ?? false;
  dynamic portError;
  SerialPortState get state => SerialPortState(isConnected, portError);

  SerialRfidStream() {
    _controller = StreamController<int?>.broadcast(
      onCancel: () {
        _stopReading();
      },
    );
  }

  /// Configure the serial port settings
  /// Returns true if configuration was successful
  bool configure({
    String? portPath,
    int? baudRate,
    int? readTimeoutMs,
    int? writeTimeoutMs,
    String? eolString,
    String? solString,
    ChecksumStyle? checksumStyle,
    ChecksumPosition? checksumPosition,
    DataFormat? dataFormat,
  }) {
    this.eolString = eolString;
    this.solString = solString;
    if (checksumStyle != null) this.checksumStyle = checksumStyle;
    if (checksumPosition != null) this.checksumPosition = checksumPosition;
    if (dataFormat != null) this.dataFormat = dataFormat;
    try {
      bool needsReconnect = false;

      // Check if port path changed
      if (portPath != null && portPath != _currentPortPath) {
        _currentPortPath = portPath;
        needsReconnect = true;
      }

      // Update other settings
      if (baudRate != null) {
        _baudRate = baudRate;
        needsReconnect = true;
      }

      if (readTimeoutMs != null) {
        _readTimeoutMs = readTimeoutMs;
      }

      if (writeTimeoutMs != null) {
        _writeTimeoutMs = writeTimeoutMs;
      }

      // Reconnect if needed and currently connected
      if (needsReconnect && isConnected) {
        disconnect();
        return connect();
      }

      return true;
    } catch (e) {
      print('Error configuring serial port: $e');
      return false;
    }
  }

  /// Connect to the serial port with current configuration
  bool connect() {
    if (_currentPortPath == null) {
      print('No port path configured');
      return false;
    }

    try {
      // Disconnect if already connected
      if (isConnected) {
        disconnect();
      }

      // Create new port instance
      _port = SerialPort(_currentPortPath!);

      // Configure port settings
      final config = SerialPortConfig();
      config.baudRate = _baudRate;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = SerialPortParity.none;
      config.setFlowControl(SerialPortFlowControl.none);

      if (!_port!.openRead()) {
        final error = SerialPort.lastError;
        print('Failed to open port: ${error?.message}');
        _port?.dispose();
        _port = null;
        return false;
      }

      _port!.config = config;

      // Start reading
      _startReading();

      print('Connected to $_currentPortPath at $_baudRate baud');
      return true;
    } catch (e) {
      print('Error connecting to serial port: $e');
      _port?.close();
      _port?.dispose();
      _port = null;
      return false;
    }
  }

  /// Disconnect from the serial port
  void disconnect() {
    try {
      _stopReading();

      _port?.close();
      _port?.dispose();
      _port = null;

      print('Disconnected from serial port');
    } catch (e) {
      print('Error disconnecting from serial port: $e');
    }
  }

  int _indexOfSequence(
    List<int> source,
    List<int> pattern, [
    int startIndex = 0,
  ]) {
    if (source.length < pattern.length ||
        startIndex > source.length - pattern.length) {
      return -1;
    }
    for (int i = startIndex; i <= source.length - pattern.length; i++) {
      bool match = true;
      for (int j = 0; j < pattern.length; j++) {
        if (source[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }

  void _startReading() {
    _reader?.close(); // Prevent multiple listeners
    _reader = SerialPortReader(_port!);
    _reader?.stream.listen(
      (Uint8List data) {
        _inWaiting.addAll(data);

        // Convert solString and eolString to byte sequences
        final solBytes = solString == 'NONE' || solString == null
            ? null
            : Uint8List.fromList(solString!.codeUnits);
        final eolBytes = Uint8List.fromList(eolString!.codeUnits);

        while (_inWaiting.isNotEmpty) {
          List<int> message;
          int endIndex;

          if (solBytes == null) {
            // Case: solString = 'NONE'
            endIndex = _indexOfSequence(_inWaiting, eolBytes);
            if (endIndex == -1) break; // Incomplete message
            message = _inWaiting.sublist(0, endIndex);
            _inWaiting = _inWaiting.sublist(endIndex + eolBytes.length);
          } else if (solString == eolString) {
            // Case: solString == eolString
            final firstIndex = _indexOfSequence(_inWaiting, solBytes);
            if (firstIndex == -1) {
              _inWaiting = []; // Clear if no sol found
              break;
            }
            final searchStart = firstIndex + solBytes.length;
            if (searchStart >= _inWaiting.length) break; // Incomplete
            final secondIndex = _indexOfSequence(
              _inWaiting,
              solBytes,
              searchStart,
            );
            if (secondIndex == -1) break; // Incomplete
            message = _inWaiting.sublist(
              firstIndex + solBytes.length,
              secondIndex,
            );
            _inWaiting = _inWaiting.sublist(secondIndex);
          } else {
            // Case: Normal solString and eolString
            final solIndex = _indexOfSequence(_inWaiting, solBytes);
            if (solIndex == -1) {
              _inWaiting = []; // Clear if no sol found
              break;
            }
            final messageData = _inWaiting.sublist(solIndex);
            endIndex = _indexOfSequence(messageData, eolBytes);
            if (endIndex == -1) break; // Incomplete
            message = messageData.sublist(solBytes.length, endIndex);
            _inWaiting = messageData.sublist(endIndex + eolBytes.length);
          }

          if (message.isNotEmpty) {
            int? userId = normalizeTagId(
              message,
              checksumStyle,
              checksumPosition,
              dataFormat,
            );
            _controller.add(userId);
          }

          // Prevent buffer overflow (max 1024 bytes)
          if (_inWaiting.length > 1024) {
            _inWaiting = [];
          }
        }
      },
      onError: (error) {
        portError = error;
        disconnect();
      },
    );
  }

  /// Stop reading from the serial port
  void _stopReading() {
    try {
      _reader?.close();
      _reader = null;
    } catch (e) {
      print('Error stopping serial port reader: $e');
    }
  }

  /// Write data to the serial port
  bool write(String data) {
    if (_port == null || !_port!.isOpen) {
      print('Port not connected');
      return false;
    }

    try {
      final bytes = Uint8List.fromList(data.codeUnits);
      final written = _port!.write(bytes, timeout: _writeTimeoutMs);
      return written == bytes.length;
    } catch (e) {
      print('Error writing to serial port: $e');
      return false;
    }
  }

  /// Clean up resources
  void dispose() {
    disconnect();
  }
}
