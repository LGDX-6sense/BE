# LG Appliance Multimodal Agent

This repository now includes:

- The original Python multimodal agent
- A mobile-friendly FastAPI wrapper
- A Flutter client that can run on Android and iOS

## 1. Backend setup

Install Python dependencies:

```bash
pip install -r requirements.txt
```

Start the mobile API server:

```bash
python mobile_api.py --host 0.0.0.0 --port 8000
```

Health check:

```bash
http://127.0.0.1:8000/health
```

Notes:

- `OPENAI_API_KEY` must be configured for image analysis and response generation.
- If `data/lg_solution_chunks.jsonl` is missing, the backend now falls back to `lg_solution_all.json` and builds retrieval chunks in memory.
- The repository currently expects the trained audio model and class `.npy` files to exist if audio diagnosis is used.

## 2. Flutter mobile app

The Flutter app lives in `mobile_app/`.

Install packages:

```bash
cd mobile_app
flutter pub get
```

Run on Android emulator:

```bash
flutter run
```

Default backend URL in the app:

- Android emulator: `http://10.0.2.2:8000`
- iOS simulator: `http://127.0.0.1:8000`
- Physical device: use your computer LAN IP, for example `http://192.168.0.20:8000`

## 3. iOS and Android support added

The Flutter client now includes:

- Text input
- Image picker
- Audio file picker
- Chat history
- Evidence/debug viewer
- Local backend URL configuration

Platform networking changes:

- Android: `INTERNET` permission and cleartext HTTP enabled for local development
- iOS: App Transport Security relaxed for local development and photo library usage description added

## 4. Useful commands

Backend:

```bash
python mobile_api.py
```

Flutter:

```bash
cd mobile_app
flutter run -d android
flutter run -d ios
```
