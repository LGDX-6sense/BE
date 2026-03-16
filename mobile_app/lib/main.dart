import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

const _defaultBaseUrlOverride = String.fromEnvironment('DEFAULT_BASE_URL');

void main() => runApp(const LgMobileApp());

class LgMobileApp extends StatelessWidget {
  const LgMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF0E7C6B);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'LG 가전 진단 챗봇',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF6F1E8),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: const BorderSide(color: seed, width: 1.2),
          ),
        ),
      ),
      home: const MobileHomePage(),
    );
  }
}

class MobileHomePage extends StatefulWidget {
  const MobileHomePage({super.key});

  @override
  State<MobileHomePage> createState() => _MobileHomePageState();
}

class _MobileHomePageState extends State<MobileHomePage> {
  static const Set<String> _supportedAudioExtensions = {
    'wav',
    'wave',
    'mp3',
    'm4a',
    'aac',
    'flac',
  };

  final _messageController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();
  final _voiceRecorder = AudioRecorder();
  final _tts = FlutterTts();

  List<ChatTurn> _history = const [];
  File? _selectedImage;
  File? _selectedAudio;
  File? _recordedVoice;
  String? _selectedImageName;
  String? _selectedAudioName;
  String? _recordedVoiceName;
  String? _latestEvidence;
  String? _errorMessage;
  bool _isSubmitting = false;
  bool _isCheckingConnection = false;
  bool _serverHealthy = false;
  bool _isRecordingVoice = false;
  bool _isSpeaking = false;
  bool _autoSpeak = true;
  String _serverStatus = '확인 중';

