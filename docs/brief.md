# Project Brief: SkipZiti

## Introduction
- **Project Name:** SkipZiti
- **Initiative Summary:** Build a cross-platform Swift SDK that embeds OpenZiti zero-trust networking into Skip Fuse-based Swift/SwiftUI apps targeting iOS and Android from a unified codebase.
- **Primary Problem & Audience:** Swift/SwiftUI developers lack a production-ready path to integrate OpenZiti capabilities into multi-platform mobile projects, leading to fragile native workarounds.
- **Urgency & Timing:** No equivalent SDK exists today, and an active project depends on delivering this capability immediately.
- **Existing Inputs:** Research and technical groundwork stored under `docs/` supply architecture references, requirements, and background.
- **Constraints:** No preset budget, timeline, or additional tech-stack limits beyond using Skip Fuse + Swift/SwiftUI.
- **Stakeholders:** Single stakeholder (you) driving vision, implementation, and validation.
- **Definition of Success:** A working, reusable cross-platform Swift SDK that cleanly exposes OpenZiti features through Skip Fuse for iOS and Android targets.

## Executive Summary
SkipZiti is a cross-platform Swift SDK that layers OpenZiti’s zero-trust networking capabilities into Skip Fuse so Swift/SwiftUI developers can deliver secure iOS and Android apps from a single codebase. It solves the absence of a production-ready OpenZiti integration in the Swift ecosystem, removing the need for brittle native wiring. Target users are Swift teams building multi-platform mobile experiences that require embedded zero-trust access. The value proposition is a first-class Skip Fuse module that offers turnkey OpenZiti enrollment, policy enforcement, and secure tunnels without juggling multiple platform-specific implementations.
## Problem Statement
- **Current State & Pain Points:** OpenZiti ships an official Swift SDK that works well on iOS, but it is tightly coupled to Apple-only dependencies and fails to build in the Swift Android runtime. Skip Fuse teams aiming for shared Swift/SwiftUI code still end up writing bespoke JNI bindings or duplicating networking logic per platform to reach Android parity.
- **Impact & Quantification:** Maintaining separate networking stacks across iOS and Android adds weeks of engineering effort per project, introduces divergence in security posture, and inflates the long-tail maintenance burden for every release.
- **Why Existing Solutions Fall Short:** The existing Swift SDK doesn’t target Android, and there is no Skip Fuse wrapper that abstracts OpenZiti’s identity enrollment, policy channels, or secure tunnels for shared Swift code. Community experiments lack sustained support, testing, or documentation for production use.
- **Urgency & Importance:** Your active project depends on deploying zero-trust networking across both platforms now; without a cross-platform SDK, delivery stalls or ships with asymmetric security. Creating SkipZiti unlocks this project and provides a reusable foundation for future Swift-first teams.

## Proposed Solution
SkipZiti delivers a single Swift package that compiles under the Skip Fuse toolchain for iOS and Android, wrapping OpenZiti’s C SDK so developers can call strongly typed Swift APIs from shared code. The package defines a `ZitiClient` facade with async Swift concurrency support for identity enrollment, controller negotiation, service discovery, and policy-driven channel lifecycle. Under the hood, platform-specific shims expose socket primitives, certificate/key storage, and background task scheduling via Skip Fuse bindings—no JNI or Objective-C bridging is required.

**Key Architectural Elements**
- **Core Runtime Layer:** A Swift module bridging to OpenZiti’s C library using `@_cdecl` entry points and Swift’s C interop. Provides thread-safe queues and structured logging so both platforms share diagnostics.
- **Identity & Enrollment Subsystem:** Swift actors handling JWT bootstrap, PKI material storage, and controller registration. On iOS it stores identities in the keychain; on Android it leverages Skip Fuse secure storage abstractions that map to Android Keystore.
- **Service & Channel API:** High-level builders for service registration, interceptors for policy updates, and stream abstractions that wrap tunnels. Developers work with `AsyncSequence`/`AsyncStream` instead of manually managing sockets.
- **Skip Fuse Integration:** Package exports `@SkipModule` components so UI code can declare Ziti-backed resources in the Skip DSL. Dependency injection macros allow preview/test scaffolds without the live controller.
- **Diagnostics & Compliance Hooks:** Built-in telemetry surfaces connection state, policy enforcement outcomes, and audit events. These feed into both debugging UIs and compliance logs so security reviewers can attest to zero-trust posture, enrollment history, and tunnel integrity.

