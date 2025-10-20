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

## 2.1 Current Status (October 19, 2025)
- **Shared Layer:** `SkipZitiConfiguration`, `SkipZitiClient`, and an in-memory identity store are implemented. The client accepts bridge implementations and streams events via `AsyncStream`.
- **Apple Bridge:** `ZitiSwiftBridge` boots the official OpenZiti Swift SDK, listens for context/service events, and supports enrollment through `Ziti.enroll`. *Open items:* expose richer service/tunnel metadata, posture callbacks, and automated tests once more native scenarios are available.
- **Android Bridge:** `ZitiAndroidBridge` (compiled under `SKIP`) wraps `org.openziti.android.Ziti`, handles identity enrollment/removal, and emits shared events. *Open items:* capture tunnel/service updates, improve alias handling, and add Android smoke tests.
- **Build & Tests:** `swift test` and `skip android build` now succeed against the new structure. Test coverage is intentionally minimal (one guard test) until additional behaviors land.
- **Known TODOs/Placeholders:** Diagnostics UI, tunnel APIs, posture telemetry, persistent identity stores, and parity-focused tests are outstanding. The Apple bridge currently expects `metadata["identityFilePath"]` (and optionally `identityOutputDirectory`) until dynamic identity management is wired.

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
- `struct SkipZitiConfiguration`: Controller URL, desired log level, and arbitrary metadata for bridge-specific configuration (for example, Apple identity file paths).
- `protocol SkipZitiPlatformBridge`: Contract for platform integrations (`start/shutdown/enroll/revoke/cachedIdentities`). Bridges wrap the official OpenZiti SDKs.
- `final class SkipZitiClient`: Shared orchestrator that wires an injected bridge to the shared event stream and optional identity storage.
- `struct SkipZitiIdentityRecord`: Canonical identity metadata surfaced back to callers (alias, controller URL, fingerprint, platform alias, arbitrary metadata).
- `enum SkipZitiClientEvent`: Shared event model (`starting`, `ready`, `identityAdded`, `identityRemoved`, `statusMessage`, `stopped`).

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
   - **Apple (current implementation):** `ZitiSwiftBridge` writes the JWT to disk, invokes `Ziti.enroll`, persists identity metadata, and optionally exports `.zid` files if `identityOutputDirectory` metadata is supplied.
   - **Android (current implementation):** `ZitiAndroidBridge` forwards the JWT to `org.openziti.android.Ziti.enrollZiti`, relying on the upstream SDK to persist into AndroidKeyStore and emitting identity-added events.
4. The shared client converts bridge results into `SkipZitiIdentityRecord` instances, optionally persists them via the configured identity store, and emits `.identityAdded` events.
5. **TODO:** Surface posture outcomes/errors uniformly and support persistent stores beyond the in-memory helper.

### 6.2 Client Bootstrap & Event Flow
1. Application boots the client via `SkipZiti.bootstrap(...)`, injecting a platform bridge.
2. The bridge initializes the upstream SDK:
   - **Apple:** `ZitiSwiftBridge` loads an existing identity (`identityFilePath`), calls `Ziti.runAsync`, and forwards context/service events into the shared event stream.
   - **Android:** `ZitiAndroidBridge` calls `org.openziti.android.Ziti.init`, observes LiveData identity events, and emits `.ready`, `.identityAdded`, and `.identityRemoved` events.
3. Events flow through `SkipZitiClient.events` for consumers (SwiftUI/Compose, diagnostics, etc.).
4. **TODO:** Extend bridges to expose tunnel/service catalogs, posture callbacks, and actionable telemetry.

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
- Commands: `swift test`.
- Completed: `ZitiSwiftBridge` boots `Ziti.runAsync`, emits shared events, supports enrollment/export of identities.
- Remaining: richer service/tunnel data, posture callbacks, improved error propagation, automated tests, documentation for metadata usage.

### Phase 3 – Android Bridge Integration **[IN PROGRESS]**
- Commands: `skip android build`, (future) `skip test` instrumentation suites.
- Completed: `ZitiAndroidBridge` wraps `org.openziti.android.Ziti`, handles identity lifecycle, Gradle dependencies aligned.
- Remaining: tunnel/service events, alias/status normalization, Android smoke tests, telemetry hooks.

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
1. Execute `skip checkup --native` and capture results in project log.
2. Scaffold the SkipZiti package with `skip init --native-model SkipZiti SkipZiti`, commit baseline structure.
3. Implement identity enrollment actor skeleton and add initial unit tests before proceeding to tunnel APIs.
