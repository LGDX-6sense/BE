import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenChatbot});
  final VoidCallback onOpenChatbot;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEDF6F7),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 19,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Text(
                  '김수현 홈',
                  style: TextStyle(
                    color: Color(0xFF212121),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'Pretendard',
                  ),
                ),
                const SizedBox(width: 8),
                Image.asset('assets/icon/k.png', width: 20, height: 20),
              ],
            ),
            Row(
              children: [
                Image.asset('assets/icon/1.png', width: 24, height: 24),
                SizedBox(width: 8),
                Image.asset('assets/icon/bell.png', width: 24, height: 24),
                SizedBox(width: 8),
                Image.asset('assets/icon/meatbell.png', width: 24, height: 24),
              ],
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // 블러 원 (좌측 상단)
          Positioned(
            left: -120,
            top: 0,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color(0xFFBFE1DE).withValues(alpha: 0.80),
                      Color(0xFFBFE1DE).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 블러 원 (우측 하단)
          Positioned(
            right: -120,
            bottom: 80,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Color(0xFFBFE1DE).withValues(alpha: 0.80),
                      Color(0xFFBFE1DE).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(19, 0, 19, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 10),
                // Section 1: Banner cards
                _buildBannerCard(
                  title: '에어컨 사전 점검 서비스로\n올 여름도 시원하게',
                  buttonLabel: '사전점검 신청하기',
                  onTap: null,
                ),
                const SizedBox(height: 12),
                _buildBannerCard(
                  title: 'Chat REBO로 우리집 가전의\n고장을 바로 해결해보세요!',
                  buttonLabel: 'Chat REBO 사용하기',
                  onTap: onOpenChatbot,
                ),
                const SizedBox(height: 24),
                // Section 2: 즐겨 찾는 제품
                _buildSectionHeader(
                  '즐겨 찾는 제품',
                  iconAsset: 'assets/icon/edit.png',
                ),
                const SizedBox(height: 12),
                _buildProductGrid(),
                const SizedBox(height: 24),
                // Section 3: 스마트 루틴
                _buildSectionHeader(
                  '스마트 루틴',
                  iconAsset: 'assets/icon/Right.png',
                ),
                const SizedBox(height: 12),
                _buildChip('루틴 알아보기'),
                const SizedBox(height: 24),
                // Section 4: ThinQ 활용하기
                _buildSectionHeader(
                  'ThinQ 활용하기',
                  iconAsset: 'assets/icon/Right.png',
                ),
                const SizedBox(height: 12),
                _buildThinQCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBannerCard({
    required String title,
    required String buttonLabel,
    VoidCallback? onTap,
  }) {
    return Container(
      height: 105,
      padding: const EdgeInsets.only(left: 19),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFD9D9D9),
              borderRadius: BorderRadius.circular(12),
            ),
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
                    fontWeight: FontWeight.w500,
                    height: 1.43,
                    fontFamily: 'Pretendard',
                  ),
                ),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: onTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD6DBFC),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      buttonLabel,
                      style: const TextStyle(
                        color: Color(0xFF4D57B9),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Pretendard',
                      ),
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

  Widget _buildSectionHeader(String title, {required String iconAsset}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: Color(0xFF212121),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            fontFamily: 'Pretendard',
          ),
        ),
        Image.asset(iconAsset, width: 24, height: 24),
      ],
    );
  }

  Widget _buildProductGrid() {
    const products = ['전기레인지', '냉장고', '에어컨', '스타일러'];
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildProductChip(products[0])),
            const SizedBox(width: 11),
            Expanded(child: _buildProductChip(products[1])),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildProductChip(products[2])),
            const SizedBox(width: 11),
            Expanded(child: _buildProductChip(products[3])),
          ],
        ),
      ],
    );
  }

  Widget _buildProductChip(String label) {
    return Container(
      height: 49,
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF212121).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(width: 20, height: 20, color: const Color(0xFFD9D9D9)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF212121),
              fontSize: 14,
              fontWeight: FontWeight.w400,
              fontFamily: 'Pretendard',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      height: 49,
      width: 163,
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF212121).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(width: 20, height: 20, color: const Color(0xFFD9D9D9)),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF212121),
              fontSize: 14,
              fontWeight: FontWeight.w400,
              fontFamily: 'Pretendard',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinQCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Column(
        children: [
          Container(
            height: 129,
            color: const Color(0xFFD9D9D9),
            width: double.infinity,
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(19, 0, 19, 0),
            height: 70,
            color: Colors.white,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '스마트 진단으로 제품 상태를 확인해요',
                  style: TextStyle(
                    color: Color(0xFF212121),
                    fontSize: 16,
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
