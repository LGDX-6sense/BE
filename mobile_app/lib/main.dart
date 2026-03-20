// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'screens/home_screen.dart';
import 'screens/device_screen.dart';
import 'screens/care_screen.dart';
import 'screens/menu_screen.dart';

const _defaultBaseUrlOverride = String.fromEnvironment('DEFAULT_BASE_URL');

void main() => runApp(const LgMobileApp());

enum AssistantMode { idle, audio, photo, replying, maincharacter }

enum ServiceRoutingStep { none, askDiagnosis, chooseService }

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      HomeScreen(onOpenChatbot: () => setState(() => _currentIndex = 2)),
      const DeviceScreen(),
      const MobileHomePage(hideBottomNav: true),
      const CareScreen(),
      const MenuScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: screens),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    const activeColor = Color(0xFF212121);
    final inactiveColor = const Color(0xFF212121).withValues(alpha: 0.30);

    final items =
        <
          ({
            IconData? fallbackIcon,
            String? fallbackAssetPath,
            String activeAssetPath,
            String inactiveAssetPath,
            String label,
          })
        >[
          (
            fallbackIcon: Icons.home_filled,
            fallbackAssetPath: null,
            activeAssetPath: 'assets/icon/home.png',
            inactiveAssetPath: 'assets/icon/home_un.png',
            label: '홈',
          ),
          (
            fallbackIcon: null,
            fallbackAssetPath: 'assets/icon/Widget_add.png',
            activeAssetPath: 'assets/icon/device.png',
            inactiveAssetPath: 'assets/icon/device_un.png',
            label: '디바이스',
          ),
          (
            fallbackIcon: null,
            fallbackAssetPath: 'assets/icon/AI.png',
            activeAssetPath: 'assets/icon/ai_.png',
            inactiveAssetPath: 'assets/icon/ai_un.png',
            label: '챗봇',
          ),
          (
            fallbackIcon: null,
            fallbackAssetPath: 'assets/icon/Line_up.png',
            activeAssetPath: 'assets/icon/care.png',
            inactiveAssetPath: 'assets/icon/care_un.png',
            label: '케어',
          ),
          (
            fallbackIcon: null,
            fallbackAssetPath: 'assets/icon/Chart.png',
            activeAssetPath: 'assets/icon/menu.png',
            inactiveAssetPath: 'assets/icon/menu_un.png',
            label: '메뉴',
          ),
        ];

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _currentIndex = i),
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _BottomNavAssetIcon(
                          active: _currentIndex == i,
                          activeAssetPath: items[i].activeAssetPath,
                          inactiveAssetPath: items[i].inactiveAssetPath,
                          fallbackAssetPath: items[i].fallbackAssetPath,
                          fallbackIcon: items[i].fallbackIcon,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          items[i].label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: _currentIndex == i
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: _currentIndex == i
                                ? activeColor
                                : inactiveColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class LgMobileApp extends StatelessWidget {
  const LgMobileApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFE9524A);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'ChatThinQ',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        scaffoldBackgroundColor: const Color(0xFFF7F3EE),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          titleLarge: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          titleMedium: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          bodyLarge: TextStyle(fontSize: 13, height: 1.45),
          bodyMedium: TextStyle(fontSize: 12, height: 1.45),
          bodySmall: TextStyle(fontSize: 10, height: 1.4),
          labelLarge: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          labelMedium: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          hintStyle: TextStyle(
            fontSize: 12,
            color: Colors.black.withValues(alpha: 0.34),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
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
            borderSide: const BorderSide(color: Color(0xFFE9524A), width: 1),
          ),
        ),
      ),
      home: const MainShell(),
    );
  }
}

class MobileHomePage extends StatefulWidget {
  const MobileHomePage({
    super.key,
    this.startInChatMode = false,
    this.hideBottomNav = false,
  });

  final bool startInChatMode;
  final bool hideBottomNav;

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
  static const List<String> _serviceActionKeywords = [
    '상담',
    '상담사',
    '고객센터',
    '전화',
    '통화',
    '콜센터',
    '출장',
    '방문',
    '기사',
    '예약',
    '접수',
    '상담 예약',
    '접수',
    '서비스',
    '서비스센터',
    '서비스 센터',
    '상담 예약',
    '서비스 예약',
    ' 상담 접수',
    '예약',
    '예약하기',
    '예약 해줘',
    '예약해줘',
    '예약 부탁',
    '예약 부탁해',
    '서비스 예약',
  ];

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
  File? _recordedNoise;
  String? _selectedImageName;
  String? _selectedAudioName;
  String? _recordedVoiceName;
  String? _recordedNoiseName;
  String? _latestEvidence;
  String? _errorMessage;
  int? _chatSessionId;
  bool _isSubmitting = false;
  bool _isCheckingConnection = false;
  bool _serverHealthy = false;
  bool _isRecordingVoice = false;
  bool _isRecordingNoise = false;
  bool _isMicButtonPressed = false;
  bool _cancelSubmissionRequested = false;
  bool _autoSpeak = true;
  bool _showWelcomeScreen = true;
  bool _showArchiveScreen = false;
  bool _archiveOpenedFromChat = false;
  bool _isLoadingArchive = false;
  int _selectedBottomNavIndex = 0;
  final int _dbUserId = 1;
  final String _dbUserName = '지영';
  String _serverStatus = '확인 중';
  String? _archiveErrorMessage;
  List<ArchiveSessionSummary> _archiveSessions = const [];
  ServiceRoutingStep _serviceRoutingStep = ServiceRoutingStep.none;
  Timer? _recordingUiTimer;
  DateTime? _recordingStartedAt;
  Duration _recordingElapsed = Duration.zero;
  int _recordingWaveSeed = 0;
  int _activeSubmissionToken = 0;
  http.Client? _activeRequestClient;

