// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

const _defaultBaseUrlOverride = String.fromEnvironment('DEFAULT_BASE_URL');

void main() => runApp(const LgMobileApp());

enum AssistantMode { idle, audio, photo, replying }

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
  File? _recordedNoise;
  String? _selectedImageName;
  String? _selectedAudioName;
  String? _recordedVoiceName;
  String? _recordedNoiseName;
  String? _latestEvidence;
  String? _errorMessage;
  bool _isSubmitting = false;
  bool _isCheckingConnection = false;
  bool _serverHealthy = false;
  bool _isRecordingVoice = false;
  bool _isRecordingNoise = false;
  bool _autoSpeak = true;
  bool _showWelcomeScreen = true;
  final String _dbUserName = 'ㅇㅇ';
  String _serverStatus = '확인 중';

  @override
  void initState() {
    super.initState();
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
    unawaited(_voiceRecorder.dispose());
    unawaited(_tts.stop());
    super.dispose();
  }

  void _handleComposerChanged() {
    if (mounted) {
      setState(() {});
    }
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
          hintText: '답변 작성 중입니다',
          gradientColors: [Color(0xFFFFF4F2), Color(0xFFFFD7DB)],
          accent: Color(0xFFD34B5C),
        );
      case AssistantMode.idle:
        return const _ModePresentation(
          label: 'AI CHAT · Normal Ver',
          title: '안녕하세요 고객님\n어떤 문제 상황인가요?',
          description:
              '텍스트를 입력하거나 + 버튼으로 사진과 파일을, 마이크 버튼으로 STT 또는 소음 녹음을 선택할 수 있어요.',
          hintText: '텍스트를 입력해주세요',
          gradientColors: [Color(0xFFFFF7F3), Color(0xFFFFDCD6)],
          accent: Color(0xFFE9524A),
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
    }
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

  Future<void> _speakText(String text) async {
    final trimmed = text.trim();
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
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isRecordingVoice = false;
        _errorMessage = '녹음을 시작하지 못했습니다: $error';
      });
    }
  }

  Future<void> _stopVoiceRecording() async {
    try {
      final savedPath = await _voiceRecorder.stop();
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
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isRecordingNoise = false;
        _errorMessage = '소음 녹음을 시작하지 못했습니다: $error';
      });
    }
  }

  Future<void> _stopNoiseRecording() async {
    try {
      final savedPath = await _voiceRecorder.stop();
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
    }
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
      useSafeArea: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBF8),
              borderRadius: BorderRadius.circular(32),
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
                const Text(
                  '마이크 모드 선택',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(
                  '말하기로 텍스트를 입력하거나, 제품 소리를 녹음해 분석받을 수 있어요.',
                  style: TextStyle(
                    color: Colors.black.withValues(alpha: 0.58),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                _AttachmentActionTile(
                  icon: Icons.mic_rounded,
                  title: '말하기 (STT)',
                  subtitle: '말한 내용을 텍스트로 변환해 전송합니다.',
                  color: const Color(0xFFFFECE8),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Future<void>.delayed(
                      const Duration(milliseconds: 120),
                      _startVoiceRecording,
                    );
                  },
                ),
                _AttachmentActionTile(
                  icon: Icons.graphic_eq_rounded,
                  title: '소음 녹음',
                  subtitle: '제품에서 나는 소리를 녹음해 AI가 분석합니다.',
                  color: const Color(0xFFFFF3E0),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Future<void>.delayed(
                      const Duration(milliseconds: 120),
                      _startNoiseRecording,
                    );
                  },
                ),
              ],
            ),
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

        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 24, 14, 14),
          child: Container(
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
                const Text(
                  '첨부 방법 선택',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  '원하는 방법을 선택해주세요',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.black.withValues(alpha: 0.56),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _AttachmentQuickAction(
                        icon: Icons.photo_camera_outlined,
                        label: '카메라',
                        onTap: () => handleTap(_capturePhoto),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AttachmentQuickAction(
                        icon: Icons.image_outlined,
                        label: '사진',
                        onTap: () => handleTap(_pickImageFromGallery),
                      ),
                    ),
                    const SizedBox(width: 10),
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
          ),
        );
      },
    );
  }

  String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

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

      if (_recordedNoise != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'audio',
            _recordedNoise!.path,
            filename: _recordedNoiseName,
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

      if (!mounted) {
        return;
      }

      setState(() {
        _history = nextHistory;
        _latestEvidence = const JsonEncoder.withIndent(
          '  ',
        ).convert(decoded['evidence']);
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
    if (_isRecordingNoise) {
      await _stopNoiseRecording();
    }
    await _stopSpeaking();
    if (!mounted) {
      return;
    }

    setState(() {
      _history = const [];
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
      _history = const [];
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

  Widget _buildWelcomeScreen() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF8),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'ChatThinQ',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: IconButton(
              tooltip: '연결 설정',
              onPressed: _openSettings,
              icon: const Icon(Icons.tune_rounded, size: 20),
            ),
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFBF8), Color(0xFFFFF3EE), Color(0xFFFFECE6)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      Text(
                        '$_displayName님을 위한 맞춤 안내',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.black.withValues(alpha: 0.88),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '생성형 AI를 활용한 스마트 어시스턴트로\n더 나은 자가진단과 손쉬운 대처를 경험해보세요.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.55,
                          color: Colors.black.withValues(alpha: 0.56),
                        ),
                      ),
                      const SizedBox(height: 20),

                      InkWell(
                        onTap: _openChatHome,
                        borderRadius: BorderRadius.circular(24),
                        child: Ink(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(18, 18, 12, 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: const Color(0xFFE8D0CB),
                              width: 1.5,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x26000000),
                                blurRadius: 20,
                                offset: Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color.fromARGB(
                                          255,
                                          255,
                                          133,
                                          129,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                      child: const Text(
                                        'NEW',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      '궁금증을 해결해줄 새로운 해결사',
                                      style: TextStyle(
                                        fontSize: 17,
                                        fontStyle: FontStyle.normal,
                                        fontWeight: FontWeight.w700,
                                        color: Color.fromARGB(255, 0, 0, 0),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        14,
                                        10,
                                        14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: Color(0x18000000),
                                            blurRadius: 10,
                                            offset: Offset(0, 4),
                                          ),
                                        ],
                                      ),

                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  '제품과 관련된 질문은\n저에게 물어보세요!',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    height: 1.36,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFF231E1D),
                                                  ),
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  '터치해서 바로 대화를 시작해보세요',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.black
                                                        .withValues(
                                                          alpha: 0.42,
                                                        ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 112,
                                            height: 112,
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              alignment: Alignment.center,
                                              children: [
                                                Container(
                                                  width: 108,
                                                  height: 108,
                                                  decoration:
                                                      const BoxDecoration(
                                                        shape: BoxShape.circle,
                                                        color: Color(
                                                          0xFFFFE9E7,
                                                        ),
                                                      ),
                                                ),
                                                Positioned(
                                                  right: -4,
                                                  bottom: -4,
                                                  child: Image.asset(
                                                    _characterAssetForMode(
                                                      AssistantMode.idle,
                                                    ),
                                                    width: 112,
                                                    height: 112,
                                                    fit: BoxFit.contain,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      Center(
                        child: Text(
                          'API 생성형 콘텐츠를 부분적으로 수집할 수 있습니다. 더보기',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9.5,
                            color: Colors.black.withValues(alpha: 0.34),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildWelcomeComposer(),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
              _buildWelcomeNavigation(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeComposer() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4F0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.add_rounded,
              size: 20,
              color: Colors.black.withValues(alpha: 0.34),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '텍스트를 입력해주세요',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.black.withValues(alpha: 0.36),
              ),
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4F0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.mic_none_rounded,
              size: 18,
              color: Colors.black.withValues(alpha: 0.34),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeNavigation() {
    const items = <({IconData icon, String label})>[
      (icon: Icons.home_filled, label: '홈'),
      (icon: Icons.grid_view_rounded, label: '디바이스'),
      (icon: Icons.search_rounded, label: '챗봇'),
      (icon: Icons.bar_chart_rounded, label: '제어'),
      (icon: Icons.article_outlined, label: '메뉴'),
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
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      size: 18,
                      color: item.label == '홈'
                          ? const Color(0xFF1F1B1A)
                          : Colors.black.withValues(alpha: 0.42),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: item.label == '홈'
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: item.label == '홈'
                            ? const Color(0xFF1F1B1A)
                            : Colors.black.withValues(alpha: 0.42),
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

  Widget _buildChatIntroPanel() {
    final presentation = _modePresentation;
    final showDescription = _assistantMode != AssistantMode.idle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: 172,
              height: 172,
              child: RobotIllustration(mode: _assistantMode),
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(
              presentation.title,
              style: const TextStyle(
                fontSize: 17.5,
                height: 1.35,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F1B1A),
              ),
            ),
          ),
          if (showDescription) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                presentation.description,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.55,
                  color: Colors.black.withValues(alpha: 0.52),
                ),
              ),
            ),
          ],
          const Spacer(),
        ],
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
        InputChip(
          avatar: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              _selectedImage!,
              width: 28,
              height: 28,
              fit: BoxFit.cover,
            ),
          ),
          label: Text(_selectedImageName ?? '사진'),
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
        InputChip(
          avatar: const Icon(Icons.audio_file_rounded, size: 18),
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
        InputChip(
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

    if (_recordedNoiseName != null) {
      chips.add(
        InputChip(
          avatar: const Icon(Icons.graphic_eq_rounded, size: 18),
          label: Text(_recordedNoiseName!),
          onDeleted: () {
            setState(() {
              _recordedNoise = null;
              _recordedNoiseName = null;
            });
          },
        ),
      );
    }

    if (_isRecordingVoice) {
      chips.add(
        const Chip(
          avatar: Icon(Icons.fiber_manual_record_rounded, color: Colors.red),
          label: Text('녹음 중'),
          backgroundColor: Color(0xFFFFEEEA),
        ),
      );
    }

    if (_isRecordingNoise) {
      chips.add(
        const Chip(
          avatar: Icon(Icons.graphic_eq_rounded, color: Colors.orange),
          label: Text('소음 녹음 중'),
          backgroundColor: Color(0xFFFFF3E0),
        ),
      );
    }

    return chips;
  }

  Widget _buildBubble(String message, {required bool isUser}) {
    final bubbleColor = isUser ? const Color(0xFFF06A5D) : Colors.white;
    final foreground = isUser ? Colors.white : const Color(0xFF312726);

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isUser ? '고객' : 'AI',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.black.withValues(alpha: 0.42),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (!isUser) ...[
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _speakText(message),
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: Icon(
                          Icons.volume_up_rounded,
                          size: 16,
                          color: Colors.black.withValues(alpha: 0.42),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(22),
                  topRight: const Radius.circular(22),
                  bottomLeft: Radius.circular(isUser ? 22 : 8),
                  bottomRight: Radius.circular(isUser ? 8 : 22),
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 10,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Text(
                message,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  height: 1.48,
                  fontWeight: FontWeight.w500,
                ),
              ),
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

  Widget _buildConversationPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
      ),
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        children: [
          for (final turn in _history) ...[
            _buildBubble(turn.user, isUser: true),
            const SizedBox(height: 8),
            _buildBubble(turn.assistant, isUser: false),
            const SizedBox(height: 14),
          ],
          if (_isSubmitting)
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
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
                    SizedBox(width: 10),
                    Text(
                      '답변을 작성중이에요...',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final chips = _buildAttachmentChips();
    final showMicAction = !_canSend && !_isSubmitting;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      tooltip: '첨부 메뉴 열기',
                      onPressed: _isSubmitting ? null : _openAttachmentSheet,
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.add_rounded,
                        color: _modePresentation.accent,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      enabled: !_isSubmitting,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 12.5, height: 1.45),
                      decoration: InputDecoration(
                        hintText: _modePresentation.hintText,
                        filled: false,
                        fillColor: Colors.transparent,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 0,
                          vertical: 10,
                        ),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: showMicAction ? const Color(0xFFFFF4F0) : null,
                      gradient: showMicAction
                          ? null
                          : const LinearGradient(
                              colors: [Color(0xFFE9524A), Color(0xFFCA4156)],
                            ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: _isSubmitting
                            ? null
                            : (showMicAction ? _handleMicTap : _sendMessage),
                        icon: _isSubmitting
                            ? const SizedBox.square(
                                dimension: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                showMicAction
                                    ? ((_isRecordingVoice || _isRecordingNoise)
                                          ? Icons.stop_circle_rounded
                                          : Icons.mic_none_rounded)
                                    : Icons.arrow_upward_rounded,
                                size: 18,
                                color: showMicAction
                                    ? (_isRecordingVoice
                                          ? const Color(0xFFCA4156)
                                          : _isRecordingNoise
                                          ? const Color(0xFFE07A00)
                                          : Colors.black.withValues(
                                              alpha: 0.36,
                                            ))
                                    : Colors.white,
                              ),
                      ),
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

  Widget _buildChatScreen() {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: Container(
          margin: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(10),
          ),
          child: IconButton(
            padding: EdgeInsets.zero,
            onPressed: () => setState(() => _showWelcomeScreen = true),
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
          ),
        ),
        title: const Text(
          'ChatThinQ',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            margin: const EdgeInsets.symmetric(vertical: 8),
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
                  _isCheckingConnection ? '확인 중' : _serverStatus,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: '연결 설정',
            onPressed: _openSettings,
            icon: const Icon(Icons.tune_rounded, size: 20),
          ),
          IconButton(
            tooltip: '대화 초기화',
            onPressed: _resetConversation,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFFFBF7), Color(0xFFFFF1EB), Color(0xFFFFECE6)],
          ),
        ),
        child: SafeArea(
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
                        child: _history.isEmpty
                            ? _buildChatIntroPanel()
                            : _buildConversationPanel(),
                      ),
                    ],
                  ),
                ),
              ),
              _buildComposer(),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _showWelcomeScreen ? _buildWelcomeScreen() : _buildChatScreen();
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
      color: const Color(0xFFF3F0EE),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: const Color(0xFF231E1D)),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
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
    };

    final rightAngle = switch (mode) {
      AssistantMode.audio => 1.05,
      AssistantMode.photo => 0.25,
      AssistantMode.replying => 0.62,
      AssistantMode.idle => 0.55,
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
