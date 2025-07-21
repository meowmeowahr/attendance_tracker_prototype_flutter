import 'dart:io';
import 'package:flutter/material.dart';
import 'package:xml/xml.dart';

class KeyEvent {
  final String key;
  final DateTime timestamp;

  KeyEvent(this.key) : timestamp = DateTime.now();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KeyEvent &&
          runtimeType == other.runtimeType &&
          key == other.key &&
          timestamp == other.timestamp;

  @override
  int get hashCode => key.hashCode ^ timestamp.hashCode;
}

// Event bus for virtual keyboard events
class VirtualKeyEventBus {
  static VirtualKeyEventBus? _instance;
  static VirtualKeyEventBus get instance {
    _instance ??= VirtualKeyEventBus._internal();
    return _instance!;
  }

  VirtualKeyEventBus._internal();

  final ValueNotifier<KeyEvent?> _keyEventNotifier = ValueNotifier<KeyEvent?>(
    null,
  );
  ValueNotifier<KeyEvent?> get keyEventNotifier => _keyEventNotifier;

  void emitKeyEvent(String key) {
    _keyEventNotifier.value = KeyEvent(key);
  }

  void dispose() {
    _keyEventNotifier.dispose();
  }
}

// Virtual TextField that responds to virtual keyboard events
class VirtualTextField extends StatefulWidget {
  final String? hintText;
  final bool requireFocus;
  final TextStyle? style;
  final InputDecoration? decoration;
  final int? maxLines;
  final Function(String)? onChanged;

  const VirtualTextField({
    super.key,
    this.hintText,
    this.requireFocus = true,
    this.style,
    this.decoration,
    this.maxLines = 1,
    this.onChanged,
  });

  @override
  State<VirtualTextField> createState() => _VirtualTextFieldState();
}

class _VirtualTextFieldState extends State<VirtualTextField> {
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();

    // Listen to virtual key events
    VirtualKeyEventBus.instance.keyEventNotifier.addListener(
      _onVirtualKeyEvent,
    );
  }

  @override
  void dispose() {
    VirtualKeyEventBus.instance.keyEventNotifier.removeListener(
      _onVirtualKeyEvent,
    );
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onVirtualKeyEvent() {
    final key = VirtualKeyEventBus.instance.keyEventNotifier.value;
    if (key == null) return;
    // if (widget.requireFocus && !_focusNode.hasFocus) return;

    switch (key.key) {
      case 'backspace':
        if (_controller.selection.isCollapsed) {
          // No selection, delete previous character
          if (_controller.text.isEmpty) return;
          final newText = _controller.text.substring(
            0,
            _controller.text.length - 1,
          );
          _controller.value = TextEditingValue(text: newText);
        } else {
          // Has selection, delete selected text
          _controller.text = _controller.text.replaceRange(
            _controller.selection.start,
            _controller.selection.end,
            '',
          );
          _controller.selection = TextSelection.collapsed(
            offset: _controller.selection.start,
          );
        }
        break;
      case 'return':
        if (widget.maxLines != 1) {
          final text = _controller.text;
          final newText = '$text\n'; // Add newline for multi-line text
          _controller.value = TextEditingValue(text: newText);
        }
        break;
      default:
        // Insert the character
        final text = _controller.text;
        final newText = text + key.key;
        _controller.value = TextEditingValue(text: newText);
    }
    widget.onChanged?.call(_controller.text);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      style: widget.style,
      maxLines: widget.maxLines,
      decoration:
          widget.decoration ??
          InputDecoration(
            hintText: widget.hintText,
            border: const OutlineInputBorder(),
          ),
      // Disable physical keyboard input
      keyboardType: TextInputType.none,
      showCursor: true,
      readOnly: true,
      onChanged: widget.onChanged,
    );
  }
}

// Key data model
class KeyData {
  final String type;
  final String symbol;
  final String style;
  final String? keystroke;
  final double width;
  final String? layoutLink;

  KeyData({
    required this.type,
    required this.symbol,
    required this.style,
    this.keystroke,
    required this.width,
    this.layoutLink,
  });
}

