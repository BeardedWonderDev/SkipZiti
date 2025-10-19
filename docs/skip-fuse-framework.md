# Skip Fuse Framework Deep Dive

This document distills the Skip documentation into a single reference for building a Swift Package-based Skip Fuse SDK that can target both iOS and Android. Each section calls out the specific Skip features and workflows that matter when you are bridging platform SDKs—such as OpenZiti—into a unified Skip Fuse experience.

## 1. Skip Fuse Essentials

- **Native-first architecture.** Skip Fuse is Skip’s “native mode,” compiling Swift directly to Android binaries via the Swift-for-Android toolchain while still building the same sources for Apple platforms. The framework layers in Android OS integrations (logging, networking, observables) and prebuilt JNI bridges so the resulting binaries slot naturally into Android apps without writing manual glue.[^modes][^fuse]
- **Contrast with Skip Lite.** Skip Lite transpiles Swift into Kotlin source, yielding faster builds, human-readable output, and smaller APKs, but at the cost of language feature gaps and lower native parity. Fuse sacrifices some build performance and package size to keep full Swift semantics and runtime behavior intact—an important trade when wrapping complex Swift APIs such as networking stacks.[^modes][^status]
- **Core runtime services.** Skip Fuse ships umbrella libraries (e.g., `SkipFuse`, `SkipFuseUI`) that expose OSLog on Android, mirror Swift `@Observable` state into Jetpack Compose, and provide `AnyDynamicObject` so compiled Swift can call Kotlin/Java APIs with minimal ceremony—ideal for invoking Android-only OpenZiti entry points while retaining Swift ergonomics.[^fuse][^modes]
- **Tooling integration.** The SkipStone build plugin embeds in Xcode and SwiftPM so a single `swift build`/`swift test` run can compile Swift for iOS, generate Android artifacts, and run Kotlin-side tests. Keep Android Studio available for emulator management, but Skip orchestrates Gradle builds automatically.[^gettingstarted][^faq]

## 2. Project Structure & Tooling

- **Scaffolding packages.** Use `skip init --native-model <folder> <ModuleName>` to scaffold a Skip Fuse SwiftPM package. The generator adds paired Swift targets, configures `skip.yml` for native mode, wires in the `skipstone` plugin, and creates `Tests/` targets that exercise both iOS and Android builds.[^gettingstarted][^cli]
- **Dependencies & Package.swift.** Native modules typically depend on `SkipFuse` plus supporting runtime libraries like `SkipModel` when using `@Observable` state. Ensure `Package.swift` includes the Skip Git dependencies (`skip.git`, `skip-fuse.git`, etc.) and attaches the `skipstone` build plugin so SwiftPM invokes Skip’s cross-platform pipeline.[^kotlincompat][^modes]
- **Build and test flows.** `swift build` compiles the Darwin artifacts, while `swift test` (or `skip test`) triggers the Android toolchain, compiles native Swift into `.so` libraries, and executes mirrored Kotlin tests through Robolectric. Integrate these commands in CI to guarantee parity across both runtimes.[^gettingstarted][^modes]
- **Environment validation.** Before wiring the OpenZiti SDKs, run `skip checkup --native` to confirm Swift-for-Android, Gradle, and Android SDK prerequisites. Pair this with `skip upgrade` to keep the CLI current and `skip android sdk install` when onboarding machines.[^faq]
- **Gradle artifacts.** Skip-generated Android projects place build outputs in `.build/Android/` and can be opened directly in Android Studio when deeper Gradle customization is required (e.g., packaging OpenZiti binaries).[^platform]

## 3. Bridging Configuration