  @override
  void initState() {
    super.initState();
    _showWelcomeScreen = !widget.startInChatMode;
    _messageController.addListener(_handleComposerChanged);
    _baseUrlController.text = _defaultBaseUrlOverride.isNotEmpty
        ? _defaultBaseUrlOverride
        : (Platform.isAndroid
              ? 'http://192.168.0.13:8000'
              : 'http://127.0.0.1:8000');
    unawaited(_configureTts());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkConnection());
  }

  @override
  void dispose() {
    _messageController
      ..removeListener(_handleComposerChanged)
      ..dispose();
    _baseUrlController.dispose();
    _scrollController.dispose();
    _recordingUiTimer?.cancel();
    unawaited(_voiceRecorder.dispose());
    unawaited(_tts.stop());
    _activeRequestClient?.close();
    super.dispose();
  }

  void _handleComposerChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _stopSubmittingResponse() async {
    if (!_isSubmitting) {
      return;
    }

    _cancelSubmissionRequested = true;
    _activeSubmissionToken += 1;

    try {
      _activeRequestClient?.close();
    } catch (_) {}

    await _stopSpeaking();

    if (!mounted) {
      return;
    }

    setState(() {
      _isSubmitting = false;
      _isMicButtonPressed = false;
      _errorMessage = null;
      _serverStatus = '중단됨';
    });
  }

  AssistantMode get _assistantMode {
    if (_isSubmitting) {
      return AssistantMode.replying;
    }
    if (_selectedImage != null) {
      return AssistantMode.photo;
    }
    if (_isRecordingVoice ||
        _isRecordingNoise ||
        _selectedAudio != null ||
        _recordedVoice != null ||
        _recordedNoise != null) {
      return AssistantMode.audio;
    }
    return AssistantMode.idle;
  }

  bool get _canSend {
    return !_isSubmitting &&
        (_messageController.text.trim().isNotEmpty ||
            _selectedImage != null ||
            _selectedAudio != null ||
            _recordedVoice != null ||
            _recordedNoise != null);
  }

  String get _displayName {
    final value = _dbUserName.trim();
    return value.isEmpty ? 'ㅇㅇ' : value;
  }

  String get _baseUrl {
    final value = _baseUrlController.text.trim();
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  bool get _isRecordingActive => _isRecordingVoice || _isRecordingNoise;

  _ModePresentation get _modePresentation {
    switch (_assistantMode) {
      case AssistantMode.audio:
        return const _ModePresentation(
          label: 'AI CHAT · Listening Sound Ver',
          title: '소리를 듣고 있어요.\n정확한 진단을 위해\n주변 소음을 차단해주세요.',
          description: '말하기(STT)와 소음 녹음을 구분해서 인식하고 처리해요.',
          hintText: '소리 특징을 텍스트로 입력해주세요',
          gradientColors: [Color(0xFFFFF4F1), Color(0xFFFFD9D2)],
          accent: Color(0xFFE95A4D),
        );
      case AssistantMode.photo:
        return const _ModePresentation(
          label: 'AI CHAT · Analyzing Photo Ver',
          title: '사진 모드예요.\n증상이 잘 보이도록\n가까이 찍어주세요.',
          description: '카메라로 다시 촬영하거나 갤러리 사진을 교체할 수 있어요.',
          hintText: '사진과 함께 상태를 입력해주세요',
          gradientColors: [Color(0xFFFFF5F2), Color(0xFFFFDDE2)],
          accent: Color(0xFFEF6B64),
        );
      case AssistantMode.replying:
        return const _ModePresentation(
          label: 'AI CHAT · Thinking Ver',
          title: '답변을 작성중이에요.\n조금만 기다려주세요.',
          description: '텍스트, 사진, 소리 정보를 합쳐서 진단 내용을 정리하고 있어요.',
          hintText: '응답 생성 중 ···',
          gradientColors: [Color(0xFFFFF4F2), Color(0xFFFFD7DB)],
          accent: Color(0xFFD34B5C),
        );
      case AssistantMode.idle:
      case AssistantMode.maincharacter:
        return _ModePresentation(
          label: 'AI CHAT · Normal Ver',
          title: '안녕하세요 $_displayName님\n어떤 문제 상황인가요?',
          description:
              '텍스트를 입력하거나 + 버튼으로 사진과 파일을, 마이크 버튼으로 STT 또는 소음 녹음을 선택할 수 있어요.',
          hintText: '메시지를 입력하세요',
          gradientColors: const [Color(0xFFFFF7F3), Color(0xFFFFDCD6)],
          accent: const Color(0xFFE9524A),
        );
    }
  }

  String _characterAssetForMode(AssistantMode mode) {
    switch (mode) {
      case AssistantMode.idle:
        return 'assets/characters/idle.png';
      case AssistantMode.audio:
        return 'assets/characters/audio.png';
      case AssistantMode.photo:
        return 'assets/characters/photo.png';
      case AssistantMode.replying:
        return 'assets/characters/replying.png';
      case AssistantMode.maincharacter:
        return 'assets/characters/rebo_Image.png';
    }
  }

  TextStyle get _composerPlaceholderStyle => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: const Color(0xFF6A6764).withValues(alpha: 0.78),
    height: 1.2,
  );

  Widget _buildComposerDisclaimer() {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Text(
            'AI가 생성한 응답은 부정확할 수 있습니다.',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6A6764),
              height: 1.2,
            ),
          ),
          SizedBox(width: 4),
          Text(
            '더보기',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6A6764),
              decoration: TextDecoration.underline,
              decorationColor: Color(0xFF6A6764),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _configureTts() async {
    _tts.setStartHandler(() {});
    _tts.setCompletionHandler(() {});
    _tts.setCancelHandler(() {});
    _tts.setErrorHandler((_) {});

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
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '음성 출력을 준비하지 못했습니다: $error';
      });
    }
  }

  Future<void> _stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void _startRecordingUiTimer() {
    _recordingUiTimer?.cancel();
    _recordingStartedAt = DateTime.now();
    _recordingElapsed = Duration.zero;
    _recordingWaveSeed = 0;
    _recordingUiTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      if (!mounted || _recordingStartedAt == null) {
        return;
      }
      setState(() {
        _recordingWaveSeed += 1;
        _recordingElapsed = DateTime.now().difference(_recordingStartedAt!);
      });
    });
  }

  void _stopRecordingUiTimer({bool reset = true}) {
    _recordingUiTimer?.cancel();
    _recordingUiTimer = null;
    if (reset) {
      _recordingStartedAt = null;
      _recordingElapsed = Duration.zero;
      _recordingWaveSeed = 0;
    }
  }

  String _formatRecordingElapsed() {
    final totalSeconds = _recordingElapsed.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _speakText(String text) async {
    final trimmed = _stripSimpleMarkdown(text).trim();
    if (trimmed.isEmpty) {
      return;
    }

    try {
      await _stopSpeaking();
      await _tts.speak(trimmed);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '음성 재생에 실패했습니다: $error';
      });
    }
  }

  Future<void> _checkConnection() async {
    if (_isCheckingConnection) {
      return;
    }

    setState(() {
      _isCheckingConnection = true;
      _serverStatus = '확인 중';
      _errorMessage = null;
    });

    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 8));

      if (!mounted) {
        return;
      }

      setState(() {
        _serverHealthy =
            response.statusCode >= 200 && response.statusCode < 300;
        _serverStatus = _serverHealthy ? '연결됨' : 'HTTP ${response.statusCode}';
        if (!_serverHealthy) {
          _errorMessage = '백엔드 상태 확인에 실패했습니다.';
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

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

  Future<void> _pickImageFromSource(ImageSource source) async {
    final file = await _imagePicker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1600,
      preferredCameraDevice: CameraDevice.rear,
    );

    if (!mounted || file == null) {
      return;
    }

    setState(() {
      _selectedImage = File(file.path);
      _selectedImageName = file.name;
      _errorMessage = null;
    });
  }

  Future<void> _capturePhoto() => _pickImageFromSource(ImageSource.camera);

  Future<void> _pickImageFromGallery() =>
      _pickImageFromSource(ImageSource.gallery);

  Future<void> _pickAudio() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.audio,
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

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
        _errorMessage = '지원하는 오디오 형식만 사용할 수 있어요: wav, mp3, m4a, aac, flac';
      });
      return;
    }

    setState(() {
      _selectedAudio = File(picked.path!);
      _selectedAudioName = picked.name;
      _errorMessage = null;
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
    if (_isSubmitting) {
      return;
    }

    try {
      await _stopSpeaking();
      final hasPermission = await _voiceRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorMessage = '마이크 권한이 필요합니다.';
        });
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath =
          '${tempDir.path}${Platform.pathSeparator}recorded_audio_$timestamp.m4a';

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

      if (!mounted) {
        return;
      }

      setState(() {
        _isRecordingVoice = true;
        _recordedVoice = null;
        _recordedVoiceName = null;
        _errorMessage = null;
      });
      _startRecordingUiTimer();
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isRecordingVoice = false;
        _errorMessage = '녹음을 시작하지 못했습니다: $error';
      });
      _stopRecordingUiTimer();
    }
  }

  Future<void> _stopVoiceRecording() async {
    try {
      final savedPath = await _voiceRecorder.stop();
      _stopRecordingUiTimer();
      if (!mounted) {
        return;
      }

      setState(() {
        _isRecordingVoice = false;
        if (savedPath == null || savedPath.isEmpty) {
          _errorMessage = '녹음 파일을 저장하지 못했습니다.';
          return;
        }

        _recordedVoice = File(savedPath);
        _recordedVoiceName = _basename(savedPath);
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isRecordingVoice = false;
        _errorMessage = '녹음을 종료하지 못했습니다: $error';
      });
      _stopRecordingUiTimer();
    }
  }

  Future<void> _toggleNoiseRecording() async {
    if (_isRecordingNoise) {
      await _stopNoiseRecording();
      return;
    }
    await _startNoiseRecording();
  }

  Future<void> _startNoiseRecording() async {
    if (_isSubmitting) return;
    if (_isRecordingVoice) {
      if (!mounted) return;
      setState(() => _errorMessage = '음성 녹음 중에는 소음 녹음을 시작할 수 없습니다.');
      return;
    }

    try {
      await _stopSpeaking();
      final hasPermission = await _voiceRecorder.hasPermission();
      if (!hasPermission) {
        if (!mounted) return;
        setState(() => _errorMessage = '마이크 권한이 필요합니다.');
        return;
      }

      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final outputPath =
          '${tempDir.path}${Platform.pathSeparator}noise_recording_$timestamp.wav';

      await _voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 22050,
          numChannels: 1,
          autoGain: false,
          echoCancel: false,
          noiseSuppress: false,
        ),
        path: outputPath,
      );

      if (!mounted) return;

      setState(() {
        _isRecordingNoise = true;
        _recordedNoise = null;
        _recordedNoiseName = null;
        _errorMessage = null;
      });
      _startRecordingUiTimer();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isRecordingNoise = false;
        _errorMessage = '소음 녹음을 시작하지 못했습니다: $error';
      });
      _stopRecordingUiTimer();
    }
  }

  Future<void> _stopNoiseRecording() async {
    try {
      final savedPath = await _voiceRecorder.stop();
      _stopRecordingUiTimer();
      if (!mounted) return;

      setState(() {
        _isRecordingNoise = false;
        if (savedPath == null || savedPath.isEmpty) {
          _errorMessage = '소음 녹음 파일을 저장하지 못했습니다.';
          return;
        }
        _recordedNoise = File(savedPath);
        _recordedNoiseName = _basename(savedPath);
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isRecordingNoise = false;
        _errorMessage = '소음 녹음을 종료하지 못했습니다: $error';
      });
      _stopRecordingUiTimer();
    }
  }

  Future<void> _cancelActiveRecording() async {
    if (!_isRecordingActive) {
      return;
    }

    try {
      final savedPath = await _voiceRecorder.stop();
      if (savedPath != null && savedPath.isNotEmpty) {
        final file = File(savedPath);
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {}

    _stopRecordingUiTimer();
    if (!mounted) {
      return;
    }

    setState(() {
      _isRecordingVoice = false;
      _isRecordingNoise = false;
      _recordedVoice = null;
      _recordedVoiceName = null;
      _recordedNoise = null;
      _recordedNoiseName = null;
      _errorMessage = null;
    });
  }

  Future<void> _handleMicTap() async {
    if (_isRecordingVoice) {
      await _stopVoiceRecording();
      return;
    }
    if (_isRecordingNoise) {
      await _stopNoiseRecording();
      return;
    }
    await _showMicModeSheet();
  }

  Future<void> _showMicModeSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x33212121),
      useSafeArea: false,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 54),
          decoration: const BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Color(0x0D212121),
                blurRadius: 4,
                offset: Offset(0, -4),
              ),
            ],
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '녹음방법',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF212121),
                  height: 1.11,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '어떤 내용을 녹음할지 선택해주세요.',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF5D5B5B),
                  height: 1.14,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        Future<void>.delayed(
                          const Duration(milliseconds: 120),
                          _startVoiceRecording,
                        );
                      },
                      child: Container(
                        height: 79,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F7F7),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.mic_rounded,
                              size: 24,
                              color: Color(0xFF5D5B5B),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '음성채팅',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF5D5B5B),
                                height: 1.125,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        Future<void>.delayed(
                          const Duration(milliseconds: 120),
                          _startNoiseRecording,
                        );
                      },
                      child: Container(
                        height: 79,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F7F7),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(
                              Icons.graphic_eq_rounded,
                              size: 24,
                              color: Color(0xFF5D5B5B),
                            ),
                            SizedBox(height: 4),
                            Text(
                              '소음/진동',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF5D5B5B),
                                height: 1.125,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openAttachmentSheet() async {
    if (_isSubmitting) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) {
        Future<void> handleTap(Future<void> Function() action) async {
          Navigator.of(sheetContext).pop();
          await Future<void>.delayed(const Duration(milliseconds: 120));
          await action();
        }

        return Container(
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 54),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(32),
              topRight: Radius.circular(32),
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x0D212121),
                blurRadius: 4,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '첨부방법',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF212121),
                  height: 1.11,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '필요한 방식을 선택해주세요',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: Color(0xFF5D5B5B),
                  height: 1.14,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _AttachmentQuickAction(
                      icon: Icons.photo_camera_outlined,
                      label: '카메라',
                      onTap: () => handleTap(_capturePhoto),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AttachmentQuickAction(
                      icon: Icons.image_outlined,
                      label: '사진',
                      onTap: () => handleTap(_pickImageFromGallery),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _AttachmentQuickAction(
                      icon: Icons.attach_file_rounded,
                      label: '파일',
                      onTap: () => handleTap(_pickAudio),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

  String _stripSimpleMarkdown(String text) {
    return text.replaceAllMapped(
      RegExp(r'\*\*(.*?)\*\*', dotAll: true),
      (match) => match.group(1) ?? '',
    );
  }

  List<InlineSpan> _buildMessageTextSpans({
    required String message,
    required TextStyle baseStyle,
  }) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*(.*?)\*\*', dotAll: true);
    var cursor = 0;

    for (final match in pattern.allMatches(message)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: message.substring(cursor, match.start),
            style: baseStyle,
          ),
        );
      }

      spans.add(
        TextSpan(
          text: match.group(1) ?? '',
          style: baseStyle.copyWith(fontWeight: FontWeight.w800),
        ),
      );
      cursor = match.end;
    }

    if (cursor < message.length) {
      spans.add(TextSpan(text: message.substring(cursor), style: baseStyle));
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: message, style: baseStyle));
    }

    return spans;
  }

  bool _containsServiceActionIntent(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }

    return _serviceActionKeywords.any(normalized.contains);
  }

  String _buildLocalUserDisplayMessage({
    required String message,
    String? imageName,
    String? audioName,
    String? voiceName,
    String? noiseName,
  }) {
    final parts = <String>[];
    if (message.trim().isNotEmpty) {
      parts.add(message.trim());
    }
    if (imageName != null && imageName.trim().isNotEmpty) {
      parts.add('[이미지 첨부: ${imageName.trim()}]');
    }
    if (audioName != null && audioName.trim().isNotEmpty) {
      parts.add('[오디오 첨부: ${audioName.trim()}]');
    }
    if (voiceName != null && voiceName.trim().isNotEmpty) {
      parts.add('[음성 메시지: ${voiceName.trim()}]');
    }
    if (noiseName != null && noiseName.trim().isNotEmpty) {
      parts.add('[오디오 첨부: ${noiseName.trim()}]');
    }
    return parts.isEmpty ? '[입력 없음]' : parts.join('\n');
  }

  void _appendLocalUserTurnAndPromptServiceRouting({
    required String userMessage,
    String? imagePath,
    String? imageName,
  }) {
    setState(() {
      _history = [
        ..._history,
        ChatTurn(
          user: userMessage,
          assistant: '',
          userImagePath: imagePath,
          userImageName: imageName,
        ),
      ];
      _serviceRoutingStep = ServiceRoutingStep.askDiagnosis;
      _selectedImage = null;
      _selectedAudio = null;
      _recordedVoice = null;
      _recordedNoise = null;
      _selectedImageName = null;
      _selectedAudioName = null;
      _recordedVoiceName = null;
      _recordedNoiseName = null;
      _messageController.clear();
      _errorMessage = null;
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
  }

  void _startAiDiagnosisFromRouting() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _serviceRoutingStep = ServiceRoutingStep.none;
      _history = const [];
      _chatSessionId = null;
      _selectedImage = null;
      _selectedAudio = null;
      _recordedVoice = null;
      _recordedNoise = null;
      _selectedImageName = null;
      _selectedAudioName = null;
      _recordedVoiceName = null;
      _recordedNoiseName = null;
      _latestEvidence = null;
      _errorMessage = null;
      _messageController.clear();
    });
  }

  void _handleServiceActionSelection(String actionLabel) {
    setState(() {
      _serviceRoutingStep = ServiceRoutingStep.none;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$actionLabel 선택 화면으로 이어질 수 있도록 준비했어요.')),
    );
  }

  String _stripDisplayedImageAttachmentLine(String message) {
    return message
        .split('\n')
        .where((line) => !line.trim().startsWith('[이미지 첨부:'))
        .join('\n')
        .trim();
  }

  List<ChatTurn> _mergeHistoryWithLocalMetadata(
    List<ChatTurn> nextHistory, {
    required List<ChatTurn> previousHistory,
    String? submittedImagePath,
    String? submittedImageName,
  }) {
    final merged = <ChatTurn>[];

    for (var index = 0; index < nextHistory.length; index++) {
      final nextTurn = nextHistory[index];
      var imagePath = nextTurn.userImagePath;
      var imageName = nextTurn.userImageName;

      if (index < previousHistory.length) {
        final previousTurn = previousHistory[index];
        if (previousTurn.user == nextTurn.user &&
            previousTurn.assistant == nextTurn.assistant) {
          imagePath ??= previousTurn.userImagePath;
          imageName ??= previousTurn.userImageName;
        }
      }

      if (index == nextHistory.length - 1 && submittedImagePath != null) {
        imagePath = submittedImagePath;
        imageName = submittedImageName;
      }

      merged.add(
        nextTurn.copyWith(userImagePath: imagePath, userImageName: imageName),
      );
    }

    return merged;
  }

  Future<void> _sendMessage() async {
    if (_isSubmitting) {
      return;
    }

    if (_isRecordingVoice) {
      await _stopVoiceRecording();
    }
    if (_isRecordingNoise) {
      await _stopNoiseRecording();
    }

    final message = _messageController.text.trim();
    if (message.isEmpty &&
        _selectedImage == null &&
        _selectedAudio == null &&
        _recordedVoice == null &&
        _recordedNoise == null) {
      setState(() {
        _errorMessage = '텍스트, 사진, 음성 중 하나 이상을 추가해주세요.';
      });
      return;
    }

    await _stopSpeaking();
    FocusManager.instance.primaryFocus?.unfocus();

    setState(() {
      _isSubmitting = true;
      _isMicButtonPressed = false;
      _errorMessage = null;
      _serviceRoutingStep = ServiceRoutingStep.none;
    });

    final submissionToken = ++_activeSubmissionToken;
    final requestClient = http.Client();
    _activeRequestClient = requestClient;
    _cancelSubmissionRequested = false;

    try {
      final previousHistory = List<ChatTurn>.from(_history);
      final submittedImagePath = _selectedImage?.path;
      final submittedImageName = _selectedImageName;

      final request =
          http.MultipartRequest('POST', Uri.parse('$_baseUrl/api/chat'))
            ..fields['message'] = message
            ..fields['user_name'] = _displayName
            ..fields['user_id'] = _dbUserId.toString()
            ..fields['history_json'] = jsonEncode(
              _history.map((turn) => turn.toJson()).toList(),
            );

      if (_chatSessionId != null) {
        request.fields['session_id'] = _chatSessionId.toString();
      }

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

      if (_recordedNoise != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'audio',
            _recordedNoise!.path,
            filename: _recordedNoiseName,
          ),
        );
      }

      final streamed = await requestClient
          .send(request)
          .timeout(const Duration(seconds: 90));
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

      final mergedHistory = _mergeHistoryWithLocalMetadata(
        nextHistory,
        previousHistory: previousHistory,
        submittedImagePath: submittedImagePath,
        submittedImageName: submittedImageName,
      );
      final routingRequired = decoded['routing_required'] == true;
      final routingIntent = decoded['routing_intent']?.toString();
      const asRoutingIntents = {'as_request', 'connect_agent', 'book_visit'};
      final isAsRouting =
          routingRequired && asRoutingIntents.contains(routingIntent);
      final nextRoutingStep = ServiceRoutingStep.none;

      // AS 관련 인텐트 → 마지막 턴 assistant를 __AS_ROUTING__으로 교체
      final rawAssistantMessage =
          decoded['assistant_message']?.toString().trim() ??
          (mergedHistory.isNotEmpty ? mergedHistory.last.assistant : '');
      final assistantMessage = isAsRouting
          ? '__AS_ROUTING__'
          : rawAssistantMessage;
      final shouldSpeak =
          _autoSpeak && assistantMessage.isNotEmpty && !isAsRouting;

      final finalHistory = isAsRouting && mergedHistory.isNotEmpty
          ? [
              ...mergedHistory.sublist(0, mergedHistory.length - 1),
              mergedHistory.last.copyWith(assistant: '__AS_ROUTING__'),
            ]
          : mergedHistory;

      if (!mounted || submissionToken != _activeSubmissionToken) {
        return;
      }

      setState(() {
        _history = finalHistory;
        _chatSessionId = decoded['session_id'] is num
            ? (decoded['session_id'] as num).toInt()
            : _chatSessionId;
        _serviceRoutingStep = nextRoutingStep;
        _latestEvidence = routingRequired
            ? null
            : const JsonEncoder.withIndent('  ').convert(decoded['evidence']);
        _selectedImage = null;
        _selectedAudio = null;
        _recordedVoice = null;
        _recordedNoise = null;
        _selectedImageName = null;
        _selectedAudioName = null;
        _recordedVoiceName = null;
        _recordedNoiseName = null;
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
      if (!mounted) {
        return;
      }

      if (_cancelSubmissionRequested ||
          submissionToken != _activeSubmissionToken) {
        setState(() {
          _errorMessage = null;
          _serverStatus = '중단됨';
        });
        return;
      }

      setState(() {
        _serverHealthy = false;
        _serverStatus = '요청 실패';
        _errorMessage = error.toString();
      });
    } finally {
      requestClient.close();
      if (identical(_activeRequestClient, requestClient)) {
        _activeRequestClient = null;
      }
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
      if (submissionToken == _activeSubmissionToken) {
        _cancelSubmissionRequested = false;
      }
    }
  }

  Future<void> _resetConversation() async {
    if (_isRecordingVoice) {
      await _stopVoiceRecording();
    }
    if (_isRecordingNoise) {
      await _stopNoiseRecording();
    }
    _stopRecordingUiTimer();
    await _stopSpeaking();
    if (!mounted) {
      return;
    }

    setState(() {
      _history = const [];
      _chatSessionId = null;
      _serviceRoutingStep = ServiceRoutingStep.none;
      _selectedImage = null;
      _selectedAudio = null;
      _recordedVoice = null;
      _recordedNoise = null;
      _selectedImageName = null;
      _selectedAudioName = null;
      _recordedVoiceName = null;
      _recordedNoiseName = null;
      _latestEvidence = null;
      _errorMessage = null;
      _messageController.clear();
    });
  }

  void _openChatHome() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _showWelcomeScreen = false;
      _showArchiveScreen = false;
      _archiveOpenedFromChat = false;
      _selectedBottomNavIndex = 2;
      _history = const [];
      _chatSessionId = null;
      _serviceRoutingStep = ServiceRoutingStep.none;
      _selectedImage = null;
      _selectedAudio = null;
      _recordedVoice = null;
      _recordedNoise = null;
      _selectedImageName = null;
      _selectedAudioName = null;
      _recordedVoiceName = null;
      _recordedNoiseName = null;
      _latestEvidence = null;
      _errorMessage = null;
      _messageController.clear();
    });
  }

  void _closeArchiveScreen() {
    setState(() {
      _showArchiveScreen = false;
      _showWelcomeScreen = !_archiveOpenedFromChat;
      _archiveOpenedFromChat = false;
    });
  }

  Future<void> _openArchiveScreen() async {
    FocusManager.instance.primaryFocus?.unfocus();
    await _stopSpeaking();
    if (!mounted) {
      return;
    }

    final openedFromChat = !_showWelcomeScreen && !_showArchiveScreen;

    setState(() {
      _showWelcomeScreen = false;
      _showArchiveScreen = true;
      _archiveOpenedFromChat = openedFromChat;
      _archiveErrorMessage = null;
    });

    await _loadArchiveSessions();

    if (!mounted || _showArchiveScreen) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 14),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.78,
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF8),
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 28,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'chat_archive',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                Text(
                  '저장된 대화 목록을 확인해보세요.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.black.withValues(alpha: 0.56),
                  ),
                ),
                const SizedBox(height: 14),
                if (_archiveErrorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1ED),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFFFD8CC)),
                    ),
                    child: Text(
                      _archiveErrorMessage!,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.45,
                        color: Color(0xFF8A4C42),
                      ),
                    ),
                  )
                else if (_archiveSessions.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      '저장된 대화가 아직 없어요.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _archiveSessions.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final session = _archiveSessions[index];
                        return Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            onTap: () async {
                              Navigator.of(sheetContext).pop();
                              await Future<void>.delayed(
                                const Duration(milliseconds: 120),
                              );
                              await _showArchiveSessionDetail(session);
                            },
                            borderRadius: BorderRadius.circular(20),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                14,
                                14,
                                14,
                                12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFEEE9),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          _archiveStatusLabel(session.status),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w800,
                                            color: Color(0xFFE9524A),
                                          ),
                                        ),
                                      ),
                                      const Spacer(),
                                      Text(
                                        _formatArchiveTimestamp(
                                          session.lastMessageAt,
                                        ),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.black.withValues(
                                            alpha: 0.42,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    session.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    session.summary,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      height: 1.45,
                                      color: Colors.black.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadArchiveSessions() async {
    if (_isLoadingArchive) {
      return;
    }

    setState(() {
      _isLoadingArchive = true;
      _archiveErrorMessage = null;
    });

    try {
      final response = await http
          .get(
            Uri.parse(
              '$_baseUrl/api/archive/sessions?user_id=$_dbUserId&limit=50',
            ),
          )
          .timeout(const Duration(seconds: 20));

      final body = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          body is Map<String, dynamic>
              ? body['detail']?.toString() ?? response.body
              : response.body,
        );
      }

      if (body is! Map<String, dynamic>) {
        throw const FormatException('보관함 응답 형식이 올바르지 않습니다.');
      }

      final items = <ArchiveSessionSummary>[];
      final rawSessions = body['sessions'];
      if (rawSessions is List) {
        for (final item in rawSessions) {
          if (item is Map) {
            items.add(ArchiveSessionSummary.fromJson(item));
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _archiveSessions = items;
        _serverHealthy = true;
        _serverStatus = '연결됨';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _archiveErrorMessage = error.toString();
        _serverHealthy = false;
        _serverStatus = '요청 실패';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingArchive = false);
      }
    }
  }

  Future<void> _showArchiveSessionDetail(ArchiveSessionSummary session) async {
    try {
      final response = await http
          .get(Uri.parse('$_baseUrl/api/archive/sessions/${session.id}'))
          .timeout(const Duration(seconds: 20));

      final body = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          body is Map<String, dynamic>
              ? body['detail']?.toString() ?? response.body
              : response.body,
        );
      }

      if (body is! Map<String, dynamic>) {
        throw const FormatException('보관함 상세 응답 형식이 올바르지 않습니다.');
      }

      final messages = <ArchiveMessage>[];
      final rawMessages = body['messages'];
      if (rawMessages is List) {
        for (final item in rawMessages) {
          if (item is Map) {
            messages.add(ArchiveMessage.fromJson(item));
          }
        }
      }

      if (!mounted) {
        return;
      }

      final restoredHistory = _restoreChatTurnsFromArchiveMessages(messages);
      if (restoredHistory.isEmpty) {
        throw const FormatException('이어서 열 수 있는 대화 내용이 없어요.');
      }

      setState(() {
        _history = restoredHistory;
        _chatSessionId = session.id;
        _showWelcomeScreen = false;
        _showArchiveScreen = false;
        _archiveOpenedFromChat = false;
        _selectedBottomNavIndex = 2;
        _serviceRoutingStep = ServiceRoutingStep.none;
        _selectedImage = null;
        _selectedAudio = null;
        _recordedVoice = null;
        _recordedNoise = null;
        _selectedImageName = null;
        _selectedAudioName = null;
        _recordedVoiceName = null;
        _recordedNoiseName = null;
        _latestEvidence = null;
        _errorMessage = null;
        _messageController.clear();
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
      return;

      // ignore: dead_code
      await _showSheet(
        session.title,
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: messages.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final message = messages[index];
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.role == 'assistant' ? 'AI 답변' : '사용자',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      message.content,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _confirmDeleteArchiveSession(
    ArchiveSessionSummary session,
  ) async {
    final shouldDelete = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x22000000),
                  blurRadius: 24,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '이 대화를 보관함에서 삭제할까요?',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF212121),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  session.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3B3B3B),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  session.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: Colors.black.withValues(alpha: 0.56),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          side: BorderSide(
                            color: Colors.black.withValues(alpha: 0.12),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          '취소',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF525252),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          backgroundColor: const Color(0xFFE9524A),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          '삭제',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldDelete == true) {
      await _deleteArchiveSession(session);
    }
  }

  Future<void> _deleteArchiveSession(ArchiveSessionSummary session) async {
    try {
      final response = await http
          .delete(
            Uri.parse(
              '$_baseUrl/api/archive/sessions/${session.id}?user_id=$_dbUserId',
            ),
          )
          .timeout(const Duration(seconds: 20));

      final body = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          body is Map<String, dynamic>
              ? body['detail']?.toString() ?? response.body
              : response.body,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _archiveSessions = _archiveSessions
            .where((item) => item.id != session.id)
            .toList();
        if (_chatSessionId == session.id) {
          _chatSessionId = null;
        }
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('보관함에서 삭제했어요.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  List<ChatTurn> _restoreChatTurnsFromArchiveMessages(
    List<ArchiveMessage> messages,
  ) {
    final restored = <ChatTurn>[];
    String? pendingUser;
    String? pendingImageName;

    String userContentFor(ArchiveMessage message) {
      final content = message.content.trim();
      if (content.isNotEmpty) {
        return message.content;
      }
      if (message.attachmentNames.isEmpty) {
        return '';
      }
      final label = switch (message.messageType) {
        'image' => '이미지 첨부',
        'audio' => '음성 첨부',
        _ => '첨부 파일',
      };
      return message.attachmentNames
          .map((name) => '[$label: $name]')
          .join('\n');
    }

    void pushPending({String assistant = ''}) {
      if ((pendingUser == null || pendingUser!.isEmpty) &&
          pendingImageName == null &&
          assistant.isEmpty) {
        return;
      }

      restored.add(
        ChatTurn(
          user: pendingUser ?? '',
          assistant: assistant,
          userImageName: pendingImageName,
        ),
      );
      pendingUser = null;
      pendingImageName = null;
    }

    for (final message in messages) {
      if (message.role == 'user') {
        pushPending();
        pendingUser = userContentFor(message);
        pendingImageName =
            message.messageType == 'image' && message.attachmentNames.isNotEmpty
            ? message.attachmentNames.first
            : null;
        continue;
      }

      if (message.role == 'assistant') {
        if (pendingUser == null && pendingImageName == null) {
          restored.add(ChatTurn(user: '', assistant: message.content));
        } else {
          pushPending(assistant: message.content);
        }
      }
    }

    pushPending();
    return restored;
  }

  String _formatArchiveTimestamp(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '';
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return value;
    }
    final local = parsed.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month.$day $hour:$minute';
  }

  String _archiveStatusLabel(String status) {
    switch (status) {
      case 'resolved':
        return '해결됨';
      case 'archived':
        return '보관됨';
      default:
        return '진행중';
    }
  }

  Widget _buildArchiveScreen() {
    final hasSessions = _archiveSessions.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFEFF1F4),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 19,
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: '홈으로',
              onPressed: _closeArchiveScreen,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 20,
                color: Color(0xFF212121),
              ),
            ),
            const Text(
              '채팅 보관함',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF212121),
                height: 1.11,
              ),
            ),
            const SizedBox(width: 24),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // 정렬 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(19, 8, 19, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    '최신순',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF606C80),
                      height: 1.17,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: '새로고침',
                    onPressed: _loadArchiveSessions,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    icon: const Icon(
                      Icons.refresh_rounded,
                      size: 16,
                      color: Color(0xFF606C80),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFFE9524A),
                onRefresh: _loadArchiveSessions,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(19, 0, 19, 20),
                  children: [
                    if (_archiveErrorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF2EF),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFFFD1C6)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '목록을 불러오지 못했어요.',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF9D3F30),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _archiveErrorMessage!,
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.45,
                                color: Color(0xFF7A4A42),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: _loadArchiveSessions,
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_isLoadingArchive && !hasSessions) ...[
                      const SizedBox(height: 64),
                      const Center(child: CircularProgressIndicator()),
                      const SizedBox(height: 12),
                      const Center(
                        child: Text(
                          '보관된 대화를 불러오는 중이에요.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF606C80),
                          ),
                        ),
                      ),
                    ] else if (!hasSessions) ...[
                      _buildArchiveEmptyState(),
                    ] else ...[
                      for (final session in _archiveSessions) ...[
                        _buildArchiveSessionCard(session),
                        const SizedBox(height: 12),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            // 하단 안내 문구
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF606C80),
                  ),
                  SizedBox(width: 4),
                  Text(
                    '채팅 기록은 최대 3년까지 보관할 수 있어요.',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF606C80),
                      height: 2,
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.hideBottomNav) _buildPrimaryNavigation(),
          ],
        ),
      ),
    );
  }

  Widget _buildArchiveEmptyState() {
    return SizedBox(
      height: 300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(
            Icons.chat_bubble_outline_rounded,
            size: 64,
            color: Color(0xFFD9D9D9),
          ),
          SizedBox(height: 12),
          Text(
            '보관된 채팅이 없어요.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF212121),
              height: 1.125,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildArchiveSessionCard(ArchiveSessionSummary session) {
    return GestureDetector(
      onTap: () => _showArchiveSessionDetail(session),
      onLongPress: () => _confirmDeleteArchiveSession(session),
      child: Container(
        padding: const EdgeInsets.all(19),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 제목 + 날짜
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF212121),
                      height: 1.43,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatArchiveTimestamp(session.lastMessageAt),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: Color(0xFF999999),
                    height: 1.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // AI 요약 라벨
            Row(
              children: [
                Image.asset(
                  'assets/icon/AI.png',
                  width: 16,
                  height: 16,
                  errorBuilder: (context, error, _) => const Icon(
                    Icons.auto_awesome_rounded,
                    size: 16,
                    color: Color(0xFF606C80),
                  ),
                ),
                const SizedBox(width: 4),
                const Text(
                  'AI 요약',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF606C80),
                    height: 1.17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 요약 내용
            Text(
              session.summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: Color(0xFF5D5B5B),
                height: 1.33,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 19,
        title: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'ChatThinQ',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Color(0xFF212121),
              ),
            ),
          ],
        ),
      ),
      backgroundColor: const Color(0xFFFCEDEB),
      body: Stack(
        children: [
          // 배경 블러 원 (좌측 상단)
          Positioned(
            left: -120,
            top: MediaQuery.of(context).size.height * 0.05,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFCAEB2).withValues(alpha: 0.60),
                      const Color(0xFFFCBABD).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 배경 블러 원 (우측 하단)
          Positioned(
            right: -120,
            bottom: MediaQuery.of(context).size.height * 0.1,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFCAEB2).withValues(alpha: 0.60),
                      const Color(0xFFFCBABD).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(19, 0, 19, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        // 인삿말 섹션
                        const Text(
                          '수현님 점심엔 쉬어가요',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF212121),
                            height: 1.44,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '생성형 AI를 활용한 스마트홈 어시스턴트로\n더 넓고 자유로운 일상의 대화를 경험해보세요!',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF5D5B5B),
                            height: 1.43,
                          ),
                        ),
                        const SizedBox(height: 48),
                        // NEW 배지
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE95744),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NEW',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              height: 1.4,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'AS와 문제 진단으로 고통 받았던\n당신만을 위한 새로운 해결사',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF212121),
                            height: 1.44,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 카드
                        GestureDetector(
                          onTap: _openChatHome,
                          child: Container(
                            width: double.infinity,
                            height: 125,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(36),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x0D000000),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(36),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(
                                        left: 19,
                                        top: 16,
                                        bottom: 16,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Text(
                                            '제품과 관련된 질문은\n저에게 물어보세요!',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF212121),
                                              height: 1.43,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 8,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFD6DBFC),
                                              borderRadius:
                                                  BorderRadius.circular(100),
                                            ),
                                            child: const Text(
                                              'Chat REBO 사용하기',
                                              style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF4D57B9),
                                                height: 1.17,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 167,
                                    height: 125,
                                    child: Image.asset(
                                      _characterAssetForMode(
                                        AssistantMode.maincharacter,
                                      ),
                                      fit: BoxFit.cover,
                                      alignment: Alignment.bottomRight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        _buildComposerDisclaimer(),
                        const SizedBox(height: 12),
                        _buildWelcomeComposer(),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
                if (!widget.hideBottomNav) _buildPrimaryNavigation(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeComposer() {
    return SizedBox(
      height: 42,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Image.asset(
                'assets/icon/1.png',
                width: 18,
                height: 18,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _modePresentation.hintText,
                style: _composerPlaceholderStyle,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Image.asset(
                'assets/icon/mic_non.png',
                width: 18,
                height: 18,
                fit: BoxFit.contain,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 2, right: 6),
              child: Image.asset(
                'assets/icon/send_non.png',
                width: 18,
                height: 18,
                fit: BoxFit.contain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeNavigation() {
    final items =
        <({IconData icon, String label, bool active, VoidCallback? onTap})>[
          (
            icon: Icons.home_filled,
            label: '홈',
            active: !_showArchiveScreen,
            onTap: () => setState(() {
              _showWelcomeScreen = true;
              _showArchiveScreen = false;
            }),
          ),
          (
            icon: Icons.grid_view_rounded,
            label: '디바이스',
            active: false,
            onTap: null,
          ),
          (
            icon: Icons.search_rounded,
            label: '챗봇',
            active: false,
            onTap: _openChatHome,
          ),
          (
            icon: Icons.bar_chart_rounded,
            label: '제어',
            active: false,
            onTap: null,
          ),
          (
            icon: Icons.article_outlined,
            label: '메뉴',
            active: false,
            onTap: null,
          ),
        ];

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final item in items)
              Expanded(
                child: InkWell(
                  onTap: item.onTap,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          size: 18,
                          color: item.active
                              ? const Color(0xFF1F1B1A)
                              : Colors.black.withValues(alpha: 0.42),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: item.active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: item.active
                                ? const Color(0xFF1F1B1A)
                                : Colors.black.withValues(alpha: 0.42),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrimaryNavigation() {
    if (widget.hideBottomNav) return const SizedBox.shrink();
    final items =
        <
          ({
            IconData? fallbackIcon,
            String? fallbackAssetPath,
            String activeAssetPath,
            String inactiveAssetPath,
            String label,
            bool active,
            VoidCallback onTap,
          })
        >[
          (
            fallbackIcon: Icons.home_filled,
            fallbackAssetPath: null,
            activeAssetPath: 'assets/icon/home.png',
            inactiveAssetPath: 'assets/icon/home_un.png',
            label: '홈',
            active: _selectedBottomNavIndex == 0,
            onTap: () => setState(() {
              _selectedBottomNavIndex = 0;
              _showWelcomeScreen = true;
              _showArchiveScreen = false;
              _archiveOpenedFromChat = false;
            }),
          ),
          (
            fallbackIcon: null,
            fallbackAssetPath: 'assets/icon/Widget_add.png',
            activeAssetPath: 'assets/icon/device.png',
            inactiveAssetPath: 'assets/icon/device_un.png',
            label: '디바이스',
            active: _selectedBottomNavIndex == 1,
            onTap: () => setState(() {
              _selectedBottomNavIndex = 1;
              _showWelcomeScreen = true;
              _showArchiveScreen = false;
              _archiveOpenedFromChat = false;
            }),
          ),
          (
            fallbackIcon: null,
            fallbackAssetPath: 'assets/icon/AI.png',
            activeAssetPath: 'assets/icon/ai.png',
            inactiveAssetPath: 'assets/icon/ai_un.png',
            label: '챗봇',
            active: _selectedBottomNavIndex == 2,
            onTap: _openChatHome,
          ),
          (
            fallbackIcon: null,
            fallbackAssetPath: 'assets/icon/Line_up.png',
            activeAssetPath: 'assets/icon/care.png',
            inactiveAssetPath: 'assets/icon/care_un.png',
            label: '케어',
            active: _selectedBottomNavIndex == 3,
            onTap: () => setState(() {
              _selectedBottomNavIndex = 3;
              _showWelcomeScreen = true;
              _showArchiveScreen = false;
              _archiveOpenedFromChat = false;
            }),
          ),
          (
            fallbackIcon: null,
            fallbackAssetPath: 'assets/icon/Chart.png',
            activeAssetPath: 'assets/icon/menu.png',
            inactiveAssetPath: 'assets/icon/menu_un.png',
            label: '메뉴',
            active: _selectedBottomNavIndex == 4,
            onTap: () => setState(() {
              _selectedBottomNavIndex = 4;
              _showWelcomeScreen = true;
              _showArchiveScreen = false;
              _archiveOpenedFromChat = false;
            }),
          ),
        ];

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (final item in items)
              Expanded(
                child: InkWell(
                  onTap: item.onTap,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _BottomNavAssetIcon(
                          active: item.active,
                          activeAssetPath: item.activeAssetPath,
                          inactiveAssetPath: item.inactiveAssetPath,
                          fallbackAssetPath: item.fallbackAssetPath,
                          fallbackIcon: item.fallbackIcon,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: item.active
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: item.active
                                ? const Color(0xFF1F1B1A)
                                : Colors.black.withValues(alpha: 0.42),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatIntroPanel() {
    final isIdle = _assistantMode == AssistantMode.idle;

    if (_isSubmitting) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 32, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: Color(0xFFDFDFDF),
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: Image.asset(
                    _characterAssetForMode(AssistantMode.audio),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '해결방법을 생각 중이에요',
                style: TextStyle(
                  color: Color(0xFFFF937E),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.33,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF937E).withValues(alpha: 0.60),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF7469).withValues(alpha: 0.60),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5555).withValues(alpha: 0.60),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // 오디오 녹음 중 화면
    if (_isRecordingActive) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 32, 12, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 165,
                height: 165,
                decoration: const BoxDecoration(
                  color: Color(0xFFDFDFDF),
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: Image.asset(
                    _characterAssetForMode(AssistantMode.audio),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '소리를 듣고 있어요.\n정확한 진단을 위해\n주변 소음을 차단해주세요.',
                    style: TextStyle(
                      color: Color(0xFFFF937E),
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.44,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 32, 12, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  color: Color(0xFFDFDFDF),
                  shape: BoxShape.circle,
                ),
                child: ClipOval(
                  child: Image.asset(
                    _characterAssetForMode(_assistantMode),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isIdle
                  ? '안녕하세요, $_displayName님!\n고장·AS 전용 상담사 REBO 에요.\n어떤 문제가 궁금하신가요?'
                  : _modePresentation.title,
              style: TextStyle(
                color: isIdle
                    ? const Color(0xFF212121)
                    : const Color(0xFFFF937E),
                fontSize: isIdle ? 14 : 18,
                fontWeight: FontWeight.w600,
                height: 1.44,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 14, 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.70),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: const Color(0xFFFF937E), width: 1.2),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(
                    Icons.photo_camera_outlined,
                    size: 13,
                    color: Color(0xFFEB4C4C),
                  ),
                  SizedBox(width: 5),
                  Text(
                    '사진/음성으로 더 정확한 진단이 가능해요',
                    style: TextStyle(
                      color: Color(0xFFEB4C4C),
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSheet(String title, Widget child) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;

        return Padding(
          padding: EdgeInsets.fromLTRB(16, 24, 16, bottomInset + 16),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF191919),
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
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                child,
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openSettings() {
    return _showSheet(
      '연결 설정',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '안드로이드 에뮬레이터는 보통 10.0.2.2, iOS 시뮬레이터는 보통 127.0.0.1을 사용합니다. '
            '실제 휴대폰에서는 같은 Wi-Fi에 있는 PC의 IP 주소를 입력해주세요.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _baseUrlController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              fillColor: Colors.white.withValues(alpha: 0.08),
              hintText: 'http://192.168.0.13:8000',
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
      SizedBox(
        height: math.min(MediaQuery.of(context).size.height * 0.58, 480),
        child: SingleChildScrollView(
          child: SelectableText(
            _latestEvidence ?? '아직 분석 근거가 없습니다.',
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

  List<Widget> _buildAttachmentChips() {
    final chips = <Widget>[];

    if (_selectedImage != null) {
      chips.add(
        SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F1F1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.06),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(_selectedImage!, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: -4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedImage = null;
                          _selectedImageName = null;
                        });
                      },
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.42),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 68,
                child: Text(
                  _selectedImageName ?? '첨부 이미지',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildAudioCard({
      required String name,
      required IconData icon,
      required VoidCallback onDelete,
    }) {
      return SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(icon, size: 16, color: const Color(0xFF999999)),
                          const Icon(
                            Icons.open_in_full_rounded,
                            size: 14,
                            color: Color(0xFF222222),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 2),
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF5D5B5B),
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: -4,
                  right: -4,
                  child: GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.42),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (_selectedAudioName != null) {
      chips.add(
        buildAudioCard(
          name: _selectedAudioName!,
          icon: Icons.audio_file_rounded,
          onDelete: () => setState(() {
            _selectedAudio = null;
            _selectedAudioName = null;
          }),
        ),
      );
    }

    if (_recordedVoiceName != null) {
      chips.add(
        buildAudioCard(
          name: _recordedVoiceName!,
          icon: Icons.mic_rounded,
          onDelete: () => setState(() {
            _recordedVoice = null;
            _recordedVoiceName = null;
          }),
        ),
      );
    }

    if (_recordedNoiseName != null) {
      chips.add(
        buildAudioCard(
          name: _recordedNoiseName!,
          icon: Icons.graphic_eq_rounded,
          onDelete: () => setState(() {
            _recordedNoise = null;
            _recordedNoiseName = null;
          }),
        ),
      );
    }

    return chips;
  }

  Widget _buildBubble(
    String message, {
    required bool isUser,
    String? imagePath,
    String? imageName,
  }) {
    final foreground = isUser
        ? const Color(0xFF5D5B5B)
        : const Color(0xFF312726);
    final displayMessage = isUser && imagePath != null
        ? _stripDisplayedImageAttachmentLine(message)
        : message;
    final baseTextStyle = TextStyle(
      color: foreground,
      fontSize: 13,
      height: 1.48,
      fontWeight: FontWeight.w500,
    );

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            if (isUser && imagePath != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.file(
                  File(imagePath),
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 6),
            ],
            if (displayMessage.isNotEmpty)
              if (isUser)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(10),
                      topRight: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                    ),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: _buildMessageTextSpans(
                        message: displayMessage,
                        baseStyle: baseTextStyle,
                      ),
                    ),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: _buildMessageTextSpans(
                          message: displayMessage,
                          baseStyle: baseTextStyle,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () {
                        if (_autoSpeak) {
                          _stopSpeaking();
                          setState(() => _autoSpeak = false);
                        } else {
                          setState(() => _autoSpeak = true);
                          _speakText(message);
                        }
                      },
                      child: Icon(
                        _autoSpeak
                            ? Icons.volume_up_rounded
                            : Icons.volume_off_rounded,
                        size: 18,
                        color: const Color(0xFF212121).withValues(alpha: 0.40),
                      ),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroPanel() {
    final presentation = _modePresentation;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            presentation.gradientColors.first,
            presentation.gradientColors.last,
            const Color(0xFFFFFBF8),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.84)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16000000),
            blurRadius: 18,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      presentation.label,
                      style: TextStyle(
                        color: Colors.black.withValues(alpha: 0.35),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _serverHealthy
                                  ? const Color(0xFF25B069)
                                  : const Color(0xFFE4664B),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _isCheckingConnection ? '백엔드 확인 중' : _serverStatus,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 4,
                children: [
                  _HeroActionButton(
                    tooltip: _autoSpeak ? '음성 읽기 끄기' : '음성 읽기 켜기',
                    icon: _autoSpeak
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    active: _autoSpeak,
                    onPressed: () {
                      setState(() => _autoSpeak = !_autoSpeak);
                      if (!_autoSpeak) {
                        unawaited(_stopSpeaking());
                      }
                    },
                  ),
                  _HeroActionButton(
                    tooltip: '연결 설정',
                    icon: Icons.tune_rounded,
                    onPressed: _openSettings,
                  ),
                  _HeroActionButton(
                    tooltip: '분석 근거',
                    icon: Icons.data_object_rounded,
                    onPressed: _latestEvidence == null ? null : _openEvidence,
                  ),
                  _HeroActionButton(
                    tooltip: '대화 초기화',
                    icon: Icons.refresh_rounded,
                    onPressed: _resetConversation,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: SizedBox(
                key: ValueKey(_assistantMode),
                height: 156,
                child: RobotIllustration(mode: _assistantMode),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            presentation.title,
            style: const TextStyle(
              fontSize: 20,
              height: 1.22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            presentation.description,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: Colors.black.withValues(alpha: 0.58),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1ED),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF3C7BC)),
      ),
      child: Text(
        _errorMessage!,
        style: const TextStyle(
          color: Color(0xFF8C3A2A),
          fontWeight: FontWeight.w700,
          height: 1.45,
        ),
      ),
    );
  }

  Widget _buildStarterPanel() {
    final suggestions = <String>[
      '냉장고에서 덜컹거리는 소리가 나요.',
      '세탁기 탈수 중에 심하게 흔들리고 쿵쿵거려요.',
      '에어컨에서 물 떨어지는 소리와 함께 냄새가 나요.',
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE8E3),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '빠르게 시작하기',
                style: TextStyle(
                  color: _modePresentation.accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '자주 묻는 증상',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            for (final suggestion in suggestions) ...[
              InkWell(
                onTap: () => _messageController.text = suggestion,
                borderRadius: BorderRadius.circular(22),
                child: Ink(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBF8),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Text(
                    suggestion,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6F3),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '+ 버튼으로 할 수 있는 일',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 10),
                  Text('사진 촬영, 갤러리 가져오기, 음성 녹음, 음성 파일 가져오기를 한 번에 열 수 있어요.'),
                ],
              ),
            ),
            if (_isSubmitting) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                    Text(
                      '답변을 작성중이에요...',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const _asCategories = [
    '양문형 냉장고',
    '일반형 냉장고',
    '상냉장 / 하냉동',
    '정수기형 냉장고',
    '스탠드형 김치냉장고',
    '뚜껑형 김치냉장고',
    '와인셀러',
  ];

  bool _isAfterCategoryOrSerial(String userMsg) {
    if (userMsg.startsWith('시리얼 넘버:')) return true;
    return _asCategories.any((cat) => userMsg.trim() == cat);
  }

  static const _asRequestKeywords = [
    'as',
    'a/s',
    'as신청',
    'a/s신청',
    'as 신청',
    'a/s 신청',
    '서비스신청',
    '서비스 신청',
    '수리신청',
    '수리 신청',
    '출장신청',
    '출장 신청',
    '출장서비스',
    '출장 서비스',
    '기사신청',
    '기사 신청',
    '방문수리',
    '방문 수리',
    '수리요청',
    '수리 요청',
    'as요청',
    'as 요청',
  ];

  bool _isAsRequestMessage(String msg) {
    final normalized = msg.trim().toLowerCase();
    return _asRequestKeywords.any(
      (kw) => normalized == kw || normalized.contains(kw),
    );
  }

  Widget _buildAsRoutingResponse() {
    Widget chip(String label, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: const Color(0xFFFF937E), width: 1.2),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFEB4C4C),
              fontSize: 12,
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          _characterAssetForMode(AssistantMode.idle),
          width: 80,
          height: 80,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 16),
        const Text(
          'AS 신청이 필요하시군요!\n그 전에 자가점검은 어떠신가요?',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.44,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          '아직 자가점검을 해보지 않으셨다면, 이 단계를 우선 추천드려요. 자가점검을 통해 해결이 가능한 문제를 돕고, 필요한 AS 데이터를 자동으로 상담원 혹은 기사님께 전해드려요.',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.57,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '어떤 해결방법으로 진행하시겠어요?',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.43,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            chip('자가점검', () {
              setState(() {
                _history = [
                  ..._history,
                  const ChatTurn(user: '자가점검', assistant: '__SELF_CHECK__'),
                ];
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              });
            }),
            const SizedBox(width: 6),
            chip('서비스 전문 상담', () {
              setState(() {
                _history = [
                  ..._history,
                  const ChatTurn(
                    user: '서비스 전문 상담',
                    assistant: '__SERVICE_CONSULT__',
                  ),
                ];
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              });
            }),
            const SizedBox(width: 6),
            chip('출장 서비스 예약', () {
              setState(() {
                _history = [
                  ..._history,
                  const ChatTurn(
                    user: '출장 서비스 예약',
                    assistant: '__VISIT_SERVICE__',
                  ),
                ];
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              });
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildSelfCheckResponse() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text(
          '자가점검을 도와드릴게요!',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 18,
            fontWeight: FontWeight.w600,
            height: 1.44,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '자가점검하는 방법은 다음과 같습니다.\n우선, 현재 수리가 필요한 제품의 카테고리 혹은 제품명과 함께 에러코드, 문제상황을 알려주세요.',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.57,
          ),
        ),
      ],
    );
  }

  Widget _buildServiceConsultResponse() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '서비스 전문 상담을 도와드릴게요!',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.44,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '서비스 전문 상담을 예약하실 수 있도록 도와드리겠습니다. 다음 링크를 통해 서비스 전문 상담을 진행하실 수 있어요.',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.57,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            _messageController.text = '서비스 전문 상담';
            _sendMessage();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.70),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: const Color(0xFFFF937E), width: 1.2),
            ),
            child: const Text(
              '서비스 전문 상담',
              style: TextStyle(
                color: Color(0xFFEB4C4C),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVisitServiceResponse() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '출장 서비스 예약을 도와드릴게요!',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            height: 1.44,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '출장 서비스 예약을 예약하실 수 있도록 도와드리겠습니다. 다음 링크를 통해 출장 서비스 예약을 진행하실 수 있어요.',
          style: TextStyle(
            color: Color(0xFF212121),
            fontSize: 14,
            fontWeight: FontWeight.w400,
            height: 1.57,
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            _messageController.text = '출장 서비스 예약';
            _sendMessage();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.70),
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: const Color(0xFFFF937E), width: 1.2),
            ),
            child: const Text(
              '출장 서비스 예약',
              style: TextStyle(
                color: Color(0xFFEB4C4C),
                fontSize: 12,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuggestionChip(String label, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.70),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: const Color(0xFFFF937E), width: 1.2),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFEB4C4C),
            fontSize: 13,
            fontWeight: FontWeight.w400,
            height: 1.43,
          ),
        ),
      ),
    );
  }

  void _showCategorySheet() {
    const categories = [
      '양문형 냉장고',
      '일반형 냉장고',
      '상냉장 / 하냉동',
      '정수기형 냉장고',
      '스탠드형 김치냉장고',
      '뚜껑형 김치냉장고',
      '와인셀러',
    ];

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF8),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '세부 카테고리 선택',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF212121),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '수현님의 냉장고를 선택해주세요.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF5D5B5B)),
                ),
                const SizedBox(height: 16),
                ...categories.map(
                  (cat) => InkWell(
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      _messageController.text = cat;
                      _sendMessage();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 4,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              cat,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF212121),
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: Color(0xFFFF937E),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSerialNumberSheet() {
    final controller = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(14, 24, 14, bottomInset + 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF8),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '시리얼 넘버(S/N) 입력',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF212121),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '제품 뒷면 또는 측면 스티커에서 확인할 수 있어요.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.black.withValues(alpha: 0.52),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'S/N 번호를 입력하세요',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFFF937E)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.black.withValues(alpha: 0.12),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: Color(0xFFFF937E),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      final sn = controller.text.trim();
                      if (sn.isNotEmpty) {
                        Navigator.of(sheetContext).pop();
                        _messageController.text = '시리얼 넘버: $sn';
                        _sendMessage();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFF937E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      '입력 완료',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildConversationPanel() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      children: [
        // 새 채팅 유도 배너
        GestureDetector(
          onTap: _resetConversation,
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFF937E).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF937E).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.add_comment_outlined,
                  size: 16,
                  color: Color(0xFFFF937E),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '다른 증상을 진단하려면 새 채팅을 시작하세요',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFFF937E),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const Text(
                  '새 채팅 →',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFFFF937E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        for (var index = 0; index < _history.length; index++) ...[
          _buildBubble(
            _history[index].user,
            isUser: true,
            imagePath: _history[index].userImagePath,
            imageName: _history[index].userImageName,
          ),
          if (_history[index].assistant.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            if (_history[index].assistant == '__AS_ROUTING__') ...[
              _buildAsRoutingResponse(),
            ] else if (_history[index].assistant == '__SELF_CHECK__') ...[
              _buildSelfCheckResponse(),
            ] else if (_history[index].assistant == '__SERVICE_CONSULT__') ...[
              _buildServiceConsultResponse(),
            ] else if (_history[index].assistant == '__VISIT_SERVICE__') ...[
              _buildVisitServiceResponse(),
            ] else ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Image.asset(
                  _characterAssetForMode(AssistantMode.idle),
                  width: 80,
                  height: 80,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 12),
              _buildBubble(_history[index].assistant, isUser: false),
            ],
            // 마지막 응답이고, 텍스트만 입력한 경우(이미지/오디오 없음) 제안 칩 표시
            if (index == _history.length - 1 &&
                !_isSubmitting &&
                _serviceRoutingStep == ServiceRoutingStep.none &&
                _history[index].userImagePath == null &&
                _history[index].assistant != '__AS_ROUTING__' &&
                _history[index].assistant != '__SELF_CHECK__' &&
                _history[index].assistant != '__SERVICE_CONSULT__' &&
                _history[index].assistant != '__VISIT_SERVICE__') ...[
              const SizedBox(height: 12),
              if (_isAfterCategoryOrSerial(_history[index].user)) ...[
                // AS 안내 텍스트
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBF8),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'AS 신청이 필요하시군요!\n아직 자가점검을 해보지 않으셨다면, 이 단계를 우선 추천드려요. 자가점검을 통해 해결이 가능한 문제를 돕고, 필요한 AS 데이터를 자동으로 상담원 혹은 기사님께 전해드려요.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF5D5B5B),
                      height: 1.5,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildSuggestionChip(
                      '상담사 연결',
                      onTap: () {
                        _messageController.text = '상담사 연결해줘';
                        _sendMessage();
                      },
                    ),
                    _buildSuggestionChip(
                      'A/S 신청',
                      onTap: () {
                        setState(() {
                          _history = [
                            ..._history,
                            const ChatTurn(
                              user: 'A/S 신청',
                              assistant: '__AS_ROUTING__',
                            ),
                          ];
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _scrollController.animateTo(
                            _scrollController.position.maxScrollExtent,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                          );
                        });
                      },
                    ),
                  ],
                ),
              ] else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildSuggestionChip(
                      '세부 카테고리 선택',
                      onTap: _showCategorySheet,
                    ),
                    _buildSuggestionChip(
                      '시리얼 넘버(S/N) 찾기',
                      onTap: _showSerialNumberSheet,
                    ),
                  ],
                ),
              ],
            ],
          ],
          if (index == _history.length - 1 &&
              _serviceRoutingStep != ServiceRoutingStep.none) ...[
            const SizedBox(height: 10),
            _buildServiceRoutingPanel(),
          ],
          const SizedBox(height: 14),
        ],
        if (_isSubmitting)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Builder(
              builder: (context) {
                final hasImage =
                    _history.isNotEmpty && _history.last.userImagePath != null;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: Color(0xFFDFDFDF),
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          _characterAssetForMode(AssistantMode.audio),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    if (hasImage) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_history.last.userImagePath!),
                          width: 98,
                          height: 98,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      hasImage
                          ? '사진을 분석중이에요\n정확한 진단을 위해 조금만 기다려주세요'
                          : '해결방법을 생각 중이에요\n정확한 진단을 위해 조금만 기다려주세요',
                      style: const TextStyle(
                        color: Color(0xFFFF937E),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.33,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFF937E,
                            ).withValues(alpha: 0.60),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFF7469,
                            ).withValues(alpha: 0.60),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFFFF5555,
                            ).withValues(alpha: 0.60),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildServiceRoutingPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF2DDD7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_serviceRoutingStep == ServiceRoutingStep.askDiagnosis) ...[
            const Text(
              'AI 진단을 먼저 해보시겠어요?',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              '증상을 먼저 확인하면 더 알맞은 다음 도움을 드릴 수 있어요.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: Colors.black.withValues(alpha: 0.54),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '바로 연결을 원하시면 아래에서 선택하고, 먼저 상태를 확인하고 싶으면 AI 진단을 시작해보세요.',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: Colors.black.withValues(alpha: 0.54),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _isSubmitting
                        ? null
                        : _startAiDiagnosisFromRouting,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFFFFECE8),
                      foregroundColor: const Color(0xFF9C3F36),
                    ),
                    child: const Text('예'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(
                            () => _serviceRoutingStep =
                                ServiceRoutingStep.chooseService,
                          ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: Colors.black.withValues(alpha: 0.7),
                      side: BorderSide(
                        color: Colors.black.withValues(alpha: 0.12),
                      ),
                    ),
                    child: const Text('아니오'),
                  ),
                ),
              ],
            ),
          ] else ...[
            const Text(
              '필요한 도움을 선택해보세요.',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isSubmitting
                        ? null
                        : () => _handleServiceActionSelection('상담사 연결'),
                    icon: const Icon(Icons.support_agent_rounded, size: 18),
                    label: const Text('상담사 연결'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFFFFECE8),
                      foregroundColor: const Color(0xFF9C3F36),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isSubmitting
                        ? null
                        : () => _handleServiceActionSelection('출장서비스 예약'),
                    icon: const Icon(
                      Icons.home_repair_service_rounded,
                      size: 18,
                    ),
                    label: const Text('출장서비스 예약'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: const Color(0xFFFFF3E8),
                      foregroundColor: const Color(0xFF9B5A20),
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _isSubmitting ? null : _startAiDiagnosisFromRouting,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF9C3F36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 4,
                  ),
                ),
                child: const Text('먼저 AI 진단해보기'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final chips = _buildAttachmentChips();
    final canSend = _canSend && !_isSubmitting;

    return Container(
      padding: const EdgeInsets.fromLTRB(19, 8, 19, 12),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(spacing: 6, runSpacing: 6, children: chips),
                ),
              ),
            _isRecordingActive
                ? _buildRecordingComposer()
                : SizedBox(
                    height: 42,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x12000000),
                            blurRadius: 16,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: _isSubmitting ? null : _openAttachmentSheet,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Image.asset(
                                'assets/icon/1.png',
                                width: 18,
                                height: 18,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              enabled: !_isSubmitting,
                              textAlignVertical: TextAlignVertical.center,
                              minLines: 1,
                              maxLines: 4,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                height: 1.45,
                              ),
                              decoration: InputDecoration(
                                hintText: _modePresentation.hintText,
                                hintStyle: _composerPlaceholderStyle,
                                filled: false,
                                fillColor: Colors.transparent,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 0,
                                  vertical: 0,
                                ),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                              ),
                            ),
                          ),
                          if (_isSubmitting)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _stopSubmittingResponse,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: 6,
                                  right: 6,
                                ),
                                child: Image.asset(
                                  'assets/icon/stop.png',
                                  width: 18,
                                  height: 18,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            )
                          else ...[
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (_) =>
                                  setState(() => _isMicButtonPressed = true),
                              onTapCancel: () {
                                if (_isMicButtonPressed && mounted) {
                                  setState(() => _isMicButtonPressed = false);
                                }
                              },
                              onTapUp: (_) {
                                if (_isMicButtonPressed && mounted) {
                                  setState(() => _isMicButtonPressed = false);
                                }
                              },
                              onTap: _handleMicTap,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                ),
                                child: Image.asset(
                                  _isMicButtonPressed
                                      ? 'assets/icon/mic.png'
                                      : 'assets/icon/mic_non.png',
                                  width: 18,
                                  height: 18,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: canSend ? _sendMessage : null,
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  left: 2,
                                  right: 6,
                                ),
                                child: Image.asset(
                                  canSend
                                      ? 'assets/icon/send.png'
                                      : 'assets/icon/send_non.png',
                                  width: 18,
                                  height: 18,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordingComposer() {
    final accent = _isRecordingVoice
        ? const Color(0xFFCA4156)
        : const Color(0xFFE07A00);
    final title = _isRecordingVoice ? '말하기 녹음 중' : '소음 녹음 중';
    final subtitle = _isRecordingVoice
        ? '말한 내용을 텍스트로 바꿔요'
        : '제품 소리를 분석용으로 저장해요';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFFF4F1EE),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _isRecordingVoice ? Icons.mic_rounded : Icons.graphic_eq_rounded,
              color: accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatRecordingElapsed(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.25,
                    color: Colors.black.withValues(alpha: 0.46),
                  ),
                ),
                const SizedBox(height: 8),
                _RecordingWaveform(seed: _recordingWaveSeed, color: accent),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _RecordingActionButton(
            tooltip: '녹음 종료',
            icon: Icons.stop_rounded,
            fillColor: accent.withValues(alpha: 0.12),
            iconColor: accent,
            onPressed: _handleMicTap,
          ),
          const SizedBox(width: 8),
          _RecordingActionButton(
            tooltip: '녹음 취소',
            icon: Icons.close_rounded,
            fillColor: const Color(0xFFF6F4F2),
            iconColor: Colors.black.withValues(alpha: 0.62),
            onPressed: _cancelActiveRecording,
          ),
        ],
      ),
    );
  }

  Widget _buildChatScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFFFCEDEB),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        titleSpacing: 19,
        title: const Text(
          'Chat REBO',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF212121),
          ),
        ),
        actions: [
          if (_history.isNotEmpty)
            GestureDetector(
              onTap: _resetConversation,
              child: Container(
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF937E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  '새 채팅',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFFF937E),
                  ),
                ),
              ),
            ),
          _TopBarIconButton(
            tooltip: '보관함',
            onPressed: _openArchiveScreen,
            child: const _ArchiveOutlineIcon(),
          ),
          const SizedBox(width: 2),
          _TopBarIconButton(
            tooltip: '채팅 닫기',
            onPressed: () => setState(() {
              _showWelcomeScreen = true;
              _showArchiveScreen = false;
            }),
            child: const _CloseOutlineIcon(),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Stack(
        children: [
          // 배경 블러 원 (좌측)
          Positioned(
            left: -120,
            top: MediaQuery.of(context).size.height * 0.05,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFCAEB2).withValues(alpha: 0.60),
                      const Color(0xFFFCBABD).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 배경 블러 원 (우측)
          Positioned(
            right: -120,
            top: MediaQuery.of(context).size.height * 0.5,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFFFCAEB2).withValues(alpha: 0.60),
                      const Color(0xFFFCBABD).withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      _history.isEmpty ? 12 : 4,
                      16,
                      0,
                    ),
                    child: Column(
                      children: [
                        if (_errorMessage != null) ...[
                          _buildErrorCard(),
                          const SizedBox(height: 10),
                        ],
                        Expanded(
                          child: (_isRecordingActive || _history.isEmpty)
                              ? _buildChatIntroPanel()
                              : _buildConversationPanel(),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildComposerDisclaimer(),
                const SizedBox(height: 7),
                _buildComposer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showArchiveScreen) {
      return _buildArchiveScreen();
    }
    return _showWelcomeScreen ? _buildWelcomeScreen() : _buildChatScreen();
  }
}

class ArchiveSessionSummary {
  const ArchiveSessionSummary({
    required this.id,
    required this.userId,
    required this.productId,
    required this.title,
    required this.summary,
    required this.status,
    required this.lastMessageAt,
  });

  final int id;
  final int userId;
  final int? productId;
  final String title;
  final String summary;
  final String status;
  final String? lastMessageAt;

  factory ArchiveSessionSummary.fromJson(Map<dynamic, dynamic> json) {
    return ArchiveSessionSummary(
      id: (json['id'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      productId: (json['product_id'] as num?)?.toInt(),
      title: json['title']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      lastMessageAt: json['last_message_at']?.toString(),
    );
  }
}

class ArchiveMessage {
  const ArchiveMessage({
    required this.id,
    required this.sessionId,
    required this.role,
    required this.messageType,
    required this.content,
    required this.attachmentNames,
    required this.createdAt,
  });

  final int id;
  final int sessionId;
  final String role;
  final String messageType;
  final String content;
  final List<String> attachmentNames;
  final String? createdAt;

  factory ArchiveMessage.fromJson(Map<dynamic, dynamic> json) {
    final attachmentNames = <String>[];
    final rawAttachments = json['attachments'];
    if (rawAttachments is Map) {
      final rawItems = rawAttachments['items'];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map) {
            final fileName = item['file_name']?.toString().trim();
            if (fileName != null && fileName.isNotEmpty) {
              attachmentNames.add(fileName);
            }
          }
        }
      }
    }

    return ArchiveMessage(
      id: (json['id'] as num?)?.toInt() ?? 0,
      sessionId: (json['session_id'] as num?)?.toInt() ?? 0,
      role: json['role']?.toString() ?? 'user',
      messageType: json['message_type']?.toString() ?? 'text',
      content: json['content']?.toString() ?? '',
      attachmentNames: List.unmodifiable(attachmentNames),
      createdAt: json['created_at']?.toString(),
    );
  }
}

class _ModePresentation {
  const _ModePresentation({
    required this.label,
    required this.title,
    required this.description,
    required this.hintText,
    required this.gradientColors,
    required this.accent,
  });

  final String label;
  final String title;
  final String description;
  final String hintText;
  final List<Color> gradientColors;
  final Color accent;
}

class _HeroActionButton extends StatelessWidget {
  const _HeroActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.active = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? const Color(0xFFFFE6DD)
            : Colors.white.withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(width: 32, height: 32, child: Icon(icon, size: 16)),
        ),
      ),
    );
  }
}

