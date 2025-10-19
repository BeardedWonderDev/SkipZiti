# OpenZiti Native SDKs Deep Dive

This document summarizes the implementation of the official OpenZiti Swift and Android SDKs so our Skip Fuse bridge can mirror their behavior. It focuses on core architecture, enrollment and runtime flows, and developer integration patterns.

---

## Swift SDK (`ziti-sdk-swift`)

### High-Level Architecture
- **Bridged C Core.** Swift types wrap the Ziti Tunnel C SDK via the `CZitiPrivate` module and a thin C shim (`lib/ziti.c`). `Ziti` owns a libuv loop and exposes Swift-friendly APIs while delegating to the C runtime (`lib/Ziti.swift`).
- **Identity & Key Management.** `ZitiIdentity` represents controller metadata and keychain handles. `ZitiKeychain` provisions and stores RSA keys/certificates per identity, managing Apple Keychain access for macOS/iOS (`lib/ZitiKeychain.swift`).
- **Connection Layer.** `ZitiConnection` handles dialing, listening, accepting, and I/O callbacks. It bridges Swift closures to C callbacks while ensuring all operations execute on the Ziti loop (`lib/ZitiConnection.swift`).
- **Networking Helpers.** `ZitiUrlProtocol` implements `URLProtocol` to intercept HTTP/S requests, routing them over Ziti based on service intercept configs provided by the controller (`lib/ZitiUrlProtocol.swift`). `ZitiTunnel` wraps the tunnel client for network-extension scenarios (`lib/ZitiTunnel.swift`).
- **Eventing & Posture.** `ZitiEvent`, `ZitiPostureChecks`, and related types capture controller notifications and posture check requirements, forwarding them to Swift callbacks.

### Enrollment & Identity Lifecycle
1. **JWT-Based Enrollment.** `ZitiEnroller` reads one-time JWTs, performs CSR creation, and persists certificates; `Ziti.enroll(_:_:)` wraps this flow and emits a `ZitiIdentity` (`lib/ZitiEnroller.swift`).
2. **Keychain Storage.** Successful enrollment writes keys/certs into the Apple Keychain tagged by JWT `sub`. The resulting identity JSON stores references to fetch credentials later.
3. **Runtime Bootstrap.** `Ziti(fromFile:)`, `Ziti(withId:)`, or `Ziti(zid:loopPtr:)` create instances tied to a libuv loop. `runAsync` starts the event loop on a background thread and invokes an `InitCallback` when services are available.
4. **Service Registration.** Clients call `registerEventCallback` to subscribe to `ZitiEvent` updates (service availability, edge router connectivity, posture requirements).

### Using the Swift SDK
- **Initialization.** Load or enroll an identity, then call `runAsync` with a handler that registers intercepts or starts application logic.
- **Connections.** Acquire a `ZitiConnection` via `createConnection()`, call `dial` or `listen`, and respond to `ConnCallback`, `DataCallback`, and `CloseCallback` events.
- **Intercepted HTTP.** Register `ZitiUrlProtocol` once Ziti is running. It maps controller-provided `ziti-url-client.v1` and `ziti-tunneler-client.v1` configs to intercept tables and handles request/response lifecycles automatically.
- **Tunnel Mode.** Use `ZitiTunnel` with a `ZitiTunnelProvider` to integrate with `NEPacketTunnelProvider` or macOS tun adapters. The tunnel manages DNS, route programming, and multi-identity orchestration.
- **Logging & Diagnostics.** `ZitiLog` standardizes logging across modules; `ziti_dump_wrapper` supports controller state dumps; `ZitiError` wraps SDK error codes.

### Implementation Notes
- **Threading.** All SDK operations marshal onto the libuv loop via `Ziti.perform(_:)`. Callbacks invoked by the C SDK are rehydrated into Swift objects using `ZitiUnretained` handles.
- **Posture Checks.** Temporary posture contexts map `ziti_context` to Swift instances to satisfy posture queries until richer user data is available.
- **XCFramework Distribution.** The project builds an `XCFramework` (`CZiti.xcframework`) consumed by apps via SwiftPM or direct inclusion. Samples (`cziti.sample-ios`, `sample-mac-host`) demonstrate both URL session interception and tunnel usage.

### Repository Guidelines Snapshot
- **Structure.** Keep primary Swift APIs in `lib/`, manage submodules under `deps/`, and update shared schemes in `CZiti.xcodeproj` when adding targets (`AGENTS.md`).
- **Build/Test.** `./build_all.sh` produces universal XCFramework artifacts; use `xcodebuild -project CZiti.xcodeproj -scheme CZiti-macOS build` for platform-specific validation.
- **Process.** Follow Swift naming conventions, add XCTest coverage for new features, and document build/test commands in PR summaries with concise, imperative commit messages.

---

## Android SDK (`ziti-sdk-android`)

