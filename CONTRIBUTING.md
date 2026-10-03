# Contributing to Buildify

Thanks for your interest in contributing! This guide covers how to get set up,
the quality bar, and how to propose changes.

## Getting started

```bash
git clone https://github.com/Maruthi-Navadeep/Buildify.git
cd Buildify
flutter pub get
flutter run          # Android device/emulator, or -d windows|macos|linux|chrome
```

- **Flutter:** use the `stable` channel. The Dart SDK constraint is in
  [`pubspec.yaml`](pubspec.yaml).
- **Native binaries:** on-device AI needs `llama-server` (and `cloudflared` for
  tunnels). These are **not** in the repo — see the README for where to place
  them per platform. The app builds and runs the UI without them; only the
  server/tunnel features are unavailable.

## Before you open a PR

Run the same checks CI runs, locally:

```bash
dart format .                 # must produce no changes
flutter analyze               # must pass with no new issues
flutter test                  # must pass
```

CI (`.github/workflows/ci.yml`) enforces formatting, analysis, tests, and
Android/web compile checks. The security workflow runs CodeQL, dependency
scanning (OSV + dependency review), and secret detection. All required checks
must be green before merge.

## Branch & commit conventions

- Branch off `main`: `feat/...`, `fix/...`, `chore/...`, `docs/...`.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for messages,
  e.g. `fix(hosting): bind static server to loopback`.
- Keep PRs focused. Fill out the PR template and link the issue you're closing.

## Coding guidelines

- Match the style of the surrounding code; `flutter_lints` is the baseline
  (see [`analysis_options.yaml`](analysis_options.yaml)).
- Add or update tests for behavior changes (`test/`).
- Prefer platform-agnostic Dart; when platform code is unavoidable, keep it
  behind an interface (see `ServerBridge` in `lib/services/`).
- Don't commit secrets, credentials, `.env` files, or large binaries.

## Reporting bugs & requesting features

Use the issue templates. For **security** issues, do not open a public issue —
follow [SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