class _AttachmentActionTile extends StatelessWidget {
  const _AttachmentActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.74),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black.withValues(alpha: 0.62),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AttachmentQuickAction extends StatelessWidget {
  const _AttachmentQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7F7F7),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 24, color: const Color(0xFF5D5B5B)),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF5D5B5B),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RobotIllustration extends StatelessWidget {
  const RobotIllustration({super.key, required this.mode});

  final AssistantMode mode;

  @override
  Widget build(BuildContext context) {
    final imagePath = switch (mode) {
      AssistantMode.idle => 'assets/characters/idle.png',
      AssistantMode.audio => 'assets/characters/audio.png',
      AssistantMode.photo => 'assets/characters/photo.png',
      AssistantMode.replying => 'assets/characters/replying.png',
      AssistantMode.maincharacter => 'assets/characters/rebo_Image.png',
    };

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 146,
          height: 146,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFD6DE), Color(0xFFFFEFF4)],
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18D96C70),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
        ),
        Image.asset(imagePath, width: 148, height: 148, fit: BoxFit.contain),
      ],
    );
  }
}

class _RobotAntennae extends StatelessWidget {
  const _RobotAntennae({required this.mode});

  final AssistantMode mode;

  @override
  Widget build(BuildContext context) {
    final tilt = switch (mode) {
      AssistantMode.audio => 0.2,
      AssistantMode.replying => -0.08,
      _ => 0.0,
    };

    return SizedBox(
      width: 112,
      height: 34,
      child: Stack(
        children: [
          Positioned(
            left: 18,
            top: 0,
            child: Transform.rotate(
              angle: -0.22 + tilt,
              child: const _AntennaStem(),
            ),
          ),
          Positioned(
            right: 18,
            top: 0,
            child: Transform.rotate(
              angle: 0.22 + tilt,
              child: const _AntennaStem(),
            ),
          ),
        ],
      ),
    );
  }
}

