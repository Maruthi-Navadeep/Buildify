# Buildify AI Server

[![CI](https://github.com/Maruthi-Navadeep/Buildify/actions/workflows/ci.yml/badge.svg)](https://github.com/Maruthi-Navadeep/Buildify/actions/workflows/ci.yml)
[![Security](https://github.com/Maruthi-Navadeep/Buildify/actions/workflows/security.yml/badge.svg)](https://github.com/Maruthi-Navadeep/Buildify/actions/workflows/security.yml)
[![Release](https://github.com/Maruthi-Navadeep/Buildify/actions/workflows/release.yml/badge.svg)](https://github.com/Maruthi-Navadeep/Buildify/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

<p align="center">
  <img src="demo-video/buildify-brief-small.gif" alt="Buildify demo — host anything from your phone: run a local AI model or your project, on your own device" width="640">
</p>

Flutter Android app that turns a phone into a **local LLM HTTP server** on your Wi‑Fi: pick a GGUF model, start the server, and other devices call OpenAI-compatible endpoints (e.g. `/v1/chat/completions`) on the phone’s LAN IP.

**Stack:** Flutter UI → MethodChannel → Kotlin foreground service → [llama.cpp](https://github.com/ggml-org/llama.cpp) `llama-server` → GGUF on your device.

> **Contributing?** See [CONTRIBUTING.md](CONTRIBUTING.md), the [Code of Conduct](CODE_OF_CONDUCT.md), and the [Security Policy](SECURITY.md).


## Requirements

- Flutter SDK (see `pubspec.yaml` for Dart SDK constraint)
- Android device or emulator (arm64 recommended)
- **Native binaries:** ship `llama-server` and companion `.so` files under `android/app/src/main/jniLibs/arm64-v8a/` (see `android/app/src/main/jniLibs/arm64-v8a/README.txt`). Android does not allow executing binaries copied from app assets into private storage; jniLibs + `libllama-server.so` naming is required.
- Models download into app storage (`files/models/`); curated URLs are in `lib/main.dart`.

## Quick start (developers)

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```

Place GGUF models via in-app download or adb into the app’s `files/models/` directory (see project docs / logs).

## Documentation

Detailed guides live under **[docs/](docs/)** — start at [docs/README.md](docs/README.md):

- Architecture, Android engine (jniLibs), models & ADB, API & Postman, troubleshooting, product scope, roadmap.

## Marketing site

The promo site for **buildify.me** lives in **[website/](website/)** (Next.js 16 + Tailwind 4 + shadcn + Magic UI). It auto-renders the docs in `docs/` at build time.

```bash
cd website
pnpm install
pnpm dev      # http://localhost:3000
pnpm build    # production build
```

Deployment notes are in [website/README.md](website/README.md).

## Contributing

### Git workflow

Use **small, focused commits**. Each commit should explain one logical change.

Recommended branch names:

```text
feat/model-download-progress
fix/server-start-on-android-10
ui/logs-copy-button
docs/readme-contributing
chore/flutter-deps
```

### Commit message convention

Use [Conventional Commits](https://www.conventionalcommits.org/):

```text
type(scope): short description
```

Examples:

```text
feat(download): stream GGUF from Hugging Face with progress
fix(android): resolve llama-server via nativeLibraryDir
ui(home): add copy-logs button
docs(readme): document jniLibs layout
chore(deps): bump http package
test(widget): smoke test home screen
refactor(native): simplify AiServerService process launch
perf(ui): reduce rebuilds on download progress
build(android): enable jniLibs legacy packaging
```

Common types:

| Type | Use for |
|------|---------|
| `feat` | New feature |
| `fix` | Bug fix |
| `ui` | Visual or interaction change |
| `docs` | Documentation only |
| `chore` | Maintenance, tooling, dependencies |
| `test` | Tests only |
| `refactor` | Restructure without behavior change |
| `perf` | Performance |
| `build` | Build system or platform config |

### Pull request checklist

Before opening or merging a PR:

- [ ] Run `flutter analyze`
- [ ] Run `flutter test`
- [ ] Confirm **no secrets** are committed (API keys, keystores, `.env`)
- [ ] Keep **generated build outputs** out of Git (`build/`, `.dart_tool/`, etc.)
- [ ] Update **README** or setup docs when install/run behavior changes
- [ ] Use a **clear PR title** following the commit convention

### Files that should not be committed

Do **not** commit:

- `.env` or environment files with real credentials
- **Signing keys:** `*.jks`, `*.keystore`, `key.properties` with real passwords
- **Google / Firebase** config files if they contain project secrets you do not intend to share publicly
- **Build outputs:** `build/`, Android `**/build/`, `.dart_tool/`
- **Machine-local paths:** `android/local.properties`
- **Huge optional tarballs** extracted beside the repo (e.g. `llama-b*/`); prefer documenting download + copy steps (root `.gitignore` ignores `llama-b*/` by default)

**Large native binaries (`jniLibs/*.so`):**  
You may commit them for a turnkey clone, or document “copy from official llama.cpp Android release” and use **Git LFS** if files exceed GitHub’s size limits. Do not commit unrelated platform builds (Windows `.exe`, etc.).

The `.gitignore` is set up for typical Flutter + Android + secret patterns; review before every push.

## License

Add a `LICENSE` file when you choose a license for the project.
