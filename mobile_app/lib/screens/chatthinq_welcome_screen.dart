import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'chatthinq_background.dart';

class ChatThinQWelcomeScreen extends StatefulWidget {
  const ChatThinQWelcomeScreen({
    super.key,
    required this.onCloseTap,
    required this.onMoreTap,
    required this.onReboTap,
    required this.onSuggestionTap,
    required this.showOnboarding,
    required this.onDismissOnboarding,
    required this.baseUrl,
  });

  final VoidCallback onCloseTap;
  final VoidCallback onMoreTap;
  final VoidCallback onReboTap;
  final ValueChanged<String> onSuggestionTap;
  final bool showOnboarding;
  final VoidCallback onDismissOnboarding;
  final String baseUrl;

  @override
  State<ChatThinQWelcomeScreen> createState() => _ChatThinQWelcomeScreenState();
}

class _ChatThinQWelcomeScreenState extends State<ChatThinQWelcomeScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _loading = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send(String text) async {
    final msg = text.trim();
    if (msg.isEmpty) return;
    _controller.clear();
    setState(() {
      _messages.add(_ChatMessage(role: 'user', text: msg));
      _loading = true;
    });
    _scrollToBottom();

    try {
      final res = await http.post(
        Uri.parse('${widget.baseUrl}/api/chatthinq/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': msg,
          'history': _messages
              .take(_messages.length - 1)
              .map((m) => {'role': m.role, 'content': m.text})
              .toList(),
        }),
      );

      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final reply = data['reply'] as String? ?? '';
        final redirect = data['redirect_to_rebo'] as bool? ?? false;
        setState(() {
          _messages.add(_ChatMessage(
            role: 'assistant',
            text: reply,
            isRedirect: redirect,
          ));
          _loading = false;
        });
      } else {
        setState(() {
          _messages.add(const _ChatMessage(role: 'assistant', text: '응답을 가져오지 못했어요.'));
          _loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(const _ChatMessage(role: 'assistant', text: '네트워크 오류가 발생했어요.'));
        _loading = false;
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasChat = _messages.isNotEmpty;

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
                  onCloseTap: widget.onCloseTap,
                  onSelectChatRebo: widget.onReboTap,
                ),
                const SizedBox(height: 16),
                if (!hasChat) ...[
                  const _IntroSection(),
                  const SizedBox(height: 28),
                  _SuggestionSection(onSuggestionTap: (s) => _send(s)),
                  const SizedBox(height: 28),
                  _ReboSection(onTap: widget.onReboTap),
                  const Spacer(),
                ] else ...[
                  Expanded(
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      itemCount: _messages.length + (_loading ? 1 : 0),
                      separatorBuilder: (context, idx) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        if (_loading && i == _messages.length) {
                          return const _TypingBubble();
                        }
                        final m = _messages[i];
                        return _MessageBubble(
                          message: m,
                          onReboTap: widget.onReboTap,
                        );
                      },
                    ),
                  ),
                ],
                _ComposerWarning(onMoreTap: widget.onMoreTap),
                const SizedBox(height: 8),
                _ChatComposer(
                  controller: _controller,
                  loading: _loading,
                  onSend: () => _send(_controller.text),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        if (widget.showOnboarding)
          const Positioned.fill(
            child: AbsorbPointer(
              child: ColoredBox(color: Color(0x59000000)),
            ),
          ),
        if (widget.showOnboarding)
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
                      onTap: widget.onDismissOnboarding,
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

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.text,
    this.isRedirect = false,
  });

  final String role;
  final String text;
  final bool isRedirect;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.onReboTap});

  final _ChatMessage message;
  final VoidCallback onReboTap;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isUser ? const Color(0xFF606C80) : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              message.text,
              style: TextStyle(
                color: isUser ? Colors.white : const Color(0xFF212121),
                fontSize: 13,
                height: 1.5,
                fontFamily: 'Pretendard',
              ),
            ),
          ),
          if (message.isRedirect) ...[
            const SizedBox(height: 8),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onReboTap,
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD6DBFC),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Chat REBO로 이동하기',
                        style: TextStyle(
                          color: Color(0xFF4D57B9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Pretendard',
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_ios_rounded, size: 11, color: Color(0xFF4D57B9)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TypingBubble extends StatefulWidget {
  const _TypingBubble();

  @override
  State<_TypingBubble> createState() => _TypingBubbleState();
}

class _TypingBubbleState extends State<_TypingBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _anim;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: AnimatedBuilder(
          animation: _anim,
          builder: (_, __) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) {
                final phase = (_anim.value - i * 0.2).clamp(0.0, 1.0);
                final opacity = math.sin(phase * math.pi).clamp(0.2, 1.0);
                return Padding(
                  padding: EdgeInsets.only(right: i < 2 ? 4.0 : 0),
                  child: Opacity(
                    opacity: opacity,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFF606C80),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.loading,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool loading;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [BoxShadow(color: Color(0x0DFD312E), blurRadius: 8)],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !loading,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              maxLines: null,
              style: const TextStyle(
                color: Color(0xFF212121),
                fontSize: 13,
                height: 1.4,
                fontFamily: 'Pretendard',
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: '메시지를 입력하세요',
                hintStyle: TextStyle(
                  color: Color(0xFF5D5B5B),
                  fontSize: 12.5,
                  fontFamily: 'Pretendard',
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 4),
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: loading ? null : onSend,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: loading ? const Color(0xFFCCCCCC) : const Color(0xFF606C80),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
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
                  text: const TextSpan(
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
                        text: '에서는\n일상 대화와 스마트홈 기능을 도와드려요',
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
                      '다음',
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
          '지영님 점심엔 쉬어가요',
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