class _AntennaStem extends StatelessWidget {
  const _AntennaStem();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 10,
      height: 34,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(
            top: 7,
            child: Container(
              width: 2.4,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFF69483B),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFE63C3D),
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _RobotHead extends StatelessWidget {
  const _RobotHead({required this.mode});

  final AssistantMode mode;

  @override
  Widget build(BuildContext context) {
    final faceBorder = switch (mode) {
      AssistantMode.replying => const Color(0xFF2A1A1A),
      _ => const Color(0xFF1B1313),
    };

    return SizedBox(
      width: 134,
      height: 108,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Positioned(left: 0, child: _RobotEar()),
          const Positioned(right: 0, child: _RobotEar()),
          Container(
            width: 118,
            height: 96,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFF7062), Color(0xFFE84A45)],
              ),
              borderRadius: BorderRadius.circular(34),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26D9514C),
                  blurRadius: 20,
                  offset: Offset(0, 12),
                ),
              ],
            ),
          ),
          Container(
            width: 84,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF131313),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: faceBorder, width: 2),
            ),
            child: CustomPaint(painter: _RobotFacePainter(mode)),
          ),
        ],
      ),
    );
  }
}

class _RobotEar extends StatelessWidget {
  const _RobotEar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: const BoxDecoration(
        color: Color(0xFFE84A45),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 8,
          height: 15,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }
}

