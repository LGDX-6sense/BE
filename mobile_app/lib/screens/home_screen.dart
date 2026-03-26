//홈화면 디자인 수정 완료
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenChatbot});

  final VoidCallback onOpenChatbot;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF6F7),
      body: Stack(
        children: [
          const Positioned.fill(child: _HomeBackground()),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 19),
                  child: _HomeTopNavigation(),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(19, 0, 19, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _BannerCard(
                          title: '에어컨 사전 점검 서비스로\n올 여름도 시원하게',
                          buttonLabel: '사전점검 신청하기',
                          imagePath: 'assets/icon/home_1.png',
                        ),
                        const SizedBox(height: 12),
                        _BannerCard(
                          title: 'Chat REBO로 우리집 가전의\n고장을 바로 해결해보세요!',
                          buttonLabel: 'Chat REBO 사용하기',
                          imagePath: 'assets/icon/home_2.png',
                          onPressed: onOpenChatbot,
                        ),
                        const SizedBox(height: 24),
                        const _SectionHeader(
                          title: '즐겨 찾는 제품',
                          trailingAssetPath: 'assets/icon/edit.png',
                        ),
                        const SizedBox(height: 12),
                        const _FavoriteProductsSection(),
                        const SizedBox(height: 24),
                        const _SectionHeader(
                          title: '스마트 루틴',
                          trailingAssetPath: 'assets/icon/Right.png',
                        ),
                        const SizedBox(height: 12),
                        const _RoutineSection(),
                        const SizedBox(height: 24),
                        const _SectionHeader(
                          title: 'ThinQ 활용하기',
                          trailingAssetPath: 'assets/icon/Right.png',
                        ),
                        const SizedBox(height: 12),
                        const _ThinQInsightCard(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeBackground extends StatelessWidget {
  const _HomeBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ColoredBox(color: Color(0xFFEDF6F7)),
        const Positioned(
          left: -155,
          top: -110,
          child: _BlurredOrb(
            size: 310,
            color: Color(0xFFBFE1DE),
            opacity: 0.42,
            blurSigma: 138,
          ),
        ),
        const Positioned(
          right: -155,
          bottom: -110,
          child: _BlurredOrb(
            size: 310,
            color: Color(0xFFBFE1DE),
            opacity: 0.42,
            blurSigma: 138,
          ),
        ),
      ],
    );
  }
}

class _BlurredOrb extends StatelessWidget {
  const _BlurredOrb({
    required this.size,
    required this.color,
    required this.opacity,
    this.blurSigma = 60,
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

class _HomeTopNavigation extends StatelessWidget {
  const _HomeTopNavigation();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '식스센스 홈',
                style: TextStyle(
                  color: Color(0xFF212121),
                  fontSize: 18,
                  height: 1.11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Pretendard',
                ),
              ),
              const SizedBox(width: 8),
              Image.asset(
                'assets/icon/down.png',
                width: 20,
                height: 20,
                filterQuality: FilterQuality.medium,
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              _TopIcon(assetPath: 'assets/icon/home_plus.png'),
              SizedBox(width: 8),
              _TopIcon(assetPath: 'assets/icon/home_bell.png'),
              SizedBox(width: 8),
              _TopIcon(assetPath: 'assets/icon/home_meatballs.png'),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Center(
        child: Image.asset(
          assetPath,
          width: 24,
          height: 24,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({
    required this.title,
    required this.buttonLabel,
    required this.imagePath,
    this.onPressed,
  });

  final String title;
  final String buttonLabel;
  final String imagePath;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 105,
      padding: const EdgeInsets.only(left: 19, right: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9DB7B5).withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Image.asset(
            imagePath,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF212121),
                    fontSize: 14,
                    height: 1.43,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Pretendard',
                  ),
                ),
                const SizedBox(height: 6),
                _ActionChip(label: buttonLabel, onPressed: onPressed),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFD6DBFC),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF4D57B9),
          fontSize: 12,
          height: 1.16,
          fontWeight: FontWeight.w500,
          fontFamily: 'Pretendard',
        ),
      ),
    );

    if (onPressed == null) {
      return chip;
    }

    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(100),
      child: chip,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.trailingAssetPath});

  final String title;
  final String trailingAssetPath;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF212121),
            fontSize: 16,
            height: 1.37,
            fontWeight: FontWeight.w600,
            fontFamily: 'Pretendard',
          ),
        ),
        Image.asset(
          trailingAssetPath,
          width: 24,
          height: 24,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ],
    );
  }
}

class _FavoriteProductsSection extends StatelessWidget {
  const _FavoriteProductsSection();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 11) / 2;

        return Column(
          children: [
            Row(
              children: [
                SizedBox(
                  width: cardWidth,
                  child: const _ProductShortcutCard(
                    label: '세탁기',
                    imagePath: 'assets/icon/home_washing.png',
                  ),
                ),
                const SizedBox(width: 11),
                SizedBox(
                  width: cardWidth,
                  child: const _ProductShortcutCard(
                    label: '냉장고',
                    imagePath: 'assets/icon/home_refrigerator.png',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: cardWidth,
                child: const _ProductShortcutCard(
                  label: '에어컨',
                  imagePath: 'assets/icon/home_air.png',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ProductShortcutCard extends StatelessWidget {
  const _ProductShortcutCard({required this.label, required this.imagePath});

  final String label;
  final String imagePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 49,
      padding: const EdgeInsets.only(left: 12, right: 12),
      decoration: BoxDecoration(
        color: const Color(0x0D212121),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            height: 30,
            child: Image.asset(
              imagePath,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF212121),
              fontSize: 14,
              height: 1.14,
              fontWeight: FontWeight.w400,
              fontFamily: 'Pretendard',
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutineSection extends StatelessWidget {
  const _RoutineSection();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = (constraints.maxWidth - 11) / 2;

        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: cardWidth,
            height: 49,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Image.asset(
                  'assets/icon/time.png',
                  width: 20,
                  height: 20,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
                const SizedBox(width: 8),
                const Text(
                  '루틴 알아보기',
                  style: TextStyle(
                    color: Color(0xFF212121),
                    fontSize: 14,
                    height: 1.14,
                    fontWeight: FontWeight.w400,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ThinQInsightCard extends StatelessWidget {
  const _ThinQInsightCard();

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 129,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFF9F5E9), Color(0xFFF3EDD9)],
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 22,
                  child: Container(
                    width: 180,
                    height: 82,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8EA),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
                Image.asset(
                  'assets/icon/home_thinq.png',
                  width: 161,
                  height: 125,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ],
            ),
          ),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(19, 14, 19, 14),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '챗봇으로 제품의 고장 원인을 파악해 보세요',
                  style: TextStyle(
                    color: Color(0xFF212121),
                    fontSize: 15,
                    height: 1.12,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Pretendard',
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '문제가 발생하면 원인부터 해결까지 안내받을 수 있어요',
                  style: TextStyle(
                    color: Color(0xFF606C80),
                    fontSize: 12,
                    height: 1.16,
                    fontWeight: FontWeight.w400,
                    fontFamily: 'Pretendard',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