### Module Layout
- **`ziti-android` Library.** Provides Android-specific glue on top of the JVM Ziti SDK dependency (`org.openziti:ziti`). Gradle exposes the library with sources/javadoc for Maven Central distribution (`ziti-android/build.gradle`).
- **Application Facade (`org.openziti.android.Ziti`).** Singleton entry point that initializes the SDK, manages enrollments, and exposes LiveData-friendly events (`ziti-android/src/main/java/org/openziti/android/Ziti.kt`).
- **View Models.** `ZitiViewModel` and `ZitiContextViewModel` wrap SDK flows in Android Architecture Components so Activities/Fragments can observe identity status and services (`.../ZitiViewModel.kt`, `.../ZitiContextViewModel.kt`).
- **Posture & System Providers.** `PostureProvider`, `AndroidSystemInfoProvider`, and debug info providers implement ServiceLoader interfaces declared in `META-INF/services` so the JVM core can collect device posture, system info, and support artifacts.
- **Enrollment UX.** `EnrollmentActivity` launches a file picker to select JWTs and triggers `Ziti.enrollZiti`, writing identity material into the AndroidKeyStore (`.../EnrollmentActivity.kt`). `LogFileProvider` exposes log zips via `FileProvider` for support submissions.
- **Crypto Loader.** `AndroidCryptoLoader` returns a `LazySodiumAndroid` instance to satisfy the core SDK’s cryptography abstraction (`android/crypto/AndroidCryptoLoader.kt`).

### Initialization Flow
1. **App Startup.** Call `Ziti.init(context, seamless = true)` from `Application.onCreate`. The SDK registers lifecycle callbacks, configures notification channels, loads existing identities from the AndroidKeyStore, and optionally enables transparent “seamless” interception.
2. **Identity Management.** `Impl.init(keyStore, seamless)` returns current `ZitiContext` instances; the wrapper persists enabled/disabled state in `SharedPreferences`. LiveData events (`identityEvents`, `identities()`) notify observers when contexts are added, removed, or change status.
3. **Enrollment.** `Ziti.enrollZiti` accepts raw JWT bytes or a URI, invokes the underlying JVM SDK’s enrollment call, stores the resulting key/cert entries (`ziti://<controller>/<id>` aliases), and broadcasts `IdentityAdded` or `IdentityRemoved`.
4. **Networking APIs.** Apps retrieve socket factories (`getSocketFactory`, `getSSLSocketFactory`) and DNS resolver hooks from the JVM SDK via the Android facade.

### Android Developer Integration
- **Gradle Dependency.** Add `implementation "org.openziti:ziti-android:<version>"`. ProGuard configs ship with the library; min SDK 26 and Kotlin 1.9.x are required.
- **Application Setup.**
  1. Call `Ziti.init(appContext)` as early as possible.
  2. Optionally customize the enrollment UI by calling `Ziti.setEnrollmentActivity` with your activity class.
  3. Observe `Ziti.identityEvents()` or use the provided ViewModels to update UI when identities change.
- **Enrollment UX.** Provide a way to launch `Ziti.getEnrollmentIntent()` or invoke `Ziti.enrollZiti(jwtBytes)` directly if the JWT is obtained programmatically.
- **Transparency & Posture.** “Seamless” mode toggles intercepts automatically; `PostureProvider.AndroidPostureService` fulfills controller posture queries (OS version, security patch level, MAC addresses).
- **Diagnostics.** Debug info providers export keystore content, logcat output, and app/build metadata into zipped reports when the user taps “Send feedback.”

### Implementation Notes
- **ServiceLoader Contracts.** Resource files in `META-INF/services` register Android-specific implementations so the shared JVM SDK can load them at runtime without explicit wiring.
- **KeyStore Usage.** Identities and controller CA certificates are stored in the AndroidKeyStore; removal routines delete matching aliases when the user revokes an identity.
- **Notifications.** If no identities are present, the SDK raises a system notification prompting enrollment; it is cleared automatically after successful enrollment.

### Repository Guidelines Snapshot
- **Structure.** `ziti-android/` houses the single library module, Kotlin sources in `src/main/java/org/openziti/android`, and publishing metadata under `src/main/resources/META-INF` (`AGENTS.md`).
- **Build/Test.** Use `./gradlew assembleRelease`, `test`, `connectedAndroidTest`, and `lint` to validate codepaths; `publishToMavenLocal` installs the release AAR for local consumers.
- **Process.** Adhere to Kotlin style conventions, expand JUnit/Espresso coverage alongside features, and include performed Gradle tasks plus any security considerations in PRs.

---

## Cross-SDK Observations
- Both SDKs wrap a shared C/JVM core and add platform-specific concerns: keychain/key store integration, posture reporting, HTTP interception, and UX hooks.
- Enrollment flows require handling JWT input, CSR generation, certificate storage, and local persistence of controller metadata.
- Service updates and posture checks are surfaced via platform-idiomatic callbacks (closures and `ZitiEvent` on Swift; LiveData/flows on Android).
- Transparent networking depends on controller-provided intercept configurations (`ziti-url-client.v1`, `ziti-tunneler-client.v1`), so any Skip Fuse bridge must preserve these config translation layers.
- Diagnostic tooling (log dumping, state introspection) is integral to troubleshooting and should be mirrored when exposing Skip Fuse APIs.

Use this analysis as the reference point when mapping OpenZiti capabilities into the Skip Fuse Swift package so the resulting multi-platform bridge respects existing enrollment, lifecycle, and networking semantics.