  @override
  void initState() {
    super.initState();
    _baseUrlController.text =
        _defaultBaseUrlOverride.isNotEmpty
            ? _defaultBaseUrlOverride
            : (Platform.isAndroid
                  ? 'http://10.0.2.2:8000'
                  : 'http://127.0.0.1:8000');
    unawaited(_configureTts());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkConnection());
  }

  @override
  void dispose() {
    _messageController.dispose();
    _baseUrlController.dispose();
    _scrollController.dispose();
    unawaited(_voiceRecorder.dispose());
    unawaited(_tts.stop());
    super.dispose();
  }

  String get _baseUrl {
    final value = _baseUrlController.text.trim();
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  Future<void> _configureTts() async {
    void markSpeaking(bool speaking) {
      if (!mounted) return;
      setState(() => _isSpeaking = speaking);
    }

    _tts.setStartHandler(() => markSpeaking(true));
    _tts.setCompletionHandler(() => markSpeaking(false));
    _tts.setCancelHandler(() => markSpeaking(false));
    _tts.setErrorHandler((_) => markSpeaking(false));

    try {
      await _tts.awaitSpeakCompletion(true);
      await _tts.setLanguage('ko-KR');
      await _tts.setSpeechRate(0.42);
      await _tts.setPitch(1.0);
      await _tts.setVolume(1.0);
      if (Platform.isIOS) {
        await _tts.setSharedInstance(true);
        await _tts.autoStopSharedSession(true);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'TTS를 초기화하지 못했습니다: $error';
      });
    }
  }

  Future<void> _stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isSpeaking = false);
  }

  Future<void> _speakText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    try {
      await _stopSpeaking();
      await _tts.speak(trimmed);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '음성 읽기에 실패했습니다: $error';
      });
    }
  }

  Future<void> _checkConnection() async {
    if (_isCheckingConnection) return;
    setState(() {
      _isCheckingConnection = true;
      _serverStatus = '확인 중';
      _errorMessage = null;
    });
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      setState(() {
        _serverHealthy =
            response.statusCode >= 200 && response.statusCode < 300;
        _serverStatus = _serverHealthy ? '연결됨' : 'HTTP ${response.statusCode}';
        if (!_serverHealthy) {
          _errorMessage = '백엔드 상태 확인에 실패했습니다.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _serverHealthy = false;
        _serverStatus = '오프라인';
        _errorMessage = '백엔드에 연결할 수 없습니다: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _isCheckingConnection = false);
      }
    }
  }

  Future<void> _pickImage() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 1600,
    );
    if (!mounted || file == null) return;
    setState(() {
      _selectedImage = File(file.path);
      _selectedImageName = file.name;
    });
  }

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.audio,
    );
    if (!mounted || result == null || result.files.isEmpty) return;

    final picked = result.files.single;
    if (picked.path == null) {
      setState(() {
        _errorMessage = '선택한 오디오 파일을 읽을 수 없습니다.';
      });
      return;
    }

    final extension = picked.extension?.toLowerCase() ?? '';
    if (!_supportedAudioExtensions.contains(extension)) {
      setState(() {
        _errorMessage = '지원하는 오디오 형식만 선택해 주세요: wav, mp3, m4a, aac, flac';
      });
      return;
    }

    setState(() {
      _selectedAudio = File(picked.path!);
      _selectedAudioName = picked.name;
    });
  }

  Future<void> _toggleVoiceRecording() async {
    if (_isRecordingVoice) {
      await _stopVoiceRecording();
      return;
    }
    await _startVoiceRecording();
  }

  Future<void> _startVoiceRecording() async {
    if (_isSubmitting) return;

    try {
      await _stopSpeaking();
      final hasPermission = await _voiceRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        setState(() {
          _errorMessage = '마이크 권한이 필요합니다.';
        });
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath =
          '${tempDir.path}${Platform.pathSeparator}voice_message_$timestamp.m4a';

      await _voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: outputPath,
      );

      if (!mounted) return;
      setState(() {
        _isRecordingVoice = true;
        _recordedVoice = null;
        _recordedVoiceName = null;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isRecordingVoice = false;
        _errorMessage = '음성 녹음을 시작하지 못했습니다: $error';
      });
    }
  }

  Future<void> _stopVoiceRecording() async {
    try {
      final savedPath = await _voiceRecorder.stop();
      if (!mounted) return;

      setState(() {
        _isRecordingVoice = false;
        if (savedPath == null || savedPath.isEmpty) {
          _errorMessage = '녹음된 음성을 저장하지 못했습니다.';
          return;
        }

        _recordedVoice = File(savedPath);
        _recordedVoiceName = _basename(savedPath);
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isRecordingVoice = false;
        _errorMessage = '음성 녹음을 종료하지 못했습니다: $error';
      });
    }
  }

  String _basename(String path) => path.split(RegExp(r'[\\\\/]')).last;

  Future<void> _sendMessage() async {
    if (_isSubmitting) return;

    if (_isRecordingVoice) {
      await _stopVoiceRecording();
    }

    final message = _messageController.text.trim();
    if (message.isEmpty &&
        _selectedImage == null &&
        _selectedAudio == null &&
        _recordedVoice == null) {
      setState(() {
        _errorMessage = '메시지, 이미지, 오디오, 음성 중 하나 이상을 추가해 주세요.';
      });
      return;
    }

    await _stopSpeaking();
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final request =
          http.MultipartRequest('POST', Uri.parse('$_baseUrl/api/chat'))
            ..fields['message'] = message
            ..fields['history_json'] = jsonEncode(
              _history.map((turn) => turn.toJson()).toList(),
            );

      if (_selectedImage != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'image',
            _selectedImage!.path,
            filename: _selectedImageName,
          ),
        );
      }

      if (_selectedAudio != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'audio',
            _selectedAudio!.path,
            filename: _selectedAudioName,
          ),
        );
      }

      if (_recordedVoice != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'voice_audio',
            _recordedVoice!.path,
            filename: _recordedVoiceName,
          ),
        );
      }

      final streamed = await request.send().timeout(
        const Duration(seconds: 90),
      );
      final body = await streamed.stream.bytesToString();
      final decoded = body.isEmpty ? <String, dynamic>{} : jsonDecode(body);
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw HttpException(
          decoded is Map<String, dynamic>
              ? decoded['detail']?.toString() ?? body
              : body,
        );
      }
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('백엔드 응답 형식이 올바르지 않습니다.');
      }

      final nextHistory = <ChatTurn>[];
      final rawHistory = decoded['history'];
      if (rawHistory is List) {
        for (final item in rawHistory) {
          if (item is Map) {
            nextHistory.add(ChatTurn.fromJson(item));
          }
        }
      }

      final assistantMessage =
          decoded['assistant_message']?.toString().trim() ??
          (nextHistory.isNotEmpty ? nextHistory.last.assistant : '');
      final shouldSpeak = _autoSpeak && assistantMessage.isNotEmpty;

      if (!mounted) return;
      setState(() {
        _history = nextHistory;
        _latestEvidence = const JsonEncoder.withIndent(
          '  ',
        ).convert(decoded['evidence']);
        _selectedImage = null;
        _selectedAudio = null;
        _recordedVoice = null;
        _selectedImageName = null;
        _selectedAudioName = null;
        _recordedVoiceName = null;
        _messageController.clear();
        _serverHealthy = true;
        _serverStatus = '연결됨';
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
        }
      });

      if (shouldSpeak) {
        unawaited(_speakText(assistantMessage));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _serverHealthy = false;
        _serverStatus = '요청 실패';
        _errorMessage = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _resetConversation() async {
    if (_isRecordingVoice) {
      await _stopVoiceRecording();
    }
    await _stopSpeaking();
    if (!mounted) return;
    setState(() {
      _history = const [];
      _selectedImage = null;
      _selectedAudio = null;
      _recordedVoice = null;
      _selectedImageName = null;
      _selectedAudioName = null;
      _recordedVoiceName = null;
      _latestEvidence = null;
      _errorMessage = null;
      _messageController.clear();
    });
  }

  Future<void> _showSheet(String title, Widget child) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 32,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF12262B),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openSettings() {
    return _showSheet(
      '연결 설정',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '안드로이드 에뮬레이터는 보통 10.0.2.2, iOS 시뮬레이터는 보통 127.0.0.1을 사용합니다.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _baseUrlController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              fillColor: Colors.white.withValues(alpha: 0.08),
              hintText: 'http://10.0.2.2:8000',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: _isCheckingConnection ? null : _checkConnection,
            icon: _isCheckingConnection
                ? const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find_rounded),
            label: const Text('백엔드 확인'),
          ),
        ],
      ),
    );
  }

  Future<void> _openEvidence() {
    return _showSheet(
      '분석 근거',
      Flexible(
        child: SingleChildScrollView(
          child: SelectableText(
            _latestEvidence ?? '아직 근거 정보가 없습니다.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.82),
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(String message, {required bool isUser}) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isUser ? '나' : '챗봇',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.black.withValues(alpha: 0.46),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!isUser) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _speakText(message),
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.volume_up_rounded,
                          size: 18,
                          color: Colors.black.withValues(alpha: 0.46),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isUser
                    ? const Color(0xFF163D44)
                    : Colors.white.withValues(alpha: 0.92),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(24),
                  topRight: const Radius.circular(24),
                  bottomLeft: Radius.circular(isUser ? 24 : 8),
                  bottomRight: Radius.circular(isUser ? 8 : 24),
                ),
              ),
              child: Text(
                message,
                style: TextStyle(
                  color: isUser ? Colors.white : const Color(0xFF1E2B2F),
                  fontSize: 15,
                  height: 1.52,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildComposerChips() {
    final chips = <Widget>[
      FilterChip(
        selected: _autoSpeak,
        label: const Text('답변 읽기'),
        avatar: Icon(
          _autoSpeak ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          size: 18,
        ),
        onSelected: (value) {
          setState(() => _autoSpeak = value);
          if (!value) {
            unawaited(_stopSpeaking());
          }
        },
      ),
      ActionChip(
        avatar: Icon(
          _isRecordingVoice
              ? Icons.stop_circle_outlined
              : Icons.mic_none_rounded,
          size: 18,
          color: _isRecordingVoice ? const Color(0xFFB63C2F) : null,
        ),
        label: Text(_isRecordingVoice ? '녹음 종료' : '마이크로 말하기'),
        backgroundColor: _isRecordingVoice ? const Color(0xFFFFF0EC) : null,
        onPressed: _isSubmitting ? null : _toggleVoiceRecording,
      ),
    ];

    if (_isSpeaking) {
      chips.add(
        ActionChip(
          avatar: const Icon(Icons.stop_circle_outlined, size: 18),
          label: const Text('읽기 중지'),
          onPressed: _stopSpeaking,
        ),
      );
    }

    if (_selectedImage != null) {
      chips.add(
        Chip(
          avatar: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              _selectedImage!,
              width: 24,
              height: 24,
              fit: BoxFit.cover,
            ),
          ),
          label: Text(_selectedImageName ?? '이미지'),
          onDeleted: () {
            setState(() {
              _selectedImage = null;
              _selectedImageName = null;
            });
          },
        ),
      );
    }

    if (_selectedAudioName != null) {
      chips.add(
        Chip(
          avatar: const Icon(Icons.graphic_eq_rounded, size: 18),
          label: Text(_selectedAudioName!),
          onDeleted: () {
            setState(() {
              _selectedAudio = null;
              _selectedAudioName = null;
            });
          },
        ),
      );
    }

    if (_recordedVoiceName != null) {
      chips.add(
        Chip(
          avatar: const Icon(Icons.mic_rounded, size: 18),
          label: Text(_recordedVoiceName!),
          onDeleted: () {
            setState(() {
              _recordedVoice = null;
              _recordedVoiceName = null;
            });
          },
        ),
      );
    }

    if (_isRecordingVoice) {
      chips.add(
        Chip(
          avatar: const Icon(
            Icons.fiber_manual_record_rounded,
            color: Colors.red,
          ),
          label: const Text('음성 녹음 중'),
          backgroundColor: const Color(0xFFFFF0EC),
        ),
      );
    }

    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = [
      '냉장고에서 몇 초마다 덜컹거리는 소리가 나요.',
      '세탁기가 탈수할 때 심하게 흔들리고 오류 코드가 보여요.',
      '에어컨 바람이 약하고 딸깍거리는 소리가 나요.',
    ];

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF4EADB), Color(0xFFE8F1EC), Color(0xFFF6F1E8)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0D7C69), Color(0xFF12454C)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Icon(
                        Icons.auto_awesome_rounded,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'LG 가전 진단 챗봇',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            _isCheckingConnection
                                ? '백엔드 확인 중...'
                                : _serverStatus,
                            style: TextStyle(
                              color: Colors.black.withValues(alpha: 0.62),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _openSettings,
                      icon: const Icon(Icons.tune_rounded),
                    ),
                    IconButton(
                      onPressed: _latestEvidence == null ? null : _openEvidence,
                      icon: const Icon(Icons.data_object_rounded),
                    ),
                    IconButton(
                      onPressed: _resetConversation,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
              ),
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3EE),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFF2C9BD)),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFF8B3928),
                        fontWeight: FontWeight.w700,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: _history.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.62),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFDEF4EC),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  '모바일 챗봇 화면',
                                  style: TextStyle(
                                    color: Color(0xFF0F7464),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                '어떤 증상을 진단해볼까요?',
                                style: TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  height: 1.05,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '텍스트를 적거나 마이크로 말해 주세요. 필요하면 사진, 소음 파일도 함께 보낼 수 있고 답변은 TTS로 읽어줍니다.',
                                style: TextStyle(
                                  color: Colors.black.withValues(alpha: 0.65),
                                  fontSize: 15,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 22),
                              Expanded(
                                child: ListView.separated(
                                  itemCount: suggestions.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, index) => InkWell(
                                    onTap: () => _messageController.text =
                                        suggestions[index],
                                    borderRadius: BorderRadius.circular(22),
                                    child: Ink(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8FAF7),
                                        borderRadius: BorderRadius.circular(22),
                                      ),
                                      padding: const EdgeInsets.all(16),
                                      child: Text(
                                        suggestions[index],
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          height: 1.45,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                        children: [
                          for (final turn in _history) ...[
                            _buildBubble(turn.user, isUser: true),
                            const SizedBox(height: 10),
                            _buildBubble(turn.assistant, isUser: false),
                            const SizedBox(height: 16),
                          ],
                          if (_isSubmitting)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox.square(
                                      dimension: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Text(
                                      '응답 생성 중...',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F4EC),
                  border: Border(
                    top: BorderSide(
                      color: Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: _buildComposerChips(),
                        ),
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: '사진 첨부',
                            onPressed: _isSubmitting ? null : _pickImage,
                            icon: const Icon(Icons.photo_library_outlined),
                          ),
                          IconButton(
                            tooltip: '소음 파일 첨부',
                            onPressed: _isSubmitting ? null : _pickAudio,
                            icon: const Icon(Icons.audio_file_outlined),
                          ),
                          Container(
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: _isRecordingVoice
                                  ? const Color(0xFFFFE6DF)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: IconButton(
                              tooltip: _isRecordingVoice ? '녹음 종료' : '마이크로 말하기',
                              onPressed: _isSubmitting
                                  ? null
                                  : _toggleVoiceRecording,
                              icon: Icon(
                                _isRecordingVoice
                                    ? Icons.stop_circle_outlined
                                    : Icons.mic_none_rounded,
                                color: _isRecordingVoice
                                    ? const Color(0xFFB63C2F)
                                    : null,
                              ),
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              minLines: 1,
                              maxLines: 5,
                              decoration: const InputDecoration(
                                hintText: '문제를 채팅처럼 입력하거나 마이크로 말해 주세요...',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF0D7C69), Color(0xFF163D44)],
                              ),
                              borderRadius: BorderRadius.circular(22),
                            ),
                            child: IconButton(
                              onPressed: _isSubmitting ? null : _sendMessage,
                              icon: _isSubmitting
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.arrow_upward_rounded,
                                      color: Colors.white,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatTurn {
  const ChatTurn({required this.user, required this.assistant});

  final String user;
  final String assistant;

  factory ChatTurn.fromJson(Map<dynamic, dynamic> json) {
    return ChatTurn(
      user: json['user']?.toString() ?? '',
      assistant: json['assistant']?.toString() ?? '',
    );
  }

  Map<String, String> toJson() => {'user': user, 'assistant': assistant};
}