class _RobotBody extends StatelessWidget {
  const _RobotBody({required this.mode});

  final AssistantMode mode;

  @override
  Widget build(BuildContext context) {
    final leftAngle = switch (mode) {
      AssistantMode.audio => -1.05,
      AssistantMode.photo => -0.42,
      AssistantMode.replying => -0.1,
      AssistantMode.idle => -0.55,
      AssistantMode.maincharacter => -0.55,
    };

    final rightAngle = switch (mode) {
      AssistantMode.audio => 1.05,
      AssistantMode.photo => 0.25,
      AssistantMode.replying => 0.62,
      AssistantMode.idle => 0.55,
      AssistantMode.maincharacter => 0.55,
    };

    return SizedBox(
      width: 122,
      height: 96,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned(left: 10, top: 8, child: _RobotArm(angle: leftAngle)),
          Positioned(right: 10, top: 8, child: _RobotArm(angle: rightAngle)),
          Positioned(
            top: 0,
            child: Container(
              width: 74,
              height: 88,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFFF7268), Color(0xFFE14A48)],
                ),
                borderRadius: BorderRadius.circular(28),
              ),
              child: Center(
                child: Container(
                  width: 24,
                  height: 74,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
            ),
          ),
          const Positioned(
            bottom: 0,
            child: Row(
              children: [_RobotFoot(), SizedBox(width: 20), _RobotFoot()],
            ),
          ),
        ],
      ),
    );
  }
}

