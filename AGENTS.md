# Repository Guidelines

## Project Structure & Module Organization
SkipZiti is a Swift Package (see `Package.swift`) with runtime code in `Sources/SkipZiti`. Shared domain models live under `Shared`, bridging layers under `Bridge` (Apple `ZitiSwiftBridge.swift`, Android `ZitiAndroidBridge.swift`), platform-specific entry points in `Skip`. Resources such as enrollment templates sit in `Resources`. XCTest suites are in `Tests/SkipZitiTests`, with parity harness scaffolding inside `Tests/SkipZitiTests/Skip`. Architecture docs and roadmap updates belong in `docs/`.

## Build, Test, and Development Commands
`swift build` compiles the Swift targets for Apple platforms. `swift test` exercises the XCTest suites; run even though the Kotlin transpile step currently fails to capture regressions. `skip android build` emits the Android artefacts via Skip Fuse. `skip test --plain` runs the parity pipeline (Swift + transpiled Kotlin) and surfaces Kotlin bridge errors. After workstation setup, run `skip checkup --native` once to ensure the Skip toolchain is aligned.

## Coding Style & Naming Conventions
Use Swift 6 features and maintain four-space indentation. Prefer `final` classes and `struct` models that conform to `Sendable` when crossing async boundaries. Names should match platform conventions: `UpperCamelCase` for types/protocols, `lowerCamelCase` for properties and methods, and `caseType` enums with explicit associated values. Keep bridge surfaces symmetrical between Apple and Android, mirroring method names and payload structs. When touching public APIs, update documentation comments so Skip's transpiler retains context.

## Testing Guidelines
Unit tests rely on XCTest with async test helpers in `Tests/SkipZitiTests/Support`. Name methods `testScenarioExpectation`. Until Kotlin collection mismatches are fixed, record the failure signature in the PR. Add focused tests for bridge regressions by extending the stubs in `Tests/SkipZitiTests/Skip`. Coordinate with Android parity by running the Gradle smoke tests when Kotlin compilation recovers.

## Commit & Pull Request Guidelines
Commits follow short, present-tense summaries (`Update bridge error surfaces`). Aim for one logical change per commit and include scoped details in the body when touching multiple layers. Pull requests should describe the user-visible impact, reference docs updated (e.g., `docs/skipziti-implementation-plan.md`), and attach `swift build`, `swift test`, `skip android build`, and `skip test --plain` outputs or failure excerpts. Add screenshots or logs when surface-level behavior changes, and tag reviewers responsible for the affected platform bridge.