- **`skip.yml` as the control center.** Every Skip module includes `Sources/<Module>/Skip/skip.yml`. Setting `mode: native` tells Skip to compile Swift natively for Android. Enabling `bridging` projects Swift APIs into Kotlin and exposes Kotlin/Java APIs back to Swift; add `options: kotlincompat` when the Android side is pure Kotlin, improving nullability and collection translations.[^modes][^kotlincompat]
- **Generated surfaces.** Skip automatically generates Kotlin stubs for your public Swift API (classes, structs, enums) so they feel idiomatic to Kotlin callers. Conversely, Swift sources can import bridged Kotlin types as if they were native Swift, reducing the need for JNI wrappers when wrapping OpenZiti’s Kotlin SDK.[^modes]
- **`AnyDynamicObject` escape hatch.** When you need to call individual Kotlin/Java APIs without configuring full module bridging, construct `AnyDynamicObject` instances. They dynamically invoke methods, properties, and constructors on Kotlin/Java classes, letting Swift code reach Android services or third-party SDKs incrementally.[^modes][^fuse]
- **Visibility rules.** Skip lifts Swift access control into generated Kotlin. Keep types and members `internal` or `public` when they must be visible to Android code. Private Swift symbols remain unexported and cannot be bridged.[^modes]
- **Mixed-mode strategies.** Native and transpiled modules can coexist. You might host heavy Swift networking logic (OpenZiti) in a native Fuse module, while lighter helpers remain transpiled for faster builds. `skip.yml` governs the mode per module, making incremental adoption straightforward.[^modes][^gettingstarted]

## 4. UI & Compose Integration

- **SkipFuseUI bridge.** Import `SkipFuseUI` in shared SwiftUI view code. On iOS it aliases to `SwiftUI`; on Android it bridges every SwiftUI control, modifier, and observable binding through the `SkipUI` layer into Jetpack Compose, preserving platform-native UI fidelity.[^faq][^fuse]
- **Observable synchronization.** Swift `@Observable` models publish to Kotlin `State` streams automatically, so Compose recomposes when Swift state changes. Ensure shared view models reside in native-mode modules and depend on `SkipModel`.[^fuse][^kotlincompat]
- **Compose interop escape hatches.** For Android-only UI affordances, wrap Kotlin UI in Swift via Compose interop entry points exposed by SkipFuse. Swift code can instantiate Compose views or modifiers using `#if os(Android)` blocks and `AnyDynamicObject` when necessary.[^modes][^fuse]
- **Testing UI parity.** Run `skip test` to execute Robolectric-backed Compose tests alongside SwiftUI tests, ensuring your shared Swift views behave correctly on both platforms before integrating OpenZiti visualizations.[^gettingstarted][^faq]

## 5. Licensing & Operational Notes

- **Evaluation to paid license.** Installing Skip starts a 14-day trial. Before it expires, request a free 30-day evaluation key, then purchase a Small Business or Professional license to continue using Skip Fuse. Indie licenses cover Skip Lite only.[^status][^license]
- **Key management.** Store the issued key in `~/.skiptools/skipkey.env` as `SKIPKEY: <value>` or export it via the `SKIPKEY` environment variable for CI builds. Keys are node-locked per developer machine; use `skip hostid` when requesting replacements.[^license]
- **Operational readiness.** Document the onboarding steps—install with Homebrew, run `skip checkup --native`, configure Android emulators, and ensure your CI agents mirror the same toolchain. Keep license status and tool versions monitored to avoid sudden build interruptions during OpenZiti integration.[^faq][^license]

---

With these pieces in place you can design a Skip Fuse package that exposes a unified Swift API surface across iOS and Android, orchestrates the Kotlin OpenZiti SDK via bridging, and retains native Swift ergonomics for both platforms. Use this guide as the baseline for authoring your project-specific architecture docs, API references, and onboarding manuals.

[^modes]: Skip Documentation — Native and Transpiled Modes. https://skip.tools/docs/modes/
[^fuse]: Skip Documentation — Skip Fuse Module. https://skip.tools/docs/modules/skip-fuse/
[^status]: Skip Documentation — Feature Status Matrix. https://skip.tools/docs/status/
[^gettingstarted]: Skip Documentation — Getting Started with Skip Fuse. https://skip.tools/docs/gettingstarted/
[^cli]: Skip Documentation — CLI Reference (`skip init`). https://skip.tools/docs/reference/cli/
[^kotlincompat]: Skip Documentation — Kotlin Compatibility Options. https://skip.tools/docs/modules/kotlincompat/
[^faq]: Skip Documentation — Skip Fuse FAQ. https://skip.tools/docs/faq/
[^platform]: Skip Documentation — Platform Customization. https://skip.tools/docs/app-development/
[^license]: Skip Documentation — License Keys. https://skip.tools/docs/licensekeys/
