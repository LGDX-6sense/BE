import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

class ChatThinQBackground extends StatelessWidget {
  const ChatThinQBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        ColoredBox(color: Color(0xFFFCEDEB)),
        Positioned(
          left: -130,
          top: 36,
          child: _ChatThinQOrb(
            size: 240,
            color: Color(0xFFFCAEB2),
            opacity: 0.52,
            blurSigma: 92,
          ),
        ),
        Positioned(
          right: -126,
          bottom: 92,
          child: _ChatThinQOrb(
            size: 232,
            color: Color(0xFFFCAEB2),
            opacity: 0.48,
            blurSigma: 92,
          ),
        ),
      ],
    );
  }
}

class _ChatThinQOrb extends StatelessWidget {
  const _ChatThinQOrb({
    required this.size,
    required this.color,
    required this.opacity,
    required this.blurSigma,
  });

  final double size;
  final Color color;
  final double opacity;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: opacity),
        ),
      ),
    );
  }
}
