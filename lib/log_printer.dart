import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';

class LevelFilter extends LogFilter {
  final Level minLevel;

  LevelFilter(this.minLevel);

  @override
  bool shouldLog(LogEvent event) {
    return event.level.index >= minLevel.index;
  }
}

class BoundedMemoryPrinter extends LogPrinter {
  final PrettyPrinter _prettyPrinter;
  static const int _maxLength = 1000;

  static final ValueNotifier<List<LogEvent>> logs =
      ValueNotifier<List<LogEvent>>([]);

  BoundedMemoryPrinter({PrettyPrinter? prettyPrinter})
    : _prettyPrinter = prettyPrinter ?? PrettyPrinter(methodCount: 0, dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart, noBoxingByDefault: true);

  @override
  List<String> log(LogEvent event) {
    final formatted = _prettyPrinter.log(event);

    final current = List<LogEvent>.from(logs.value);
    current.add(event);

    if (current.length > _maxLength) {
      current.removeAt(0);
    }

    logs.value = current;

    return formatted;
  }
}
