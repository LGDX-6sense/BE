# LG 가전 멀티모달 에이전트

이 저장소는 LG 가전 관련 질의응답과 증상 분석을 위해 구성된 멀티모달 프로젝트입니다. 현재 저장소에는 다음 세 가지가 함께 포함되어 있습니다.

- 기존 Python 기반 멀티모달 에이전트
- 모바일 앱에서 사용하기 쉬운 FastAPI 백엔드 래퍼
- Android와 iOS에서 실행 가능한 Flutter 클라이언트

## 주요 기능

- 텍스트 기반 질의응답
- 사진 촬영 및 갤러리 이미지 업로드
- 오디오 파일 업로드
- 마이크를 통한 말하기(STT) 입력
- 제품 소리 녹음 후 소음 분석
- 채팅 히스토리 표시
- 분석 근거(Evidence) 확인
- 앱 내부에서 백엔드 주소 변경

## 1. 백엔드 실행

### 의존성 설치

```bash
pip install -r requirements.txt
```

### 서버 실행

```bash
python mobile_api.py --host 0.0.0.0 --port 8000
```

### 헬스 체크

브라우저 또는 API 도구에서 아래 주소로 확인할 수 있습니다.

```text
http://127.0.0.1:8000/health
```

### 참고 사항

- `OPENAI_API_KEY`는 응답 생성, 이미지 분석, 음성 전사(STT)에 필요합니다.
- `data/lg_solution_chunks.jsonl` 파일이 없으면 `lg_solution_all.json`을 읽어 메모리에서 검색용 청크를 생성합니다.
- 오디오 진단 기능을 사용하려면 학습된 오디오 모델과 클래스 `.npy` 파일이 준비되어 있어야 합니다.

## 2. Flutter 모바일 앱

Flutter 앱은 `mobile_app/` 디렉터리에 있습니다.

### 패키지 설치

```bash
cd mobile_app
flutter pub get
```

### 실행 예시

안드로이드 에뮬레이터:

```bash
flutter run -d android --dart-define=DEFAULT_BASE_URL=http://10.0.2.2:8000
```

iOS 시뮬레이터:

```bash
flutter run -d ios --dart-define=DEFAULT_BASE_URL=http://127.0.0.1:8000
```

실기기:

- 같은 Wi-Fi에 연결된 경우 PC의 LAN IP를 사용합니다.
- 예시: `http://192.168.0.20:8000`

## 3. 실기기 Hot Reload

안드로이드 실기기를 USB로 연결한 상태라면 `adb reverse`를 포함한 스크립트로 바로 Hot Reload 개발을 할 수 있습니다.

```powershell
cd mobile_app
.\run_hot_reload.ps1
```

옵션을 직접 넘기는 방법:

```powershell
.\run_hot_reload.ps1 -DeviceId R3CN205RZTY -BaseUrl http://127.0.0.1:8000
```

`flutter run`이 실행된 상태에서는 아래 키를 사용할 수 있습니다.

- `r`: Hot Reload
- `R`: Hot Restart
- `q`: 종료

## 4. 백엔드 주소 가이드

개발 환경에 따라 사용할 주소가 다릅니다.

- Android 에뮬레이터: `http://10.0.2.2:8000`
- iOS 시뮬레이터: `http://127.0.0.1:8000`
- Android 실기기 + `adb reverse`: `http://127.0.0.1:8000`
- Android/iOS 실기기 + 같은 Wi-Fi: PC의 LAN IP 사용

앱 내부의 연결 설정 화면에서도 주소를 직접 바꿀 수 있습니다.

## 5. 모바일 앱 지원 기능

현재 Flutter 클라이언트에는 아래 기능이 포함되어 있습니다.

- 텍스트 입력
- 카메라 촬영
- 갤러리 이미지 선택
- 파일 기반 오디오 업로드
- 마이크 버튼으로 `말하기(STT)` 또는 `소음 녹음` 선택
- 채팅 히스토리 표시
- 분석 근거(Evidence) 팝업 확인
- 로컬 백엔드 주소 설정

## REBO 유스케이스/기능 명세

현재 구현 기준으로 다시 정리한 REBO 유스케이스와 기능 상태표는 아래 문서에서 확인할 수 있습니다.

- [REBO_USECASE_SPEC.md](REBO_USECASE_SPEC.md)

## 6. 플랫폼별 개발 설정

로컬 개발 편의를 위해 네트워크 및 권한 설정이 추가되어 있습니다.

- Android: `INTERNET` 권한과 로컬 HTTP 통신용 cleartext 설정
- iOS: 로컬 개발용 App Transport Security 완화, 사진 라이브러리 접근 설명, 카메라 사용 설명

## 7. 자주 쓰는 명령어

백엔드:

```bash
python mobile_api.py
```

Flutter:

```bash
cd mobile_app
flutter pub get
flutter analyze lib/main.dart
flutter run
```
