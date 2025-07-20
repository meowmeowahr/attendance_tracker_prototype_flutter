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
