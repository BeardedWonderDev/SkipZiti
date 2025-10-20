# SkipZiti

Cross-platform Swift SDK work-in-progress that wraps the official [OpenZiti](https://openziti.github.io/ziti/overview.html) Apple and Android SDKs through [Skip Fuse](https://skip.tools/docs/modules/skip-fuse/). The goal is to expose a single Swift API that applications can compile for iOS and Android, while receiving the same enrollment, service, posture, and diagnostic signals from each platform.

> **Project status (October&nbsp;2025):** Active development, pre-alpha quality. Shared plumbing and bridge scaffolding exist, but the Kotlin transpilation step currently fails, so the parity (`skip test`) pipeline and Gradle smoke suites do not run. No production tunnel APIs or diagnostics UI have been implemented yet.

---

## Components & Capabilities

| Layer | What works today | Outstanding work |
| --- | --- | --- |
| Shared Types & Client | `SkipZitiConfiguration`, `SkipZitiClient`, `SkipZitiIdentityRecord`, `SkipZitiServiceDescriptor`, `SkipZitiServiceUpdate`, `SkipZitiPostureQueryEvent`, `SkipZitiReportedError` and an in-memory identity store. Events flow through `AsyncStream<SkipZitiClientEvent>`. | Persistent identity storage, public tunnel APIs, diagnostics utilities, richer error handling. |
| Apple Bridge (`ZitiSwiftBridge`) | Boots the OpenZiti Swift SDK, emits context/service updates, posture callbacks, enrollment results, and structured error/status messages. | Automated bridge tests, doc updates for metadata contracts, resilience when posture metadata is absent. |
| Android Bridge (`ZitiAndroidBridge`) | Wraps `org.openziti.android.Ziti`, emits identity/service updates, posture events, and status/error metadata. | Fix Skip/Kotlin transpilation (dictionary and iterator conversions), smoke/Gradle tests, alias normalization, telemetry hooks. |

---

## Requirements

- Xcode 16+, Swift 6 toolchain.
- Skip CLI `1.6.27` or newer with native-mode support (licensed).
- Android SDK 33+, Java 11, Gradle 8.x.
- Access to an OpenZiti controller for integration testing.

Run once after cloning:

```bash
brew install skiptools/skip/skip
skip checkup --native
```

---

## Building & Testing

```bash
# Build Apple targets
swift build

# Run Swift unit tests
swift test        # currently fails because the transpiled Kotlin step fails

# Build Android artefacts (transpiled Kotlin only)
skip android build

# Run parity tests (Swift + Kotlin) – currently fails during :SkipZiti:compileDebugKotlin
skip test --plain
```

Known failure: `skip test` and `swift test` abort during the Kotlin compile phase with messages such as `Argument type mismatch: actual type is 'Dictionary<String, String>', but 'Map<String, String>' was expected`. Resolving these requires refactoring the Swift collections/iterators in the shared layer and Android bridge to use Skip-compatible helpers.

---

## Current Roadmap

1. Refactor shared types/bridges to eliminate Skip→Kotlin collection issues and restore the parity pipeline.
2. Add automated coverage (Swift unit tests + Gradle smoke tests) for service/posture/error events on both bridges.
3. Introduce secure/persistent identity storage implementations.
4. Layer on tunnel APIs, diagnostics UI, and telemetry exporters.
5. Harden performance (≤10 % tunnel latency overhead target) and release packaging.

For a detailed breakdown, see [`docs/skipziti-implementation-plan.md`](docs/skipziti-implementation-plan.md).

---

## Contributing

Pull requests and issues are welcome, but expect rapid iteration and breaking changes until the parity pipeline, storage, and diagnostics pieces are in place. Please include:

- `swift build`, `swift test`, and `skip android build` outputs.
- `skip test` results (even if failing) with notes about any new regressions.
- Updates to the implementation plan when scope or status changes.

---

## License

SkipZiti is released under the [MIT License](LICENSE). The project depends on LGPL-licensed Skip components (with linking exceptions) and Apache-licensed OpenZiti SDKs. See the license table in the implementation plan for redistribution guidance.
