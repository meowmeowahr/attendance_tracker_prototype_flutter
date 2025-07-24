import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RfidTapCard extends StatelessWidget {
  const RfidTapCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Icon(
              Icons.contactless_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.primary,
            ),
            Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Tap your badge to clock in/out",
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                Text(
                  "or manually select your name below",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            Spacer(),
          ],
        ),
      ),
    );
  }
}

class AdminStriper extends StatelessWidget {
  const AdminStriper({super.key});

  @override
  Widget build(BuildContext context) {
    // Measure the text size
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'ADMIN',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontSize: 18,
          letterSpacing: 2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final textWidth =
        textPainter.width + 16.0; // Add padding (8.0 left + 8.0 right)

    return Stack(
      alignment: Alignment.center,
      children: [
        // Background stripes
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CustomPaint(
              painter: _StripePainter(context, textWidth, isLeft: true),
              child: SizedBox(height: 24, width: textWidth / 2),
            ),
            SizedBox(width: textWidth), // Reserve space for text
            CustomPaint(
              painter: _StripePainter(context, textWidth, isLeft: false),
              child: SizedBox(height: 24, width: textWidth / 2),
            ),
          ],
        ),
        // Foreground text
        Padding(
          padding: const EdgeInsets.only(left: 8.0, right: 8.0),
          child: Text(
            'ADMIN',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
              fontSize: 18,
              letterSpacing: 2,
              backgroundColor: Theme.of(context).colorScheme.surface,
            ),
          ),
        ),
      ],
    );
  }
}

class _StripePainter extends CustomPainter {
  final BuildContext context;
  final double textWidth;
  final bool isLeft;

  _StripePainter(this.context, this.textWidth, {required this.isLeft});

  @override
  void paint(Canvas canvas, Size size) {
    const stripeWidth = 20.0;
    final paint = Paint();
    final path = Path();

    // Calculate the stripe boundaries based on text width
    final halfTextWidth = textWidth / 2;
    final startX = isLeft ? -size.height : halfTextWidth;
    final endX = isLeft ? halfTextWidth : halfTextWidth + size.width;

    for (double x = startX; x < endX; x += stripeWidth * 2) {
      path.reset();
      path.moveTo(x, 0);
      path.lineTo(x + stripeWidth, 0);
      path.lineTo(x + stripeWidth - size.height, size.height);
      path.lineTo(x - size.height, size.height);
      path.close();

      paint.color = Theme.of(context).colorScheme.tertiary;
      canvas.drawPath(path, paint);

      path.reset();
      path.moveTo(x + stripeWidth, 0);
      path.lineTo(x + stripeWidth * 2, 0);
      path.lineTo(x + stripeWidth * 2 - size.height, size.height);
      path.lineTo(x + stripeWidth - size.height, size.height);
      path.close();

      paint.color = Theme.of(context).colorScheme.surface;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

class DoubleSpinBox extends StatefulWidget {
  final double min;
  final double max;
  final double step;
  final double initialValue;
  final ValueChanged<double>? onChanged;

  const DoubleSpinBox({
    super.key,
    this.min = 0.1,
    this.max = 2.0,
    this.step = 0.1,
    this.initialValue = 1.0,
    this.onChanged,
  });

  @override
  State<DoubleSpinBox> createState() => _DoubleSpinBoxState();
}

class _DoubleSpinBoxState extends State<DoubleSpinBox> {
  late TextEditingController _controller;
  late double _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue.clamp(widget.min, widget.max);
    _controller = TextEditingController(text: _value.toStringAsFixed(2));
  }

  void _setValue(double newVal) {
    final clamped = newVal.clamp(widget.min, widget.max);
    setState(() {
      _value = clamped;
      _controller.text = _value.toStringAsFixed(2);
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
    });
    widget.onChanged?.call(_value);
  }

  void _increment() => _setValue(_value + widget.step);
  void _decrement() => _setValue(_value - widget.step);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(4.0),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Row(
          children: [
            IconButton(onPressed: _decrement, icon: const Icon(Icons.remove)),
            Expanded(
              child: Text(
                _value.toStringAsFixed(2),
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(onPressed: _increment, icon: const Icon(Icons.add)),
          ],
        ),
      ),
    );
  }
}