class _RobotArm extends StatelessWidget {
  const _RobotArm({required this.angle});

  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 18,
        height: 56,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Container(
              width: 10,
              height: 42,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF60433B), Color(0xFF2D2422)],
                ),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Positioned(
              top: 34,
              child: Container(
                width: 18,
                height: 18,
                decoration: const BoxDecoration(
                  color: Color(0xFFE74C47),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: Color(0xFF342925),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RobotFoot extends StatelessWidget {
  const _RobotFoot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 8,
      decoration: BoxDecoration(
        color: const Color(0xFF2F2725),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _RobotFacePainter extends CustomPainter {
  const _RobotFacePainter(this.mode);

  final AssistantMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    final eyePaint = Paint()..color = Colors.white;
    final stroke = Paint()
      ..color = const Color(0xFFFFB3A8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;

    switch (mode) {
      case AssistantMode.idle:
      case AssistantMode.maincharacter:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width * 0.18, size.height * 0.28, 10, 18),
            const Radius.circular(99),
          ),
          eyePaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width * 0.68, size.height * 0.28, 10, 18),
            const Radius.circular(99),
          ),
          eyePaint,
        );
        final smile = Path()
          ..moveTo(size.width * 0.39, size.height * 0.62)
          ..quadraticBezierTo(
            size.width * 0.5,
            size.height * 0.72,
            size.width * 0.61,
            size.height * 0.62,
          );
        canvas.drawPath(smile, stroke);
      case AssistantMode.audio:
        canvas.drawArc(
          Rect.fromLTWH(size.width * 0.22, size.height * 0.3, 14, 12),
          math.pi,
          math.pi,
          false,
          stroke,
        );
        canvas.drawArc(
          Rect.fromLTWH(size.width * 0.6, size.height * 0.3, 14, 12),
          math.pi,
          math.pi,
          false,
          stroke,
        );
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(size.width * 0.5, size.height * 0.62),
            width: 20,
            height: 16,
          ),
          Paint()..color = const Color(0xFFFF8A8D),
        );
      case AssistantMode.photo:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width * 0.2, size.height * 0.29, 11, 17),
            const Radius.circular(99),
          ),
          eyePaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(size.width * 0.68, size.height * 0.29, 11, 17),
            const Radius.circular(99),
          ),
          eyePaint,
        );
        final mouth = Path()
          ..moveTo(size.width * 0.43, size.height * 0.62)
          ..lineTo(size.width * 0.57, size.height * 0.62);
        canvas.drawPath(mouth, stroke);
      case AssistantMode.replying:
        canvas.drawArc(
          Rect.fromLTWH(size.width * 0.2, size.height * 0.36, 12, 8),
          0,
          math.pi,
          false,
          stroke,
        );
        canvas.drawArc(
          Rect.fromLTWH(size.width * 0.6, size.height * 0.36, 12, 8),
          0,
          math.pi,
          false,
          stroke,
        );
        final mouth = Path()
          ..moveTo(size.width * 0.46, size.height * 0.62)
          ..quadraticBezierTo(
            size.width * 0.5,
            size.height * 0.66,
            size.width * 0.54,
            size.height * 0.62,
          );
        canvas.drawPath(mouth, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _RobotFacePainter oldDelegate) {
    return oldDelegate.mode != mode;
  }
}

