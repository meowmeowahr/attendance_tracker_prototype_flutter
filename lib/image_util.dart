import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

String pngToBase64(String imagePath) {
  File imageFile = File(imagePath);
  List<int> imageBytes = imageFile.readAsBytesSync();
  return base64Encode(imageBytes);
}

Future<String> assetPngToBase64(String imagePath) async {
  // 1. Load the asset bytes asynchronously
  // rootBundle.load returns a Future<ByteData>
  ByteData byteData = await rootBundle.load(imagePath);

  // 2. Convert ByteData to Uint8List (which implements List<int>)
  Uint8List imageBytes = byteData.buffer.asUint8List();

  // 3. Encode the bytes to Base64 string
  return base64Encode(imageBytes);
}
