# SkipZiti Implementation Plan

Prepared October 19, 2025 for the SkipZiti initiative. This document synthesizes the project brief (`docs/brief.md`), OpenZiti analysis (`docs/openziti-sdk-review.md`), Skip Fuse deep dive (`docs/skip-fuse-framework.md`), and Skip SDK case studies (`docs/skip-sdk-case-studies.md`) with current Skip CLI guidance (skip.tools/docs/skip-cli, skip.tools/docs/gradle).

---

## 1. Mission & Scope
- **Objective:** Ship a reusable Skip Fuse-native Swift SDK that embeds OpenZiti zero-trust networking for iOS and Android from a single codebase, eliminating platform-specific wiring and meeting the success criteria in the brief.
- **Deliverables:** SwiftPM package, Kotlin bridge artifacts, enrollment & tunnel APIs, diagnostics surface, onboarding docs, CI automation, example Skip Fuse app.
- **Non-goals for v1:** Desktop Swift targets, managed controller provisioning, non-Swift platforms, advanced observability plugins.

---

## 2. Project Foundations
- **Primary References:** `docs/brief.md`, `docs/openziti-sdk-review.md`, `docs/skip-fuse-framework.md`, `docs/skip-sdk-case-studies.md`.
- **SDK Parity Requirements:** Async/await-first APIs, identical enrollment & tunnel semantics across platforms, secure identity storage, ≤10% tunnel latency overhead on low-end Android hardware.
- **Stakeholders:** Single maintainer (you) acting as architect, developer, and validator.

---