class _SparkleBadge extends StatelessWidget {
  const _SparkleBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.auto_awesome_rounded, size: 18),
    );
  }
}

class _SoundBadge extends StatelessWidget {
  const _SoundBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.graphic_eq_rounded, size: 22),
    );
  }
}

class _MagnifierBadge extends StatelessWidget {
  const _MagnifierBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        shape: BoxShape.circle,
      ),
      child: const Icon(Icons.search_rounded, size: 30),
    );
  }
}

class _MicBadge extends StatelessWidget {
  const _MicBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Icon(Icons.mic_rounded, size: 22),
    );
  }
}

class _RecordingActionButton extends StatelessWidget {
  const _RecordingActionButton({
    required this.tooltip,
    required this.icon,
    required this.fillColor,
    required this.iconColor,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color fillColor;
  final Color iconColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(color: fillColor, shape: BoxShape.circle),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}

class _RecordingWaveform extends StatelessWidget {
  const _RecordingWaveform({required this.seed, required this.color});

  final int seed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.clamp(0, 260).toDouble();
          final barCount = math.max(18, (availableWidth / 7).floor());

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(barCount, (index) {
              final phase = (seed * 0.38) + (index * 0.72);
              final intensity =
                  ((math.sin(phase) + math.cos(phase * 0.6 + 1.2)) + 2) / 4;
              final height = 5 + (intensity * 17);

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1.5),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: 3,
                  height: height,
                  decoration: BoxDecoration(
                    color: color.withValues(
                      alpha: index.isEven ? 0.95 : 0.45 + (intensity * 0.4),
                    ),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _TopBarIconButton extends StatelessWidget {
  const _TopBarIconButton({
    required this.tooltip,
    required this.onPressed,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (child is _TrashOutlineIcon) {
      return const SizedBox.shrink();
    }

    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      splashRadius: 17,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 9),
      icon: child,
    );
  }
}

class _CloseOutlineIcon extends StatelessWidget {
  const _CloseOutlineIcon();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/chat_close.png',
      width: 17,
      height: 17,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return SizedBox(
          width: 17,
          height: 17,
          child: CustomPaint(painter: _CloseOutlinePainter()),
        );
      },
    );
  }
}

class _TrashOutlineIcon extends StatelessWidget {
  const _TrashOutlineIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 17,
      height: 17,
      child: CustomPaint(painter: _TrashOutlinePainter()),
    );
  }
}

