import 'dart:convert';
import 'dart:io';

String pngToBase64(String imagePath) {
  File imageFile = File(imagePath);
  List<int> imageBytes = imageFile.readAsBytesSync();
  return base64Encode(imageBytes);
}
