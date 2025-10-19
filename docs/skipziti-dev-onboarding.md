# SkipZiti Developer Onboarding

Welcome to the SkipZiti project. This guide summarizes the essential repo context, environment requirements, and validation steps referenced across `docs/brief.md`, `docs/openziti-sdk-review.md`, `docs/skip-fuse-framework.md`, `docs/skip-sdk-case-studies.md`, and `docs/skipziti-implementation-plan.md`.

---

## 1. Project Snapshot
- **Mission:** Deliver a Skip Fuse-native Swift SDK that embeds OpenZiti zero-trust networking for iOS and Android from a unified codebase.
- **Key Outcomes:** Cross-platform Swift APIs, automated enrollment & tunnel flows, secure identity storage, telemetry hooks, and robust docs/samples.
- **Primary References:** Read the project brief first (`docs/brief.md`), then skim the OpenZiti analysis and Skip Fuse deep dive for technical background.

---

## 2. Access & Credentials Checklist
- Ensure you have Skip Fuse license details (`SKIPKEY`) before running native builds.
- Obtain OpenZiti controller URLs, enrollment JWT sources, and any staging credentials needed for integration testing.
- Confirm Git submodules or vendored dependencies (e.g., CZiti) are accessible from your environment.

---

## 3. Environment Preparation
1. **Install prerequisites**
   - Skip CLI (latest release).
   - Swift toolchain with Swift-for-Android support.
   - Xcode 16+ for iOS builds.
   - Android Studio + SDK/NDK/command-line tools (Gradle 8.x recommended).
2. **Configure Skip license**
   ```bash
   export SKIPKEY="<your-license-key>"
   ```
3. **Validate tooling**
   ```bash
   skip checkup --native
   swift --version
   xcodebuild -version
   adb devices
   ```
   Resolve any failures before touching the codebase. Keep console output for audit.

---

## 4. Repository Orientation
- `docs/brief.md`: business context, goals, KPIs, risks.
- `docs/openziti-sdk-review.md`: structural analysis of official OpenZiti Swift/Android SDKs.
- `docs/skip-fuse-framework.md`: essential Skip Fuse concepts, CLI workflows, and bridging mechanics.
- `docs/skip-sdk-case-studies.md`: proven patterns used by SkipFirebase, SkipStripe, SkipZip.
- `docs/skipziti-implementation-plan.md`: current roadmap, architecture, CLI usage, testing strategy.

Review each document before implementing features or stories—most questions are answered there.

---

## 5. Getting Started (Day 0)
1. Clone the repo and update submodules.
2. Run environment validation commands above.
3. Execute baseline builds/tests once the scaffold exists:
   ```bash
   swift build --build-tests
   skip test
   ```
4. Read the “Phase 1” tasks in `docs/skipziti-implementation-plan.md` to align on module structure and coding standards.
5. Document any environment deviations in your session notes or PR description.

---

## 6. During Development
- Keep the architecture boundaries defined in the implementation plan (`SkipZitiCore`, `SkipZitiIdentity`, etc.).
- Follow case-study guidance for Android bridging (guard code with `#if SKIP`, use `KotlinConverting`, `SkipFFI` when needed).
- Update the implementation plan or supporting docs if you diverge materially from prescribed workflows.

---

## 7. Before You Finish
1. Run the full command suite relevant to your change (`swift test`, `skip test`, `skip android build`, `skip android test` if applicable).
2. Verify docs and samples remain accurate; add snippets when exposing new APIs.
3. Capture telemetry or performance metrics if your change touches enrollment/tunnel paths.
4. Update risks or assumptions in the plan if you discover toolchain or controller constraints.

---

## 8. Need Help?
- Re-read the analysis documents; most architectural or API questions are covered there.
- If tooling fails, consult official Skip CLI documentation (skip.tools/docs/skip-cli) or escalate via project maintainer channels with logs attached.
- For controller or policy issues, coordinate with the owner of the OpenZiti environment referenced in the brief.

Happy building!