// Row data model
class RowData {
  final String? type;
  final List<dynamic> elements; // KeyData or SpacerData

  RowData({this.type, required this.elements});
}

// Spacer data model
class SpacerData {
  final String type;
  final double width;

  SpacerData({required this.type, required this.width});
}

// Layout data model
class LayoutData {
  final String layoutName;
  final List<RowData> rows;

  LayoutData({required this.layoutName, required this.rows});
}

// Virtual Keyboard Widget
class VirtualKeyboard extends StatefulWidget {
  final String rootLayoutPath;
  final double keyWidth;
  final double keyHeight;

  const VirtualKeyboard({
    super.key,
    required this.rootLayoutPath,
    this.keyWidth = 48.0,
    this.keyHeight = 40.0,
  });

  @override
  State<VirtualKeyboard> createState() => _VirtualKeyboardState();
}

class _VirtualKeyboardState extends State<VirtualKeyboard>
    with AutomaticKeepAliveClientMixin<VirtualKeyboard> {
  late PageController _pageController;
  final Map<String, int> _layoutNameToIndex = {};
  final Map<String, LayoutData> _parsedLayoutsCache = {};
  String? _rootLayoutFilename;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _rootLayoutFilename = widget.rootLayoutPath.split('/').last;
    _buildLayouts();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => _parsedLayoutsCache.isNotEmpty;

  Future<LayoutData?> _parseLayoutXml(String path) async {
    if (_parsedLayoutsCache.containsKey(path)) {
      return _parsedLayoutsCache[path];
    }

    try {
      final file = File(path);
      final xmlString = await file.readAsString();
      final document = XmlDocument.parse(xmlString);
      final root = document.rootElement;

      final layoutName = root.getAttribute('name') ?? 'Unknown Layout';
      final rows = <RowData>[];

      for (final rowElement in root.findElements('Row')) {
        final rowType = rowElement.getAttribute('type');
        final elements = <dynamic>[];

        for (final element in rowElement.children.whereType<XmlElement>()) {
          if (element.name.local == 'Key') {
            final keyData = KeyData(
              type: 'key',
              symbol: element.getAttribute('symbol') ?? '',
              style: element.getAttribute('style') ?? 'Std',
              keystroke: element.getAttribute('keystroke'),
              width:
                  double.tryParse(element.getAttribute('width') ?? '1.0') ??
                  1.0,
              layoutLink: element.getAttribute('layoutLink'),
            );
            elements.add(keyData);
          } else if (element.name.local == 'Spacer') {
            final spacerData = SpacerData(
              type: 'spacer',
              width:
                  double.tryParse(element.getAttribute('width') ?? '1.0') ??
                  1.0,
            );
            elements.add(spacerData);
          }
        }

        rows.add(RowData(type: rowType, elements: elements));
      }

      final layoutData = LayoutData(layoutName: layoutName, rows: rows);
      _parsedLayoutsCache[path] = layoutData;
      return layoutData;
    } catch (e) {
      debugPrint('Error parsing XML file $path: $e');
      return null;
    }
  }

  Future<void> _buildLayouts() async {
    await _buildLayoutsRecursive(widget.rootLayoutPath, _rootLayoutFilename!);
  }

  Future<void> _buildLayoutsRecursive(
    String currentPath,
    String currentLinkName,
  ) async {
    if (_layoutNameToIndex.containsKey(currentLinkName)) {
      return;
    }

    final layoutData = await _parseLayoutXml(currentPath);
    if (layoutData == null) return;

    final index = _layoutNameToIndex.length;
    _layoutNameToIndex[currentLinkName] = index;

    // Process layout links for recursive loading
    for (final row in layoutData.rows) {
      for (final element in row.elements) {
        if (element is KeyData && element.layoutLink != null) {
          if (element.layoutLink == 'ROOT') continue;

          final directory = currentPath.substring(
            0,
            currentPath.lastIndexOf('/'),
          );
          final nextLayoutPath = '$directory/${element.layoutLink}';
          await _buildLayoutsRecursive(nextLayoutPath, element.layoutLink!);
        }
      }
    }
  }

  void _switchToLayout(String targetLayoutLinkName) {
    if (!_layoutNameToIndex.containsKey(targetLayoutLinkName)) {
      debugPrint(
        'Attempted to switch to unknown layout: $targetLayoutLinkName',
      );
      return;
    }

    final targetIndex = _layoutNameToIndex[targetLayoutLinkName]!;
    _pageController.jumpToPage(targetIndex);
  }

  Widget _buildLayoutWidget(LayoutData layoutData) {
    return Container(
      padding: const EdgeInsets.all(8.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: layoutData.rows.map((row) => _buildRowWidget(row)).toList(),
      ),
    );
  }

  Widget _buildRowWidget(RowData row) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Spacer(),
        ...row.elements.map((element) => _buildElementWidget(element)),
        const Spacer(),
      ],
    );
  }

  Widget _buildElementWidget(dynamic element) {
    if (element is SpacerData) {
      return SizedBox(width: element.width * widget.keyWidth);
    } else if (element is KeyData) {
      return _buildKeyWidget(element);
    }
    return const SizedBox.shrink();
  }

  Widget _buildKeyWidget(KeyData keyData) {
    Widget keyContent;

    switch (keyData.symbol) {
      case 'ICON_SHIFT':
        keyContent = const Icon(Icons.keyboard_arrow_up);
        break;
      case 'ICON_UNSHIFT':
        keyContent = const Icon(Icons.keyboard_arrow_up);
        break;
      case 'ICON_BKSP':
        keyContent = const Icon(Icons.backspace_outlined);
        break;
      default:
        keyContent = Text(keyData.symbol);
    }

    Widget child;
    if (keyData.style == "Primary") {
      child = FilledButton(
        onPressed: () => _onKeyPressed(keyData),
        style: FilledButton.styleFrom(
          elevation: 1,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4.0),
          ),
          splashFactory: NoSplash.splashFactory,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          textStyle: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
        ),
        child: keyContent,
      );
    } else if (keyData.style == "Secondary") {
      child = FilledButton(
        onPressed: () => _onKeyPressed(keyData),
        style: FilledButton.styleFrom(
          elevation: 1,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4.0),
          ),
          splashFactory: NoSplash.splashFactory,
          backgroundColor: Theme.of(context).colorScheme.secondary,
          textStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSecondary,
          ),
        ),
        child: keyContent,
      );
    } else if (keyData.style == "Tertiary") {
      child = FilledButton(
        onPressed: () => _onKeyPressed(keyData),
        style: FilledButton.styleFrom(
          elevation: 1,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4.0),
          ),
          splashFactory: NoSplash.splashFactory,
          backgroundColor: Theme.of(context).colorScheme.tertiary,
          foregroundColor: Theme.of(context).colorScheme.onTertiary,
          textStyle: TextStyle(color: Theme.of(context).colorScheme.onTertiary),
        ),
        child: keyContent,
      );
    } else {
      child = ElevatedButton(
        onPressed: () => _onKeyPressed(keyData),
        style: ElevatedButton.styleFrom(
          elevation: 1,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4.0),
          ),
          splashFactory: NoSplash.splashFactory,
        ),
        child: keyContent,
      );
    }

    return Padding(
      padding: const EdgeInsets.all(2.0),
      child: SizedBox(
        width: (keyData.width * widget.keyWidth).clamp(
          widget.keyWidth,
          double.infinity,
        ),
        height: widget.keyHeight,
        child: child,
      ),
    );
  }

  void _onKeyPressed(KeyData keyData) {
    if (keyData.layoutLink != null) {
      String targetLinkName = keyData.layoutLink!;
      if (targetLinkName == 'ROOT') {
        targetLinkName = _rootLayoutFilename!;
      }
      _switchToLayout(targetLinkName);
    } else if (keyData.keystroke != null) {
      VirtualKeyEventBus.instance.emitKeyEvent(keyData.keystroke!);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_parsedLayoutsCache.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return PageView(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(), // Only switch via buttons
      children: _parsedLayoutsCache.values.map(_buildLayoutWidget).toList(),
    );
  }
}
