# SkipZiti CI & Validation Reference

This guide captures the continuous-integration and validation expectations for SkipZiti. It condenses testing strategies from `docs/skipziti-implementation-plan.md` (§8), environment notes from `docs/skip-fuse-framework.md`, and risk considerations in `docs/brief.md`.

---

## 1. Pipeline Overview

| Pipeline | Purpose | Key Jobs |
| --- | --- | --- |
| PR CI | Block regressions on incoming changes. | Environment validation → Swift build/tests → Skip parity tests → Android builds/tests (conditional). |
| Nightly (toolchain) | Detect Skip/Swift-for-Android drift. | `skip checkup --native` on latest toolchains, `skip test`, performance smoke. |
| Release | Produce artifacts and run full regression. | PR CI steps + `skip export --release`, signing/notarization, artifact publish. |

---

## 2. Required Commands

Execute and record relevant commands for any change touching shared code, bridging, or build tooling.

```bash
# 1. Environment
skip version
skip checkup --native

# 2. Swift build/tests (Darwin)
swift build --build-tests
swift test

# 3. Skip parity (Swift + Kotlin)
skip test

# 4. Android (when Gradle/Kotlin/native code touched)
skip android build --project .
skip android test --project .

# 5. Release
skip export --release --project .
```

> Capture command output (especially failures) in CI logs or PR summaries to aid future sessions.

---

## 3. Matrix Targets
- **iOS:** arm64 device, arm64 simulator (Xcode 16 toolchain).
- **Android:** arm64-v8a, armeabi-v7a; optional x86_64 emulator for instrumentation tests.
- **Toolchains:** Pin Skip CLI version and Swift-for-Android tag; run nightly job against latest published versions to detect drift (see risks in `docs/brief.md`).

---

## 4. Quality Gates
- **Build Success:** 100% pass rate across matrix before merge.
- **Test Coverage:** ≥80% for modules touched; parity tests must run for shared code.
- **Performance Budget:** Tunnel initialization latency overhead ≤10% vs direct network baseline.
- **Security Checks:** Identity storage tests must verify secure persistence (Keychain/Android Keystore).
- **Documentation Sync:** CI ensures DocC or Markdown references build (run `swift build --target SkipZitiDocs` if a docs target exists).

---

## 5. Sample GitHub Actions Workflow (Mac Runner)
```yaml
name: pr-ci
on:
  pull_request:
  push:
    branches: [main]

jobs:
  build-test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Install Skip CLI
        run: brew install skiptools/tap/skip
      - name: Validate Environment
        run: skip checkup --native
      - name: Swift Build & Test
        run: |
          swift build --build-tests
          swift test
      - name: Skip Parity Tests
        run: skip test
      - name: Android Build/Test
        if: contains(github.event.pull_request.changed_files, 'Android/')
        run: |
          skip android build --project .
          skip android test --project .
```

Add additional jobs for performance benchmarks or doc generation as needed.

---

## 6. Troubleshooting Playbook

| Failure | Likely Cause | Recovery |
| --- | --- | --- |
| `skip checkup --native` fails on Android SDK | Missing SDK/NDK path or license | Install via `skip android sdk install`, accept licenses, rerun checkup. |
| `swift build` fails linking CZiti | CMake/config mismatch | Verify CZiti path, regenerate `Skip/skip.yml` CMake blocks (see case studies). |
| `skip test` Kotlin errors | Bridging mismatched with new Swift API | Update `skip.yml` and Kotlin façade, rerun `skip android build`. |
| Android emulator tests timeout | Emulator image not installed | Pre-download via `avdmanager`, run `emu-headless` or use physical device farm. |
| Tunnel latency regression | Controller change or code regression | Compare performance logs, profile libuv loop, revisit mitigation in implementation plan. |

Log resolved issues in PR descriptions or update documentation if fixes influence onboarding.

---

## 7. Artifact Management
- **Swift:** Ship SwiftPM package + DocC archives. Tag releases and optionally submit to Swift Package Index.
- **Android:** Publish AAR via `skip export --release`, then upload to Maven repository (internal or public).
- **Telemetry:** Store benchmark results and test run metrics for at least the last 10 releases to track trends.

---

## 8. Change Control Notes
- Always update `docs/skipziti-implementation-plan.md` if CI commands or gates change.
- For new pipelines, append workflow details here and link from onboarding materials.
- Record any toolchain upgrades in a changelog entry with actionable rollback steps.

Keep this reference accessible during CI/debugging to maintain consistent validation standards across AI coding sessions.

