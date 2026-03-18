import 'package:flutter/material.dart';

class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFEDF6F7),
      body: Center(
        child: Text(
          '디바이스',
          style: TextStyle(fontSize: 18, color: Color(0xFF212121)),
        ),
      ),
    );
  }
}