**Differentiators vs Existing Offerings**
1. **Cross-Platform Parity:** CI pipelines validate builds against Skip Fuse’s iOS and Swift Android targets, guaranteeing identical functionality and tests for both runtimes.
2. **Security by Design:** Identity lifecycle is automated with revocation, re-enrollment, and policy reconciliation baked in; secrets never leave secure enclaves, satisfying zero-trust requirements.
3. **Developer Ergonomics:** Async/await-first APIs, Skip Fuse instrumentation, and guardrails (retry, offline handling) reduce cognitive load for app teams implementing the SDK.
4. **Operational Readiness:** Shipping example apps, integration tests, and documentation sourced from the existing research docs ensure teams can audit, extend, and support the SDK in production environments.

By leaning on Skip Fuse rather than ad-hoc bridges, SkipZiti keeps the Android runtime native to Swift, avoiding undefined behavior from JNI wrappers and ensuring future Skip Fuse platform targets can inherit the same abstractions. The roadmap envisions plug-in adapters for observability, policy analytics, and eventual support for desktop Swift targets, positioning SkipZiti as the de facto zero-trust networking layer for the Skip ecosystem.

## Target Users
- **Primary User Segment:** Swift-first cross-platform mobile teams—Swift/SwiftUI engineers at product companies or consultancies delivering iOS-first experiences who must maintain Android parity without duplicating effort. They rely on Skip Fuse to compile shared Swift into native Android binaries and currently juggle fragile JNI bridges to reach OpenZiti on Android. Their goal is a single Swift SDK that handles identity enrollment, secure tunnels, and policy updates identically on iOS and Android so they can focus on product features while keeping release cadence tight.
- **Secondary User Segment:** Security and platform engineering teams in regulated SaaS, DevOps tooling, operational technology, or federal projects rolling out OpenZiti-backed zero-trust overlays across mobile fleets. They need uniform enrollment workflows, posture checks, and policy telemetry across both operating systems plus integration hooks for observability stacks, enabling them to operationalize zero-trust in Swift apps without platform-specific agents or exposed ports.

## Goals & Success Metrics
- **Business Objectives**
  - Launch SkipZiti v1.0 to support your current project’s shipment by February 2026, enabling feature parity across iOS and Android.
  - Establish SkipZiti as the canonical OpenZiti integration for Skip Fuse by onboarding at least one external adopter or open-source collaborator within six months of release.
  - Reduce long-term maintenance cost by consolidating cross-platform networking code into a single Swift package, freeing two developer-months per release cycle that were previously spent on platform-specific fixes.
- **User Success Metrics**
  - Development teams integrate SkipZiti into a new Skip Fuse app in under one sprint (≤2 weeks) with documented end-to-end sample flows.
  - Achieve ≥95% success rate for automated enrollment and tunnel establishment across supported services in CI pipelines.
  - Maintain SDK-level crash rate below 0.1% across mobile sessions, signaling stability of the shared networking stack.
- **Key Performance Indicators (KPIs)**
  - SDK Build Matrix Pass Rate: ≥98% green runs across iOS (arm64) and Android (arm64/armv7) targets per release.
  - Secure Tunnel Latency Overhead: ≤10% added latency compared with direct network access when measured via integration benchmarks.
  - Documentation & Sample Coverage: 100% of public APIs covered with code snippets or runnable examples, audited quarterly.

## MVP Scope
- **Core Features (Must Have)**
  - **Cross-Platform Build Pipeline:** Unified Swift Package Manager setup and CI scripts that compile and run the OpenZiti C bindings under Skip Fuse targets for iOS (arm64, simulator) and Android (arm64, armv7).
  - **Identity & Enrollment API:** Async Swift actors for JWT bootstrap, identity material creation, secure storage (iOS Keychain, Skip-backed Android keystore), and controller registration.
  - **Secure Channel Abstractions:** `AsyncSequence` / `AsyncStream` based tunnel wrappers that expose send/receive streams, policy enforcement callbacks, and lifecycle management (connect, resume, teardown) without JNI glue.
  - **Skip Fuse Integration Layer:** Annotated `@SkipModule` components and dependency injection macros enabling Skip declarative resources and previews/tests without live controllers; includes sample Skip app demonstrating integration.
  - **Diagnostics Toolkit:** Structured logging, metrics hooks, and configurable alerts for tunnel health, policy updates, and enrollment errors, wired into Skip Fuse logging infrastructure.
