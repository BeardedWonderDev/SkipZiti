# Skip SDK Case Studies (Firebase, Stripe, Zip)

This field report captures how existing Skip-maintained SDKs structure their dual-platform support so we can model our Skip Fuse OpenZiti package on proven patterns. Each section highlights implementation tactics (build config, interop, Android bridging) and consumption patterns (how apps import and call the SDK) observed in:

- [`skip-firebase`](../../SkipRepos/skip-firebase)
- [`skip-stripe`](../../SkipRepos/skip-stripe)
- [`skip-zip`](../../SkipRepos/skip-zip)

## 1. SkipFirebase

- **Module layout mirrors vendor SDKs.** `Package.swift` exports a SwiftPM target per Firebase feature (`SkipFirebaseAuth`, `SkipFirebaseFirestore`, …) and applies the `skipstone` build plugin everywhere so tooling drives both Swift (Apple) and Kotlin (Android) builds. (`../SkipRepos/skip-firebase/Package.swift`)
- **Environment-aware dependencies.** The `SKIP_BRIDGE` environment toggle injects a `SkipFuse` dependency and forces dynamic libraries, enabling the same package to serve Skip Fuse native mode while defaulting to Skip Lite transpilation. (`../SkipRepos/skip-firebase/Package.swift`)
- **Kotlin façade wrappers.** Android implementations live behind `#if SKIP` guards and wrap Kotlin SDK types using `KotlinConverting`. Example: `Auth` exposes the iOS-style API while calling `com.google.firebase.auth.FirebaseAuth` under the hood and mapping coroutines via `tasks.await()`. (`../SkipRepos/skip-firebase/Sources/SkipFirebaseAuth/SkipFirebaseAuth.swift`)
- **skip.yml extends Gradle.** Each module’s `Skip/skip.yml` sets `mode: transpiled`, turns on `bridging`, and injects required Gradle dependencies (Firebase BOM, individual artifacts, coroutines). (`../SkipRepos/skip-firebase/Sources/SkipFirebaseCore/Skip/skip.yml`)
- **Process bridging helpers.** Android-only paths access the foreground `Activity` through SkipFuse helpers (`UIApplication.shared.androidActivity`) and translate Kotlin exceptions into `NSError`, maintaining the Swift API contract.
- **Consumption pattern.** Client code conditionally imports Skip wrappers on Android and vendor frameworks on Apple: tests and samples use `#if SKIP` to import `SkipFirebase*` but fall back to the official Firebase modules on iOS/macOS. (`../SkipRepos/skip-firebase/Tests/SkipFirebaseAuthTests/SkipFirebaseAuthTests.swift`)

**Key takeaway:** Author Swift-first APIs, then wrap Android interop behind `#if SKIP` using `KotlinConverting` and coroutine adapters, letting Apple builds link the vendor’s Swift frameworks directly.

## 2. SkipStripe

- **Shared SwiftUI-first surface.** `SkipStripe.swift` defines cross-platform Swift data models (`StripePaymentConfiguration`, `BillingDetails`, etc.) with conditional typealiases so Apple builds link directly against Stripe’s Swift frameworks while Android maps to Kotlin classes. (`../SkipRepos/skip-stripe/Sources/SkipStripe/SkipStripe.swift`)
- **UI bridge strategy.** `StripePaymentButton` renders a `PaymentSheet.PaymentButton` on Apple and wraps an Android `PaymentSheet` invocation inside a SwiftUI `Button` that SkipFuse lifts into Compose. When SkipFuse cannot bridge complex generics, the module vends a simplified `SimpleStripePaymentButton` to guarantee availability. (`../SkipRepos/skip-stripe/Sources/SkipStripe/SkipStripe.swift`)
- **Skip configuration.** The module’s `skip.yml` keeps `mode: transpiled`, enables `bridging`, and adds the `com.stripe:stripe-android` Gradle dependency so Kotlin code is present when the Swift is transpiled. (`../SkipRepos/skip-stripe/Sources/SkipStripe/Skip/skip.yml`)
- **End-to-end example app.** The `Examples/` package ships a Skip Fuse demo that imports `SkipStripe` on Android (`#if os(Android)`) and Stripe’s native SDK on Apple, demonstrating how to call shared services and present the payment sheet from shared SwiftUI. (`../SkipRepos/skip-stripe/Examples/ContentView.swift`, `../SkipRepos/skip-stripe/Examples/StripePaymentService.swift`)
- **Asynchronous interop.** Kotlin callbacks (e.g., payment sheet completion) are converted into Swift enums (`StripePaymentResult`) so callers share identical handling logic across platforms.

