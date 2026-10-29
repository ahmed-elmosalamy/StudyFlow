import 'package:flutter/material.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Today screen — arrives in a later milestone.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
