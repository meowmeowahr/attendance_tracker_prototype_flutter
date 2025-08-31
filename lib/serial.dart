import 'dart:async';
import 'dart:io' show Platform, Directory, FileSystemEntity;
import 'dart:typed_data';

import 'package:attendance_tracker/state.dart';
import 'package:attendance_tracker/util.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart'
    if (dart.library.io) 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:usb_serial/usb_serial.dart';

Future<List<String>> get listPortPaths async {
  // Linux: /dev/ttyS*, /dev/ttyAMA*, /dev/ttyACM*
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
      return ports..sort();
    } catch (e) {
      print('Error listing serial ports on Linux: $e');
      return [];
    }
  }
  // default search
  else if (Platform.isWindows || Platform.isMacOS) {
    try {
      return SerialPort.availablePorts;
    } catch (e) {
      print('Error accessing serial ports: $e');
      return [];
    }
  }
  // usb_serial
  else if (Platform.isAndroid) {
    try {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      print(devices.map((device) => device.deviceName).toList());
      return devices.map((device) => device.deviceName).toList();
    } catch (e) {
      print('Error listing USB serial devices on Android: $e');
      return [];
    }
  }
  return [];
}

class SerialRfidStream {
  dynamic _port; // Can be SerialPort or UsbPort
  bool _portOpened = false; // UsbPort only
  SerialPortReader? _reader;
  UsbPort? _usbPortReader;
  late StreamController<int?> _controller;
  List<int> _inWaiting = [];
  String? eolString;

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
  bool get isConnected {
    if (Platform.isAndroid) {
      return (_port is UsbPort) ? _portOpened : false;
    } else {
      return (_port is SerialPort) ? (_port as SerialPort).isOpen : false;
    }
  }

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
  Future<bool> configure({
    String? portPath,
    int? baudRate,
    int? readTimeoutMs,
    int? writeTimeoutMs,
    String? eolString,
    ChecksumStyle? checksumStyle,
    ChecksumPosition? checksumPosition,
    DataFormat? dataFormat,
  }) async {
    this.eolString = eolString;
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
        // On Android, baud rate change often requires reconnect
        if (Platform.isAndroid) needsReconnect = true;
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
        return await connect();
      }

      return true;
    } catch (e) {
      print('Error configuring serial port: $e');
      return false;
    }
  }

  /// Connect to the serial port with current configuration
  Future<bool> connect() async {
    // Make connect async for Android
    if (_currentPortPath == null) {
      print('No port path configured');
      return false;
    }

    try {
      // Disconnect if already connected
      if (isConnected) {
        disconnect();
      }

      if (Platform.isAndroid) {
        List<UsbDevice> devices = await UsbSerial.listDevices();
        UsbDevice? targetDevice;

        // Find the device by its deviceName (which is the portPath for Android)
        for (var device in devices) {
          if (device.deviceName == _currentPortPath) {
            targetDevice = device;
            break;
          }
        }

        if (targetDevice == null) {
          print('Android: USB device not found for path $_currentPortPath');
          return false;
        }

        UsbPort? port = await targetDevice.create();
        if (port == null) {
          print("Android: Failed to create UsbPort from device.");
          return false;
        }

        bool openResult = await port.open();
        _portOpened = openResult;
        if (!openResult) {
          print("Android: Failed to open UsbPort.");
          return false;
        }

        await port.setPortParameters(
          _baudRate,
          UsbPort.DATABITS_8,
          UsbPort.STOPBITS_1,
          UsbPort.PARITY_NONE,
        );

        // Optional: set DTR/RTS if needed by your device
        // await port.setDTR(true);
        // await port.setRTS(true);

        _port = port;
        _startReading(); // Start reading from the UsbPort's inputStream

        print('Android: Connected to $_currentPortPath at $_baudRate baud');
        return true;
      } else {
        // Create new port instance for non-Android platforms
        _port = SerialPort(_currentPortPath!);

        // Configure port settings
        final config = SerialPortConfig();
        config.baudRate = _baudRate;
        config.bits = 8;
        config.stopBits = 1;
        config.parity = SerialPortParity.none;
        config.setFlowControl(SerialPortFlowControl.none);

        if (!(_port as SerialPort).openRead()) {
          final error = SerialPort.lastError;
          print('Failed to open port: ${error?.message}');
          (_port as SerialPort).dispose();
          _port = null;
          return false;
        }

        (_port as SerialPort).config = config;

        // Start reading
        _startReading();

        print('Connected to $_currentPortPath at $_baudRate baud');
        return true;
      }
    } catch (e) {
      print('Error connecting to serial port: $e');
      if (Platform.isAndroid && _port is UsbPort) {
        (_port as UsbPort).close();
      } else if (_port is SerialPort) {
        (_port as SerialPort).close();
        (_port as SerialPort).dispose();
      }
      _port = null;
      return false;
    }
  }

  /// Disconnect from the serial port
  void disconnect() {
    try {
      _stopReading();

      if (Platform.isAndroid && _port is UsbPort) {
        (_port as UsbPort).close();
        _portOpened = false;
      } else if (_port is SerialPort) {
        (_port as SerialPort).close();
        (_port as SerialPort).dispose();
      }
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
    if (Platform.isAndroid) {
      _usbPortReader?.close(); // Close any previous Android stream
      if (_port is UsbPort) {
        print("here");
        _usbPortReader = _port as UsbPort;
        _usbPortReader?.inputStream?.listen(
          (Uint8List data) {
            _inWaiting.addAll(data);
            _processIncomingData();
          },
          onError: (error) {
            portError = error;
            disconnect();
          },
          onDone: () {
            print("Android UsbPort input stream closed.");
            disconnect();
          },
        );
      }
    } else {
      _reader?.close(); // Prevent multiple listeners for libserialport
      if (_port is SerialPort) {
        _reader = SerialPortReader(_port as SerialPort);
        _reader?.stream.listen(
          (Uint8List data) {
            _inWaiting.addAll(data);
            _processIncomingData();
          },
          onError: (error) {
            portError = error;
            disconnect();
          },
        );
      }
    }
  }

  void _processIncomingData() {
    // Convert eolString to byte sequence (UTF-8 safe)
    final eolBytes = (eolString == null || eolString == 'NONE')
        ? null
        : Uint8List.fromList(eolString!.codeUnits);

    if (eolBytes == null) {
      // You always need an end-of-line marker
      return;
    }

    while (_inWaiting.isNotEmpty) {
      // Look for EOL marker
      int endIndex = _indexOfSequence(_inWaiting, eolBytes);
      if (endIndex == -1) break; // Incomplete message

      // Extract message (everything before EOL)
      List<int> message = _inWaiting.sublist(0, endIndex);

      // Remove processed data from buffer
      _inWaiting = _inWaiting.sublist(endIndex + eolBytes.length);

      if (message.isNotEmpty) {
        print('Received message: $message');
        int? userId = normalizeTagId(
          message,
          checksumStyle,
          checksumPosition,
          dataFormat,
        );
        _controller.add(userId);
      }

      // Prevent runaway buffer
      if (_inWaiting.length > 1024) {
        _inWaiting.clear();
      }
    }
  }

  /// Stop reading from the serial port
  void _stopReading() {
    try {
      if (Platform.isAndroid) {
        _usbPortReader?.close();
        _usbPortReader = null;
      } else {
        _reader?.close();
        _reader = null;
      }
    } catch (e) {
      print('Error stopping serial port reader: $e');
    }
  }

  /// Clean up resources
  void dispose() {
    disconnect();
    _controller.close();
  }
}
