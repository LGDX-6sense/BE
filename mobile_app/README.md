# ChatThinQ Flutter 앱

`mobile_app/`는 LG 가전 멀티모달 진단용 Flutter 클라이언트입니다.  
Android와 iPhone에서 실행할 수 있고, 텍스트, 사진, 음성 녹음, 파일 첨부를 지원합니다.

## 준비

```bash
flutter pub get
```

## iPhone에서 실행

사전 준비:

- Mac에 Xcode 설치
- Mac에 CocoaPods 설치
- iPhone을 Mac에 연결
- iPhone과 백엔드 PC를 같은 Wi-Fi에 연결
- Apple 개발자 서명 설정

백엔드 주소:

- 현재 Windows PC 주소 예시: `http://192.168.0.13:8000`
- 주소가 바뀌면 `ipconfig`로 다시 확인

직접 실행:

```bash
cd mobile_app
flutter pub get
cd ios
pod install
cd ..
flutter run --dart-define=DEFAULT_BASE_URL=http://192.168.0.13:8000
```

스크립트 실행:

```bash
cd mobile_app
chmod +x run_ios_device.sh
./run_ios_device.sh
```

백엔드 주소를 바꿔서 실행:

```bash
./run_ios_device.sh http://192.168.0.13:8000
```

특정 iPhone 기기를 지정해서 실행:

```bash
flutter devices
./run_ios_device.sh http://192.168.0.13:8000 <device_id>
```

## Android에서 실행

에뮬레이터:

```bash
flutter run -d android --dart-define=DEFAULT_BASE_URL=http://10.0.2.2:8000
```

실기기:

- 같은 Wi-Fi 환경이면 PC LAN IP 사용
- USB 연결 + `adb reverse` 환경이면 `http://127.0.0.1:8000` 사용 가능

## Hot Reload

`flutter run` 실행 중에는:

- `r`: Hot Reload
- `R`: Hot Restart
- `q`: 종료