**Key takeaway:** Model UI and configuration structs in Swift, map them to each platform’s native types within conditional compilation blocks, and ship Skip Fuse-friendly wrappers when generics or closures block bridging.

## 3. SkipZip

- **Hybrid native + transpiled build.** `Package.swift` declares a dynamic `SkipZip` target plus a `MiniZip` C target compiled through CMake. This structure exposes MiniZip to Swift while Skip transpiles the Swift façade to Kotlin. (`../SkipRepos/skip-zip/Package.swift`)
- **Custom Gradle glue.** `Sources/MiniZip/Skip/skip.yml` injects an `externalNativeBuild { cmake { ... } }` block so the generated Android project builds the bundled C sources with the same `CMakeLists.txt`. (`../SkipRepos/skip-zip/Sources/MiniZip/Skip/skip.yml`)
- **SkipFFI bridging.** `MiniZipLibrary.swift` wraps MiniZip functions in Swift methods marked with `/* SKIP EXTERN */`, letting Skip generate JNI bindings via `SkipFFI`. Conditional `#if SKIP` sections substitute JNA-compatible structure definitions and use `SKIP INSERT` annotations to control generated Kotlin. (`../SkipRepos/skip-zip/Sources/SkipZip/MiniZipLibrary.swift`)
- **Swift-facing API.** `SkipZip.swift` exposes high-level Swift classes (`ZipReader`, `ZipWriter`) that call into the registered native library, handling pointer translation via `withFFIDataPointer`, bridging error codes, and hiding the platform differences. (`../SkipRepos/skip-zip/Sources/SkipZip/SkipZip.swift`)
- **Consumer experience.** Callers interact purely with Swift types; Skip handles registering the native library on Android through `registerNatives`, so app code stays identical across platforms.

**Key takeaway:** When third-party libraries have C/C++ surfaces, bundle them as separate targets and use `SkipFFI` plus Gradle `externalNativeBuild` hooks to keep Android builds aligned with Swift-linting APIs.

## Cross-Repo Lessons for a Skip Fuse OpenZiti SDK

1. **Split responsibilities cleanly.** Keep Swift-facing APIs platform-neutral; push platform-specific code under `#if SKIP` (Android) and `#elseif os(...)` (Apple) branches so Skip transpilation/native compilation stays deterministic.
2. **Leverage Skip macros.** `KotlinConverting`, `/* SKIP EXTERN */`, and `SKIP INSERT` annotations steer the generated Kotlin, enabling direct interop with existing JVM libraries and native code without hand-written JNI.
3. **Treat `skip.yml` as Gradle glue.** Match Android dependencies and build steps (Firebase BOM, Stripe artifacts, CMake builds) inside module-specific `skip.yml` files so the generated project compiles out of the box.
4. **Design for both Skip Lite and Fuse.** Conditionally add `SkipFuse` as a dependency when `SKIP_BRIDGE` is set, and offer simplified entry points when the full Swift UI can’t bridge cleanly.
5. **Provide dual-platform samples.** Shipping example or test targets that import Skip modules on Android and native SDKs on Apple gives downstream developers a concrete template for conditional imports, async handling, and lifecycle integration.

These patterns form a reference playbook for building the Skip Fuse OpenZiti bridge: define the Swift API first, wire Android access via Skip’s interop mechanisms, and ensure tooling configurations produce consistent artifacts for both platforms.
