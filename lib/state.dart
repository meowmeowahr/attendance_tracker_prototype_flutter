import 'package:flutter/material.dart';

class AppState {
  final Color color;
  final String description;

  AppState(this.color, this.description);

  static AppState initial = AppState(Colors.white, 'Please Wait...');
}

class SerialPortState {
  final bool isConnected;
  final dynamic error;

  SerialPortState(this.isConnected, this.error);
}
