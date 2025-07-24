String escapeFormatCharacters(String input) {
  // Map of format characters to their escaped versions
  final escapeMap = {
    '\n': '\\n', // Newline
    '\t': '\\t', // Tab
    '\r': '\\r', // Carriage return
    '\b': '\\b', // Backspace
    '\f': '\\f', // Form feed
    '\\': '\\\\', // Backslash itself
    '"': '\\"', // Double quote
    "'": "\\'", // Single quote
  };

  // Replace each format character with its escaped version
  return input.replaceAllMapped(
    RegExp('[\x0A\x09\x0D\x08\x0C\\\\"\']'),
    (Match match) => escapeMap[match.group(0)] ?? match.group(0)!,
  );
}
