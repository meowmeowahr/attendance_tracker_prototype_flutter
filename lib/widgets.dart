import 'package:flutter/material.dart';

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
    return CustomPaint(
      painter: _StripePainter(),
      child: Container(
        height: 24,
        alignment: Alignment.center,
        child: Container(
          color: Colors.black,
          child: Padding(
            padding: const EdgeInsets.only(left: 8.0, right: 8.0),
            child: const Text(
              'ADMIN',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontSize: 18,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StripePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const stripeWidth = 20.0;
    final paint = Paint();
    final path = Path();

    for (double x = -size.height; x < size.width; x += stripeWidth * 2) {
      path.reset();
      path.moveTo(x, 0);
      path.lineTo(x + stripeWidth, 0);
      path.lineTo(x + stripeWidth - size.height, size.height);
      path.lineTo(x - size.height, size.height);
      path.close();

      paint.color = Colors.yellow;
      canvas.drawPath(path, paint);

      path.reset();
      path.moveTo(x + stripeWidth, 0);
      path.lineTo(x + stripeWidth * 2, 0);
      path.lineTo(x + stripeWidth * 2 - size.height, size.height);
      path.lineTo(x + stripeWidth - size.height, size.height);
      path.close();

      paint.color = Colors.black;
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