## 2.1 Current Status (October 20, 2025)
- **Shared Layer:** `SkipZitiConfiguration`, `SkipZitiClient`, the in-memory identity store, and the service/posture models (`SkipZitiServiceDescriptor`, `SkipZitiServiceUpdate`, `SkipZitiPostureQueryEvent`, `SkipZitiReportedError`) remain in place. We have reintroduced `#if !SKIP_BRIDGE` guards around these types so the Swift sources participate in native builds while Skip’s generated Kotlin owns the Android bridge surface, per the [Skip transpiled-mode guidance](https://skip.tools/docs/modes/).
- **Apple Bridge:** `ZitiSwiftBridge` carries the full OpenZiti integration under `#if !SKIP_BRIDGE && canImport(Ziti)`. The Kotlin parity pipeline now imports Skip’s generated projection at `.build/plugins/outputs/skipziti/SkipZiti/destination/skipstone/SkipBridgeGenerated/ZitiSwiftBridge_Bridge.swift`, but Gradle still fails because the generated Kotlin adapters (`callback_start`, etc.) conflict with the protocol generated from `SkipZitiPlatformBridge`.
- **Android Bridge:** `ZitiAndroidBridge` continues to wrap `org.openziti.android.Ziti` inside an `#if SKIP` block. The Kotlin translation invokes posture helper accessors like `getId()`/`getTimeout()` that we have not yet surfaced through the Skip-friendly typealiases. Graduate parity still breaks because those getters are unresolved.
- **Build & Tests:** `swift build` and `skip android build` both invoke Skip successfully, but `swift test`/`skip test --plain` terminate in Gradle (`:SkipZiti:compileDebugKotlin`) due to the callback override mismatch and missing posture getters. We copied the populated Skip support modules (`SkipFoundation`, `SkipLib`, `SkipUnit`) from `../SkipRepos/skip-stripe/.build/plugins/outputs/...` so Kotlin now resolves shared symbols such as `Task`, `Async.run`, and `ProcessInfo`.
- **Reference Material:** Working Skip bridging examples live under `../SkipRepos/skip-stripe` and `../SkipRepos/skip-firebase` (see their `Sources/*/Skip/skip.yml` files and transpiled outputs). OpenZiti source context is staged in `/tmp/ziti-sdk-swift2` (Apple SDK) and `/tmp/ziti-sdk-android2` (Android SDK) for parity verification.

---

## 3. Tooling & CLI Baseline

### 3.1 Mandatory Toolchain
- Skip CLI (latest) with native license.
- Swift toolchain with Swift-for-Android components.
- Android SDK, NDK (for CZiti C targets), Gradle 8.x.
- Xcode 16+ (for iOS builds), Android Studio (for debugging generated Gradle projects).

### 3.2 Key Commands & Usage
| Stage | Command(s) | Purpose |
| --- | --- | --- |
| Environment validation | `skip checkup --native` | Verifies native prerequisites and runs sample build/test. |
| Workspace scaffold | `skip init --native-model SkipZiti SkipZiti` | Generates Skip Fuse SwiftPM package with native bridging. |
| Baseline build | `swift build --build-tests` | Compiles Darwin artifacts and unit tests. |
| Cross-platform tests | `skip test` | Runs Skip parity pipeline (Swift + Kotlin/Compose tests). |
| Android-only iteration | `skip android build` / `skip android test` | Invokes generated Gradle projects directly. |
| Project metadata | `skip version`, `skip doctor` (optional) | Captures CLI versioning for CI logs. |
| Release packaging | `skip export --release` | Produces distributable frameworks/AARs. |

> __Note:__ Skip CLI currently exposes `skip test`, `skip android build`, and `skip android test`. There is no standalone `skip build`; continue to use `swift build`/`swift test` for Darwin targets.

---

## 4. Architecture Blueprint

```
┌─────────────────────────────┐
│     SkipZiti (SwiftPM)      │
├─────────────┬───────────────┤
│ Shared      │ Platform Decks│
│ API Layer   │ (Apple/Android│
├─────────────┼───────────────┤
│ - Client    │ - ZitiSwift   │
│ - Identity  │   Bridge      │
│ - Services  │   (OpenZiti   │
│ - Events    │   Swift SDK)  │
├─────────────┼───────────────┤
│             │ - ZitiAndroid │
│             │   Bridge      │
│             │   (org.openziti│
│             │    :ziti-android)│
└─────────────┴───────────────┘
```

- **Shared API Layer:** Swift-first façade exposing enrollment, runtime events, tunnel APIs, and diagnostics consistently across platforms.
- **ZitiSwiftBridge (Apple):** Delegates to the official OpenZiti Swift SDK (`Ziti`, `CZiti`), handling libuv lifecycle, identity enrollment, and service/tunnel events, while persisting credentials through the Apple Keychain.
- **ZitiAndroidBridge (Skip/Android):** Transpiled Swift module that calls `org.openziti.android.Ziti` via Skip Fuse bridging (e.g., `.kotlin()` conversions and Skip Fuse Gradle configuration), managing AndroidKeyStore-backed enrollment, LiveData status, and tunnel operations.
- **SkipZitiUI:** Shared SwiftUI/Compose diagnostics surfaces and telemetry helpers layered on top of the shared API events.

---

## 5. Core Data & API Schema

### 5.1 Swift Types (Current Codebase)
- `struct SkipZitiConfiguration`: Controller URL, desired log level, optional metadata dictionary (nil-safe for Skip bridging), used to pass identity file paths and posture hints into bridges.
- `protocol SkipZitiPlatformBridge`: Contract for platform integrations (`start/shutdown/enroll/revoke/cachedIdentities`). Each bridge wraps the official OpenZiti SDKs and is responsible for emitting `SkipZitiClientEvent`s.
- `final class SkipZitiClient`: Shared orchestrator that injects a bridge, exposes `AsyncStream` events, and persists identities when a store is supplied.
- `struct SkipZitiIdentityRecord`: Canonical identity metadata (alias, controller URL, fingerprint, optional platform alias/metadata) with default enrollment timestamp handling.
- `enum SkipZitiClientEvent`: Shared event model (`starting`, `ready`, `identityAdded`, `identityRemoved`, `statusMessage`, `serviceUpdate`, `postureEvent`, `errorReported`, `stopped`) supporting richer telemetry.
- `struct SkipZitiServiceDescriptor` / `SkipZitiServiceUpdate`: Cross-platform service catalog describing intercepts, permissions, posture requirements, and update deltas.
- `struct SkipZitiPostureQueryEvent` / `SkipZitiReportedError`: Standard payloads for posture callbacks and surfaced bridge/runtime errors.

### 5.2 Example: Bootstrap & Event Handling
```swift
import SkipZiti

let configuration = SkipZitiConfiguration(
    controllerURL: URL(string: "wss://controller.example")!,
    metadata: [
        "identityFilePath": "/path/to/demo.zid",
        "identityOutputDirectory": "~/Documents/ZitiIdentities"
    ]
)

let bridge = ZitiSwiftBridge(identityName: "demo")
let store = SkipZitiInMemoryIdentityStore()
let client = try await SkipZiti.bootstrap(
    configuration: configuration,
    bridge: bridge,
    identityStore: store
)

for await event in client.events {
    switch event {
    case .ready(let identities):
        print("Ready with identities", identities)
    case .identityAdded(let record):
        print("New identity enrolled", record.alias)
    case .statusMessage(let message):
        print("Status:", message)
    default:
        break
    }
}
```

### 5.3 Example: `skip.yml`
```yaml
mode: native
bridging:
  enabled: true
  options:
    - kotlincompat
gradle:
  dependencies:
    implementation: |
      implementation(platform("org.openziti:ziti-bom:<version>"))
      implementation("org.openziti:ziti-android")
      implementation("com.goterl:lazysodium-android:5.0.2")
      implementation("net.java.dev.jna:jna:5.14.0")
```

---

## 6. Runtime Workflows

### 6.1 Identity Enrollment
1. Receive JWT input (file, deep link, provisioning API).
2. Application calls `SkipZitiClient.enroll(jwt:alias:)`.
3. The active bridge performs enrollment:
   - **Apple (current implementation):** `ZitiSwiftBridge` writes the JWT to disk, invokes `Ziti.enroll`, publishes `.identityAdded`, and optionally exports `.zid` files when `metadata["identityOutputDirectory"]` is supplied.
   - **Android (current implementation):** `ZitiAndroidBridge` forwards the JWT to `org.openziti.android.Ziti.enrollZiti`, relying on AndroidKeyStore persistence and emitting LiveData-backed `.identityAdded` events.
4. The shared client converts bridge results into `SkipZitiIdentityRecord` instances, persists them via the configured identity store, and emits `.identityAdded`.
5. **TODO:** Harden storage backends (beyond in-memory), reconcile Android alias naming, and add enrollment smoke tests that run under Skip/Gradle.

### 6.2 Client Bootstrap & Event Flow
1. Application boots the client via `SkipZiti.bootstrap(...)`, injecting a platform bridge and optional store.
2. The bridge initializes the upstream SDK:
   - **Apple:** `ZitiSwiftBridge` loads `metadata["identityFilePath"]`, calls `Ziti.runAsync` with posture callbacks, and emits `.ready`, `.serviceUpdate`, `.postureEvent`, and `.statusMessage` events.
   - **Android:** `ZitiAndroidBridge` calls `org.openziti.android.Ziti.init`, attaches `AsyncStream` observers for service updates, and emits `.ready`, `.serviceUpdate`, `.postureEvent`, `.errorReported`, `.identityAdded`, `.identityRemoved`.
3. Events flow through `SkipZitiClient.events` and are consumed by platform UIs / diagnostics.
4. **Current Blocker:** Skip parity builds fail to transpile some Swift collections/iterators into Kotlin (`Map<String,String>`, `Iterator` APIs). The event surface compiles for iOS but is unusable on the Kotlin side until we correct bridging-friendly patterns.

### 6.3 Diagnostics & Telemetry (Planned)
1. Structured logging hooks and telemetry aggregation will be layered on top of bridge events once tunnel/service data is exposed.
2. Shared SwiftUI/Compose diagnostics views remain pending until the richer event surface is available.

---

## 7. Development Phases & Activities

### Phase 0 – Environment & Governance **[DONE]**
- Commands: `skip checkup --native`, `skip version`, `swift --version`, `adb devices`.
- Actions: validated tooling/licensing, documented onboarding, configured secrets.
- Outputs: environment report, CI bootstrap ticket.

### Phase 1 – Scaffolding & Baseline Builds **[DONE]**
- Commands: `skip init --native-model SkipZiti SkipZiti`, `swift build --build-tests`, `skip test`.
- Actions: committed initial scaffold, added OpenZiti dependencies, set up Skip Fuse configuration.
- Outputs: repository structure, initial build badge, developer setup guide.

### Phase 2 – Apple Bridge Integration **[IN PROGRESS]**
- Commands: `swift test`, forthcoming `skip test` once bridging is stable.
- Completed: `ZitiSwiftBridge` boots `Ziti.runAsync`, emits service updates, posture callbacks, and structured errors; enrollment/export flows working.
- Remaining: automate bridge-specific tests (unit + integration), ensure Skip parity (no Kotlin output required but we need coverage guarding Swift-only behaviour), document posture metadata contract, and add resilience for missing metadata.

### Phase 3 – Android Bridge Integration **[IN PROGRESS – BLOCKED]**
- Commands: `skip android build` (passes), `skip test` (fails).
- Completed: `ZitiAndroidBridge` wraps `org.openziti.android.Ziti`, streams service updates via `AsyncStream`, enriches identity metadata, and tracks posture/status.
- Blockers: Kotlin transpilation fails on Swift dictionaries/iterators/URI conversions; until we adopt Skip-friendly collection helpers the Gradle harness cannot run. After that, add Android smoke tests, alias normalization, telemetry hooks, and ensure parity with Apple’s event surface.

### Phase 4 – Shared Services & UI **[NOT STARTED]**
- Planned: add shared tunnel abstractions, diagnostics UI, and example app flows once bridge data is complete.

### Phase 5 – Hardening & Release Prep **[NOT STARTED]**
- Planned: performance benchmarking, posture stress tests, documentation polish, release packaging once earlier phases conclude.

---

## 8. Testing & CI Strategy
- **Pipelines:** 
  - `ci-linux`: `swift build`, `swift test`, `skip test`.
  - `ci-android`: `skip android build`, `skip android test`, instrumentation tests (if applicable).
  - `ci-release`: `skip export --release`, notarization (Apple), Maven local publish.
- **Quality Gates:** Build matrix ≥98% pass rate, enrollment/tunnel integration tests must pass on simulator + emulator, code coverage ≥80% for core modules, telemetry exporters validated.
- **Performance Tests:** Automated latency benchmarks comparing Ziti tunnel vs direct network on representative Android hardware; fail gate if overhead >10%.

---

## 9. Documentation & Developer Experience
- **Core docs:** API reference (DocC + Markdown), onboarding guide, troubleshooting playbook, telemetry integration manual, sample app walkthrough.
- **Samples:** Skip Fuse app demonstrating enrollment UI, service call, diagnostics panel; additional CLI scripts to run `skip test` locally.
- **Release artifacts:** Swift Package index metadata, Android Maven coordinates, changelog, upgrade notes.

---

## 10. Risk Register & Mitigation
| Risk | Impact | Mitigation |
| --- | --- | --- |
| Swift-for-Android drift | Build failures | Pin toolchain versions, monitor Skip release notes, nightly `skip test` runs on latest toolchain. |
| Secure storage misconfiguration | Credential exposure | Threat modeling, integration tests simulating storage failures, defense-in-depth with hardware-backed keys. |
| Tunnel latency regression | Poor UX | Automated benchmarks, instrumentation metrics, fallback backoff strategies. |
| Documentation lag | Slow adoption | Allocate doc sprints each milestone, enforce doc PR checklist, internal reviews. |
| Controller configuration gaps | Enrollment failures | Draft controller playbook, run staging environment tests, automate configuration validation scripts. |

---

## 11. Appendices

### A. Command Cheat Sheet
```bash
# Validate environment (run before every major upgrade)
skip checkup --native

# Scaffold SkipZiti package
skip init --native-model SkipZiti SkipZiti

# Swift (Darwin) builds & tests
swift build --build-tests
swift test --filter SkipZitiCoreTests

# Skip parity tests (Swift + Kotlin/Compose)
skip test

# Android-specific iteration
skip android build
skip android test

# Generate release artifacts
skip export --release --project .
```

### B. Sample `Package.swift` Segment
```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SkipZiti",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "SkipZiti", targets: ["SkipZiti"])
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "0.9.0")
    ],
    targets: [
        .target(
            name: "SkipZiti",
            dependencies: [
                .product(name: "SkipFuse", package: "skip")
            ],
            plugins: [
                .plugin(name: "skipstone", package: "skip")
            ]
        ),
        .testTarget(
            name: "SkipZitiTests",
            dependencies: ["SkipZiti"]
        )
    ]
)
```

### C. Example CI Steps (GitHub Actions Snippet)
```yaml
name: ci
on:
  pull_request:
  push:
    branches: [main]

jobs:
  build:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4
      - name: Install dependencies
        run: brew install skiptools/tap/skip
      - name: Validate toolchain
        run: skip checkup --native
      - name: Swift build/tests
        run: |
          swift build --build-tests
          swift test
      - name: Skip parity tests
        run: skip test
```

---

## 12. Next Actions
1. **Align with Skip bridging model (done October 20, 2025):** Audited `Sources/SkipZiti/**` and updated Android-only Swift to follow the Skip guidance. `Sources/SkipZiti/Bridge/ZitiAndroidBridge.swift` and `Sources/SkipZiti/SkipZiti.swift` now wrap Android integrations with `#if SKIP && os(Android)` so native builds still compile while Skip transpilation targets Android only. Verified shared sources continue to sit behind `#if !SKIP_BRIDGE` and confirmed `Sources/SkipZiti/Skip/skip.yml` stays `mode: 'transpiled'` with `bridging: true`, matching the pattern in `../SkipRepos/skip-stripe/Sources/SkipStripe/Skip/skip.yml`. This section anchors back to the [Skip transpiled-mode documentation](https://skip.tools/docs/modes/) plus the `SkipStripe.swift` projection for cross-checking file layout.
2. **Resolve generated callback overrides:** Investigate why Skip emits `callback_*` helpers without the `override` modifier in `ZitiSwiftBridge.kt`. Compare with Skip Firebase projections (e.g., `../SkipRepos/skip-firebase/.build/plugins/outputs/.../SkipFirebaseMessaging.kt`) where overrides succeed. Update `SkipZitiPlatformBridge` if needed (`SharedTypes.swift`) to adopt the signature shape Skip expects or annotate methods so Skip suppresses redundant adapters. Link supporting documentation from [Skip docs on asynchronous bridging](https://skip.tools/docs/platformcustomization/).
3. **Expose posture model accessors to Kotlin:** Review Android posture types in `/tmp/ziti-sdk-android2/ziti-android/src/main/java/org/openziti/edge/model/` and adjust our `typealias`/extensions so Kotlin sees getters like `getId()` and `getTimeout()`. If necessary, add bridging helpers inside `#if SKIP` to mirror the sample approach in `../SkipRepos/skip-stripe/.build/plugins/outputs/.../SkipStripe.kt`.
4. **Re-run Kotlin parity:** After steps 1–3, execute `swift test` and `skip test --plain` to confirm `:SkipZiti:compileDebugKotlin` passes. Capture Gradle logs and update this document with the new status.
5. **Add bridge-focused tests:** Once parity compiles, extend Swift XCTest (`Tests/SkipZitiTests/ServiceDescriptorTests.swift`) and add Robolectric smoke coverage following the scaffolding in `../SkipRepos/skip-stripe/Tests/SkipStripeTests`. Ensure new tests use the bridged API so Skip generates Kotlin counterparts.
6. **Document metadata contracts:** Update inline comments and this plan with explicit requirements for `metadata["identityFilePath"]`, posture hints, and Android alias handling, referencing OpenZiti sample configurations under `/tmp/ziti-sdk-swift2` and `/tmp/ziti-sdk-android2`.
7. **Plan persistent storage & diagnostics:** Once Kotlin parity is reliable, prioritize work items for secure identity storage, diagnostics UI, and telemetry export, keeping references to the OpenZiti SDK samples and Skip repo examples for cross-platform parity.
8. **Monitor Darwin toolchain linkage:** Retain the `libclang_rt.profile_osx.a` force-load helper in `Package.swift` and note any Skip release notes that let us remove the workaround, as previously tracked.
