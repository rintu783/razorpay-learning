import 'package:flutter/material.dart';

/// Round avatar showing initials. [radius] makes it small (app bar) or large (account page).
class Avatar extends StatelessWidget {
  final String initials;
  final double radius;
  const Avatar({super.key, required this.initials, this.radius = 18});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primaryContainer,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.w600,
          color: scheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