- **Out of Scope for MVP**
  - Desktop Swift (macOS) or server-side support.
  - Advanced observability plugins (Prometheus exporters, distributed tracing integrations).
  - Automated policy orchestration or controller management tools.
  - Non-Swift Fuse platforms (React Native, Flutter) or non-mobile targets.
- **MVP Success Criteria**
  Successful completion occurs when SkipZiti builds cleanly on CI for both mobile targets, integrates into a reference Skip app that establishes OpenZiti tunnels end-to-end, passes integration tests covering enrollment/tunnel lifecycle/policy updates, and publishes developer documentation plus code samples sufficient for a new team to integrate within two weeks.

## Post-MVP Vision
- **Phase 2 Features**
  - Deliver desktop Swift (macOS) support so the same SkipZiti module powers native workstation clients and developer tooling.
  - Introduce optional observability adapters (Prometheus metrics exporter, OpenTelemetry spans) for operations teams needing centralized monitoring.
  - Publish plug-in points for custom identity providers (e.g., enterprise IdPs) and policy orchestration, enabling enterprises to align SkipZiti with existing onboarding workflows.
- **Long-term Vision**
  Expand SkipZiti into the canonical zero-trust connectivity layer across the Skip ecosystem: universal Swift package, shared policy grammar, and turnkey tooling that lets any Skip Fuse or future Skip-compatible target (watchOS, visionOS, Windows via Swift runtime) inherit OpenZiti security. Pair the SDK with starter templates, CI/CD blueprints, and managed controller options so teams ship secure mesh networking without touching low-level Ziti configuration. The long-range aim is an ecosystem where Swift developers treat zero-trust tunnels as a declarative resource, not bespoke infrastructure.
- **Expansion Opportunities**
  - Offer a managed SkipZiti “control plane in a box” that bundles OpenZiti controller hosting, identity lifecycle automation, and analytics dashboards.
  - Partner with Skip tooling vendors to integrate SkipZiti into project scaffolds and dev environment provisioning.
  - Explore SDK variants for other declarative runtimes (e.g., Kotlin Multiplatform, Rust) using the same architectural patterns, creating a family of OpenZiti SDKs with consistent ergonomics.

## Risks & Open Questions
- **Key Risks**
  - **Swift-for-Android Compatibility Drift:** Skip Fuse or Swift toolchain updates could break OpenZiti C interop, delaying releases.
  - **Identity Security Across Platforms:** Misconfigured secure storage or policy handling might expose keys or weaken zero-trust guarantees.
  - **Performance Regression:** Ziti tunnel initialization or latency overhead may exceed the ≤10% target on lower-end Android hardware.
  - **Documentation Debt:** Limited author bandwidth may slow onboarding content, undermining the 2-week integration goal.

- **Open Questions**
  - Which portions of the existing OpenZiti controller fleet require configuration changes to support mobile identities and policy channels?
  - Do we need dedicated QA devices or emulators for broader Android hardware coverage beyond Skip Fuse defaults?
  - How will we sustain SDK maintenance (versioning, issue triage) once external adopters appear?

- **Areas Needing Further Research**
  - Validate Skip Fuse roadmap for upcoming Android runtime changes and M-series Apple hardware updates.
  - Benchmark end-to-end tunnel performance under representative workloads to confirm latency targets.
  - Investigate observability integration patterns (OpenTelemetry, Prometheus) for the planned Phase 2 adapters.

## Appendices
### C. References
- docs/openziti-sdk-review.md
- docs/skip-fuse-framework.md

## Next Steps
- **Immediate Actions**
  1. Audit the `docs/openziti-sdk-review.md` research against latest OpenZiti releases to confirm API parity.
  2. Run `skip checkup --native` and validate Swift-for-Android toolchain plus Skip Fuse licensing on your build machines.
  3. Draft the initial `SkipZiti` SwiftPM package skeleton (`skip init --native-model`) and verify shared builds for iOS/Android.
  4. Outline the enrollment/tunnel integration tests that will back CI success criteria.
- **PM Handoff**
  This Project Brief provides the full context for SkipZiti. Please start in “PRD Generation Mode,” review the brief thoroughly, and work with stakeholders to create the PRD section by section per the template, confirming assumptions or suggesting improvements as needed.
