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
│ SkipZitiCore│ CZiti Bridge  │
│ (Swift + C) │ libuv loop    │
├─────────────┼───────────────┤
│ SkipZitiIdentity (actors,   │
│ JWT enroll, secure storage) │
├─────────────┼───────────────┤
│ SkipZitiServices (tunnels,  │
│ intercepts, posture)        │
├─────────────┼───────────────┤
│ SkipZitiFuse (bridging,     │
│ AnyDynamicObject adapters)  │
├─────────────┼───────────────┤
│ SkipZitiUI (SwiftUI/Compose │
│ diagnostics)                │
└─────────────┴───────────────┘
```

- **SkipZitiCore:** Wraps OpenZiti C SDK via `@_cdecl` hooks; owns libuv loop and concurrency queues.
- **SkipZitiIdentity:** Swift actors for JWT enrollment, CSR generation, Keychain & Skip-secured Android Keystore adapters.
- **SkipZitiServices:** AsyncStream-based tunnels, HTTP interceptors, posture callbacks, policy reconciliation.
- **SkipZitiFuse:** Skip bridging configuration (`skip.yml`), Kotlin façade wrappers using `KotlinConverting`, `AnyDynamicObject`, and `SKIP INSERT` annotations when required.
- **SkipZitiUI:** Shared observability surface with SwiftUI/Compose components and telemetry export hooks.

---

## 5. Core Data & API Schema

### 5.1 Swift Types
- `struct SkipZitiConfiguration`: controller URL, logging level, storage adapters, telemetry sinks.
- `actor ZitiIdentityManager`: handles enroll/load/revoke flows.
- `struct ZitiIdentityRecord`: controller metadata, certificate fingerprint, storage alias, posture state.
- `struct ZitiServiceDescriptor`: service ID, intercept configs, posture requirements, preferred dial modes.
- `struct TunnelChannel`: endpoints for `AsyncStream<Data>` reads, `send(_:)`, cancellation, metrics snapshot.
- `enum EnrollmentResult`: `.success(ZitiIdentityRecord)`, `.postureViolation(details)`, `.failure(SkipZitiError)`.

### 5.2 Example: Enrollment Actor
```swift
import SkipZitiCore

actor ZitiIdentityManager {
    private let storage: SecureIdentityStore
    private let controller: ControllerClient

    init(storage: SecureIdentityStore, controller: ControllerClient) {
        self.storage = storage
        self.controller = controller
    }

    func enroll(jwtData: Data) async throws -> EnrollmentResult {
        let csr = try CSRBuilder(jwt: jwtData).make()
        let signedIdentity = try await controller.enroll(csr: csr)
        let record = try storage.persist(identity: signedIdentity)
        return .success(record)
    }

    func loadCached() async throws -> [ZitiIdentityRecord] {
        try storage.fetchAll()
    }
}
```

### 5.3 Example: Async Tunnel Usage
```swift
let client = try await ZitiClient.bootstrap(
    SkipZitiConfiguration(controller: URL(string: "wss://edge.example")!,
                          storage: KeychainStorage(),
                          logger: .default)
)

for await event in client.events {
    if case .ready(let services) = event,
       let orders = services.named("orders-api") {
        let channel = try await client.tunnels.open(service: orders,
                                                    options: .init(mode: .stream))
        try await channel.send(Data("ping".utf8))

        for await response in channel.messages {
            print("Received:", response)
        }
    }
}
```

### 5.4 Example: `skip.yml`
```yaml
mode: native
bridging:
  enabled: true
  options:
    - kotlincompat
gradle:
  dependencies:
    implementation: |
      implementation("org.openziti:ziti-android:<version>")
  externalNativeBuild:
    cmake:
      path: Sources/CZitiAndroid/CMakeLists.txt
```

---

## 6. Runtime Workflows

### 6.1 Identity Enrollment
1. Receive JWT (file, deep link, provisioning API).
2. `ZitiIdentityManager.enroll` generates CSR, submits to controller, stores key/cert via platform adapter.
3. Persist `ZitiIdentityRecord` to encrypted cache; emit `.identityAdded` event.
4. Trigger policy reconciliation and posture validation sequence.

### 6.2 Client Bootstrap & Service Resolution
1. Application calls `ZitiClient.bootstrap(configuration:)`.
2. Core spins libuv loop, registers event callbacks, hydrates stored identities.
3. On `.ready`, expose `ZitiServiceDescriptor` catalog to shared SwiftUI state.
4. Services consumed via `client.tunnels.open` or intercepted HTTP contexts.

### 6.3 Diagnostics & Telemetry
1. Structured logging via SkipFuse logging API; logs emitted with Ziti context IDs.
2. Telemetry actor aggregates tunnel metrics, posture results, enrollment history.
3. UI layer presents diagnostics dashboard; Android Compose view auto-generated by Skip.
4. Optional export: `client.telemetry.export(to:)` writes compliance bundle for auditors.

---

## 7. Development Phases & Activities

### Phase 0 – Environment & Governance
- Commands: `skip checkup --native`, `skip version`, `swift --version`, `adb devices`.
- Actions: validate licenses, document onboarding steps, configure secrets (e.g., `SKIPKEY`, controller credentials).
- Outputs: environment report, CI bootstrap ticket.

### Phase 1 – Scaffolding & Baseline Builds
- Commands: `skip init --native-model SkipZiti SkipZiti`, `swift build --build-tests`, `skip test`.
- Actions: commit scaffold, wire CZiti submodule, ensure `Package.swift` lists Skip dependencies, annotate `Skip/skip.yml`.
- Outputs: repository structure, initial build badge, developer setup guide.

### Phase 2 – Core Runtime & Identity Layer
- Commands: `swift test --filter SkipZitiCoreTests`, `skip test`, `skip android build --project .`.
- Actions: implement libuv bridge, identity actors, Keychain + Skip storage, baseline telemetry hooks.
- Outputs: passing unit tests, documented API surface, architecture ADR.

### Phase 3 – Services, Policies, Bridging
- Commands: `swift test --filter SkipZitiServicesTests`, `skip test`, `skip android test`.
- Actions: AsyncStream tunnels, HTTP interceptors, posture handling, Kotlin façade wrappers (`#if SKIP`), Gradle dependency injections.
- Outputs: service API docs, Kotlin stub validation report, integration test plan.

### Phase 4 – Diagnostics & UI/UX
- Commands: `swift test --filter SkipZitiUITests`, `skip test`, device smoke tests (`skip android test --devices pixel_6` when configured).
- Actions: SwiftUI diagnostics overlays, Compose parity, telemetry export, sample app instrumentation.
- Outputs: screenshots, UX checklist, telemetry documentation.

### Phase 5 – Hardening & Release Prep
- Commands: `swift test`, `skip test`, `skip android build --release`, `skip export --release`.
- Actions: performance benchmarking, posture edge-case tests, doc polish, release notes, version tagging.
- Outputs: release artifacts, changelog, maintenance runbook.

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
skip android build --project .
skip android test --project .

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

