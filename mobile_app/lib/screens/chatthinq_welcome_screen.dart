import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'chatthinq_background.dart';

class ChatThinQWelcomeScreen extends StatelessWidget {
  const ChatThinQWelcomeScreen({
    super.key,
    required this.onCloseTap,
    required this.onMoreTap,
    required this.onComposerTap,
    required this.onReboTap,
    required this.onSuggestionTap,
    required this.showOnboarding,
    required this.onDismissOnboarding,
  });

  final VoidCallback onCloseTap;
  final VoidCallback onMoreTap;
  final VoidCallback onComposerTap;
  final VoidCallback onReboTap;
  final ValueChanged<String> onSuggestionTap;
  final bool showOnboarding;
  final VoidCallback onDismissOnboarding;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ChatThinQBackground()),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 19),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                _ChatThinQTopNavigation(
                  onCloseTap: onCloseTap,
                  onSelectChatRebo: onReboTap,
                ),
                const SizedBox(height: 28),
                const _IntroSection(),
                const SizedBox(height: 36),
                _SuggestionSection(onSuggestionTap: onSuggestionTap),
                const SizedBox(height: 36),
                _ReboSection(onTap: onReboTap),
                const Spacer(),
                _ComposerWarning(onMoreTap: onMoreTap),
                const SizedBox(height: 12),
                _WelcomeComposer(onTap: onComposerTap),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        if (showOnboarding)
          const Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(color: Color(0x59000000)),
            ),
          ),
        if (showOnboarding)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 19),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 58,
                    child: _WelcomeOnboardingCard(
                      onTap: onDismissOnboarding,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _WelcomeOnboardingCard extends StatelessWidget {
  const _WelcomeOnboardingCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 24,
          top: -5,
          child: Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ),
        ),
        Container(
          width: 332,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 18,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(
                      color: Color(0xFF212121),
                      fontSize: 13,
                      height: 1.45,
                      fontFamily: 'Pretendard',
                    ),
                    children: [
                      TextSpan(
                        text: 'ChatThinQ',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text: '\uc5d0\uc11c\ub294\n\uc77c\uc0c1 \ub300\ud654\uc640 \uc2a4\ub9c8\ud2b8\ud648 \uae30\ub2a5\uc744 \ub3c4\uc640\ub4dc\ub824\uc694',
                        style: TextStyle(fontWeight: FontWeight.w400),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF606C80),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '\ub2e4\uc74c',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.15,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Pretendard',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatThinQTopNavigation extends StatelessWidget {
  const _ChatThinQTopNavigation({
    required this.onCloseTap,
    required this.onSelectChatRebo,
  });

  final VoidCallback onCloseTap;
  final VoidCallback onSelectChatRebo;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          PopupMenuButton<String>(
            tooltip: '',
            padding: EdgeInsets.zero,
            offset: const Offset(0, 34),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            color: Colors.white,
            elevation: 10,
            onSelected: (_) => onSelectChatRebo(),
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'rebo',
                child: Text(
                  'Chat REBO',
                  style: TextStyle(
                    color: Color(0xFF212121),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'ChatThinQ',
                  style: TextStyle(
                    color: Color(0xFF212121),
                    fontSize: 20,
                    height: 1.1,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Pretendard',
                  ),
                ),
                const SizedBox(width: 6),
                Image.asset(
                  'assets/icon/down.png',
                  width: 18,
                  height: 18,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onCloseTap,
            borderRadius: BorderRadius.circular(999),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Image.asset(
                'assets/icon/close.png',
                width: 18,
                height: 18,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IntroSection extends StatelessWidget {
  const _IntroSection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '식스센스님 점심엔 쉬어가요',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 16,
            height: 1.38,
            fontWeight: FontWeight.w600,
            fontFamily: 'Pretendard',
          ),
        ),
        SizedBox(height: 10),
        Text(
          '생성형 AI를 활용한 스마트홈 어시스턴트로\n더 넓고 자유로운 일상의 대화를 경험해보세요!',
          style: TextStyle(
            color: Color(0xFF5D5B5B),
            fontSize: 12,
            height: 1.5,
            fontWeight: FontWeight.w400,
            fontFamily: 'Pretendard',
          ),
        ),
      ],
    );
  }
}

class _SuggestionSection extends StatelessWidget {
  const _SuggestionSection({required this.onSuggestionTap});

  final ValueChanged<String> onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    const suggestions = ['스마트 루틴 사용법 알려줘', '오늘 날씨는 어때?', '우리집 에너지 효율은 어느 정도야?'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '다음 주제의 대화는 어때요?',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 16,
            height: 1.38,
            fontWeight: FontWeight.w600,
            fontFamily: 'Pretendard',
          ),
        ),
        const SizedBox(height: 10),
        for (final suggestion in suggestions) ...[
          _SuggestionChip(
            label: suggestion,
            onTap: () => onSuggestionTap(suggestion),
          ),
          if (suggestion != suggestions.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFFFF937E), Color(0xFFFF5555)],
        ),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.all(1.2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              padding: const EdgeInsets.fromLTRB(9, 5, 12, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/icon/AI.png',
                    width: 13,
                    height: 13,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFEB4C4C),
                        fontSize: 11,
                        height: 1.5,
                        fontWeight: FontWeight.w400,
                        fontFamily: 'Pretendard',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReboSection extends StatelessWidget {
  const _ReboSection({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '고장이나 A/S가 필요하신가요?',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 16,
            height: 1.38,
            fontWeight: FontWeight.w600,
            fontFamily: 'Pretendard',
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '사진/음성으로 진단하고\n예약까지 한 번에 해결하세요',
          style: TextStyle(
            color: Color(0xFF5D5B5B),
            fontSize: 12,
            height: 1.5,
            fontWeight: FontWeight.w400,
            fontFamily: 'Pretendard',
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFD6DBFC),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Chat REBO 시작하기',
                    style: TextStyle(
                      color: Color(0xFF4D57B9),
                      fontSize: 12,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Pretendard',
                    ),
                  ),
                  const SizedBox(width: 4),
                  Image.asset(
                    'assets/icon/Right.png',
                    width: 12,
                    height: 12,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ComposerWarning extends StatelessWidget {
  const _ComposerWarning({required this.onMoreTap});

  final VoidCallback onMoreTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'AI가 생성한 응답은 부정확할 수 있습니다.',
            style: TextStyle(
              color: Color(0xFF5D5B5B),
              fontSize: 10,
              height: 1.2,
              fontWeight: FontWeight.w400,
              fontFamily: 'Pretendard',
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onMoreTap,
            child: const Text(
              '더보기',
              style: TextStyle(
                color: Color(0xFF5D5B5B),
                fontSize: 10,
                height: 1.2,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.underline,
                fontFamily: 'Pretendard',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WelcomeComposer extends StatelessWidget {
  const _WelcomeComposer({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(color: Color(0x0DFD312E), blurRadius: 8),
            ],
          ),
          child: Row(
            children: [
              Image.asset(
                'assets/icon/home_plus.png',
                width: 22,
                height: 22,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.medium,
              ),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  '메시지를 입력하세요',
                  style: TextStyle(
                    color: Color(0xFF5D5B5B),
                    fontSize: 12.5,
                    height: 1.15,
                    fontWeight: FontWeight.w400,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ),
              _PressableTintAssetIcon(
                assetPath: 'assets/icon/mic.png',
                size: 22,
                onTap: onTap,
              ),
              const SizedBox(width: 7),
              _PressableTintAssetIcon(
                assetPath: 'assets/icon/send.png',
                size: 22,
                onTap: onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PressableTintAssetIcon extends StatefulWidget {
  const _PressableTintAssetIcon({
    required this.assetPath,
    required this.size,
    required this.onTap,
  });

  final String assetPath;
  final double size;
  final VoidCallback onTap;

  @override
  State<_PressableTintAssetIcon> createState() =>
      _PressableTintAssetIconState();
}

class _PressableTintAssetIconState extends State<_PressableTintAssetIcon> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: Image.asset(
          widget.assetPath,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          color: _pressed ? const Color(0xFF212121) : const Color(0xFF606C80),
          colorBlendMode: BlendMode.srcIn,
        ),
      ),
    );
  }
}
