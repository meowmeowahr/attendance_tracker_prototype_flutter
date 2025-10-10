import 'dart:convert';

import 'package:crypto/crypto.dart';

String hashPin(String pin) {
  final bytes = utf8.encode(pin);
  final digest = sha256.convert(bytes);
  return digest.toString();
}

bool isValidHash(String input) {
  final sha256Regex = RegExp(r'^[a-fA-F0-9]{64}$');
  return sha256Regex.hasMatch(input);
}