class _ArchiveOutlineIcon extends StatelessWidget {
  const _ArchiveOutlineIcon();

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/icon/chat_arhive.png',
      width: 17,
      height: 17,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        return SizedBox(
          width: 17,
          height: 17,
          child: Icon(
            Icons.inventory_2_outlined,
            size: 17,
            color: const Color(0xFF23201E),
          ),
        );
      },
    );
  }
}

class _BottomNavAssetIcon extends StatelessWidget {
  const _BottomNavAssetIcon({
    required this.activeAssetPath,
    required this.inactiveAssetPath,
    required this.active,
    this.fallbackAssetPath,
    this.fallbackIcon,
  });

  final String activeAssetPath;
  final String inactiveAssetPath;
  final bool active;
  final String? fallbackAssetPath;
  final IconData? fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final assetPath = active ? activeAssetPath : inactiveAssetPath;
    final fallbackColor = active
        ? const Color(0xFF1F1B1A)
        : Colors.black.withValues(alpha: 0.42);

    return Image.asset(
      assetPath,
      width: 18,
      height: 18,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) {
        if (fallbackAssetPath != null) {
          return Opacity(
            opacity: active ? 1.0 : 0.34,
            child: Image.asset(
              fallbackAssetPath!,
              width: 18,
              height: 18,
              fit: BoxFit.contain,
            ),
          );
        }
        if (fallbackIcon != null) {
          return Icon(fallbackIcon, size: 18, color: fallbackColor);
        }
        return const SizedBox(width: 18, height: 18);
      },
    );
  }
}

class _CloseOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF23201E)
      ..strokeWidth = 2.3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(size.width * 0.21, size.height * 0.21),
      Offset(size.width * 0.79, size.height * 0.79),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.79, size.height * 0.21),
      Offset(size.width * 0.21, size.height * 0.79),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TrashOutlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF23201E)
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final lidPath = Path()
      ..moveTo(size.width * 0.20, size.height * 0.29)
      ..lineTo(size.width * 0.80, size.height * 0.29)
      ..moveTo(size.width * 0.40, size.height * 0.18)
      ..lineTo(size.width * 0.60, size.height * 0.18);
    canvas.drawPath(lidPath, stroke);

    final binRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.23,
        size.height * 0.33,
        size.width * 0.54,
        size.height * 0.41,
      ),
      const Radius.circular(2.4),
    );
    canvas.drawRRect(binRect, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class ChatTurn {
  const ChatTurn({
    required this.user,
    required this.assistant,
    this.userImagePath,
    this.userImageName,
  });

  final String user;
  final String assistant;
  final String? userImagePath;
  final String? userImageName;

  factory ChatTurn.fromJson(Map<dynamic, dynamic> json) {
    return ChatTurn(
      user: json['user']?.toString() ?? '',
      assistant: json['assistant']?.toString() ?? '',
    );
  }

  Map<String, String> toJson() => {'user': user, 'assistant': assistant};

  ChatTurn copyWith({
    String? user,
    String? assistant,
    String? userImagePath,
    String? userImageName,
  }) {
    return ChatTurn(
      user: user ?? this.user,
      assistant: assistant ?? this.assistant,
      userImagePath: userImagePath ?? this.userImagePath,
      userImageName: userImageName ?? this.userImageName,
    );
  }
}
