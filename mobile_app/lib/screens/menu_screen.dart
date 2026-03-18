import 'package:flutter/material.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFEDF6F7),
      body: Center(
        child: Text(
          '메뉴',
          style: TextStyle(fontSize: 18, color: Color(0xFF212121)),
        ),
      ),
    );
  }
}
