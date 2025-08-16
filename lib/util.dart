String unescapeFormatCharacters(String input) {
  // Map of format characters to their escaped versions
  final escapeMap = {
    '\\n': '\n', // Newline
    '\\t': '\t', // Tab
    '\\r': '\r', // Carriage return
    '\\b': '\b', // Backspace
    '\\f': '\f', // Form feed
    '\\\\': '\\', // Backslash itself
    '\\"': '"', // Double quote
    "\\'": "'", // Single quote
    "\\x02": "\x02", // STX
    "\\x03": "\x03", // ETX
  };

  for (var key in escapeMap.keys) {
    input = input.replaceAll(key, escapeMap[key]!);
  }
  return input;
}

String columnToReference(int col) {
  if (col <= 0) {
    throw ArgumentError('Column number must be a positive integer.');
  }

  var result = '';
  var current = col;

  while (current > 0) {
    final remainder = (current - 1) % 26;
    result = String.fromCharCode(65 + remainder) + result;
    current = (current - 1) ~/ 26;
  }

  return result;
}

enum ChecksumStyle { none, xor2hex, xor1byte }

enum DataFormat { decAscii, hexAscii, bin }

enum ChecksumPosition { start, end }

int? normalizeTagId(
  List<int> message,
  ChecksumStyle checksumStyle,
  ChecksumPosition checksumPosition,
  DataFormat dataFormat,
) {
  try {
    List<int> tagId;
    int? checksumByte;
    String? checksumStr;

    // Extract checksum based on position
    switch (checksumStyle) {
      case ChecksumStyle.none:
        tagId = message;
        break;
      case ChecksumStyle.xor2hex:
        if (message.length < 2) return null;
        if (checksumPosition == ChecksumPosition.end) {
          tagId = message.sublist(0, message.length - 2);
          checksumStr = String.fromCharCodes(
            message.sublist(message.length - 2),
          );
        } else {
          checksumStr = String.fromCharCodes(message.sublist(0, 2));
          tagId = message.sublist(2);
        }
        // XOR checksum validation
        List<int> pairs = [];
        String tagStr = String.fromCharCodes(tagId);
        for (int i = 0; i < tagStr.length; i += 2) {
          pairs.add(int.parse(tagStr.substring(i, i + 2), radix: 16));
        }
        int calcChecksum = pairs.reduce((a, b) => a ^ b);
        if (calcChecksum != int.parse(checksumStr, radix: 16)) {
          print('Checksum validation failed: $message');
          return null;
        }
        break;
      case ChecksumStyle.xor1byte:
        if (message.length < 1) return null;
        if (checksumPosition == ChecksumPosition.end) {
          tagId = message.sublist(0, message.length - 1);
          checksumByte = message.last;
        } else {
          checksumByte = message.first;
          tagId = message.sublist(1);
        }
        int calcChecksum = tagId.reduce((a, b) => a ^ b);
        if (calcChecksum != checksumByte) {
          print('Checksum validation failed: $message');
          return null;
        }
        break;
    }

    // Convert tag ID to integer based on data format
    switch (dataFormat) {
      case DataFormat.decAscii:
        String tagStr = String.fromCharCodes(tagId);
        if (!RegExp(r'^\d+$').hasMatch(tagStr)) return null;
        return int.parse(tagStr);
      case DataFormat.hexAscii:
        String tagStr = String.fromCharCodes(tagId);
        if (!RegExp(r'^[0-9A-Fa-f]+$').hasMatch(tagStr)) return null;
        return int.parse(tagStr, radix: 16);
      case DataFormat.bin:
        if (tagId.every((b) => b <= 0xFF)) {
          return tagId.fold(0, (prev, byte) => (prev ?? 0 << 8) + byte);
        }
        return null;
    }
  } catch (e) {
    print('Error normalizing tag ID: $e');
    return null;
  }
}
