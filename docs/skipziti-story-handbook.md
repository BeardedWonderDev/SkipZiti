# SkipZiti Story Handbook

Use this handbook during AI-assisted coding sessions to translate backlog items into implementation steps. It distills the authoritative docs (`docs/brief.md`, `docs/openziti-sdk-review.md`, `docs/skip-fuse-framework.md`, `docs/skip-sdk-case-studies.md`, `docs/skipziti-implementation-plan.md`) into quick-reference guidance.

---

## 1. Modules & Responsibilities

| Module | Responsibility | Key References |
| --- | --- | --- |
| `SkipZitiCore` | Wrap OpenZiti C SDK (CZiti) via libuv loop, expose concurrency-safe entry points. | OpenZiti Swift analysis §Swift SDK. |
| `SkipZitiIdentity` | JWT enrollment, CSR generation, secure storage (Keychain/Android Keystore), identity lifecycle events. | OpenZiti Swift analysis §Enrollment; Implementation Plan §5. |
| `SkipZitiServices` | AsyncStream tunnels, service discovery, posture callbacks, HTTP intercept interceptors. | OpenZiti Swift analysis §Connection Layer & Interceptors; Implementation Plan §6. |
| `SkipZitiFuse` | Skip bridging (`skip.yml`), Kotlin façade wrappers, `AnyDynamicObject` utilities, Android-specific glue. | Skip Fuse deep dive §Bridging; Case Studies §§1–3. |
| `SkipZitiUI` | Shared SwiftUI/Compose status views, diagnostics panels, telemetry exports. | Implementation Plan §7; Brief §Diagnostics. |
| Samples/Docs | Showcase enrollment flow, service call, telemetry export; maintain onboarding materials. | Implementation Plan §§8–9; Case Studies cross-repo lessons. |

---

## 2. Story Intake Checklist
Before touching code, confirm:
1. **Scope fits module**: map acceptance criteria to a single module plus optional UI/samples.
2. **Dependencies known**: note CZiti updates, Skip CLI version, controller credentials.
3. **Tests planned**: identify unit/integration tests (Swift, Skip parity, Android-specific).
4. **Docs impact**: decide which docs/sample apps require updates.

If you cannot answer these, re-read the relevant source docs or request clarification.

---

## 3. Common Story Patterns

### 3.1 Enrollment Enhancements
- Touch `SkipZitiIdentity`.
- Reference JWT/CSR flow in OpenZiti Swift SDK doc.
- Tests: actor unit tests, integration using mock controller, `skip test`.
- Docs: update onboarding guide and implementation plan if flow changes.

### 3.2 Tunnel/Service Features
- Modify `SkipZitiServices` and possibly `SkipZitiCore`.
- Ensure AsyncStream semantics align with libuv callbacks.
- Add posture handling per brief KPIs; update service descriptors.
- Tests: concurrency unit tests, parity tests, optional emulator smoke.

### 3.3 Android Bridging Work
- Update `SkipZitiFuse` `skip.yml`, Kotlin façade files.
- Use case-study patterns (`#if SKIP`, `KotlinConverting`, `SkipFFI`).
- Run `skip android build`/`skip android test`.

### 3.4 UI/Diagnostics
- Work in `SkipZitiUI` and sample app.
- Mirror SwiftUI features in Compose (Skip handles bridge); guard complex generics.
- Validate via `swift test --filter SkipZitiUITests` and `skip test`.

---

## 4. Testing Expectations
- **Unit Tests:** `swift test` required for impacted modules.
- **Parity Tests:** `skip test` mandatory when touching shared code or bridging.
- **Android Builds:** `skip android build`/`skip android test` when editing Gradle, Kotlin, or native bindings.
- **Performance/Telemetry:** Evaluate tunnel latency or posture performance for relevant stories ( ≤10% overhead target).

Document executed commands in PR summaries.

---

## 5. Documentation & Sample Updates
- Check `docs/skipziti-implementation-plan.md` for phase alignment; update if diverging.
- Update onboarding (`docs/skipziti-dev-onboarding.md`) when environment steps change.
- Refresh sample app instructions or code snippets for newly exposed APIs.

---

## 6. Definition of Done (per story)
1. Code adheres to module boundaries above.
2. Tests and validations executed and passing.
3. Docs/samples updated.
4. Risks or assumptions noted if new constraints discovered.
5. Story file (if used) updated only in allowed sections (per dev agent rules).

---

## 7. Quick Reference Snippets

### Enrollment Mock Test Skeleton
```swift
func testEnrollPersistsIdentity() async throws {
    let storage = InMemoryIdentityStore()
    let controller = MockControllerClient(result: .success(MockSignedIdentity()))
    let manager = ZitiIdentityManager(storage: storage, controller: controller)

    let outcome = try await manager.enroll(jwtData: Data("mock".utf8))
    guard case .success(let record) = outcome else {
        XCTFail("Expected success"); return
    }
    XCTAssertEqual(record.controller.host, "edge.example")
}
```

### Android Bridging Guard
```swift
#if SKIP
import SkipBridge

extension ZitiAndroidConnector: KotlinConverting {
    // Conversion helpers
}
#endif
```

---

## 8. Escalation Paths
- Tooling issues: revisit Skip CLI docs or contact maintainer.
- Controller/policy blockers: sync with OpenZiti environment owner.
- Scope ambiguity: align with implementation plan phases or update the plan before coding.

Keep this handbook open during sessions to stay aligned with project architecture and delivery standards.

