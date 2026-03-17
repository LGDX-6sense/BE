# ChatThinQ Flutter 앱

`mobile_app/`는 LG 가전 멀티모달 에이전트를 위한 Flutter 클라이언트입니다. Android와 iOS에서 실행할 수 있으며, 텍스트, 사진, 파일, STT, 소음 녹음 흐름을 한 화면에서 다룰 수 있습니다.

## 준비

패키지를 설치합니다.

```bash
flutter pub get
```

## 실행 방법

안드로이드 에뮬레이터:

```bash
flutter run -d android --dart-define=DEFAULT_BASE_URL=http://10.0.2.2:8000
```

iOS 시뮬레이터:

```bash
flutter run -d ios --dart-define=DEFAULT_BASE_URL=http://127.0.0.1:8000
```

실기기:

- 같은 Wi-Fi 환경이면 PC의 LAN IP를 사용합니다.
- 예시: `http://192.168.0.20:8000`

## 안드로이드 실기기 Hot Reload

USB로 연결된 안드로이드 기기에서 `adb reverse`까지 자동으로 처리하며 실행하려면 아래 스크립트를 사용합니다.

```powershell
.\run_hot_reload.ps1
```

옵션을 직접 지정할 수도 있습니다.

```powershell
.\run_hot_reload.ps1 -DeviceId R3CN205RZTY -BaseUrl http://127.0.0.1:8000
```

실행 중 사용할 수 있는 키:

- `r`: Hot Reload
- `R`: Hot Restart
- `q`: 종료

## 현재 지원하는 기능

- 텍스트 입력
- 카메라 촬영
- 갤러리 사진 선택
- 파일 기반 오디오 업로드
- 마이크 버튼으로 `말하기(STT)` 또는 `소음 녹음` 선택
- 채팅 히스토리 확인
- 분석 근거(Evidence) 팝업 확인
- 앱 내부에서 백엔드 주소 설정

## 개발 팁

- Android 에뮬레이터는 보통 `http://10.0.2.2:8000`을 사용합니다.
- iOS 시뮬레이터는 보통 `http://127.0.0.1:8000`을 사용합니다.
- 안드로이드 실기기를 USB로 연결한 경우 `adb reverse`를 쓰면 `http://127.0.0.1:8000`으로 개발할 수 있습니다.
- 분석 전에 `flutter analyze lib/main.dart`로 기본 정적 검사를 돌려두면 편합니다.
