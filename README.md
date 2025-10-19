# SkipZiti — Cross-Platform Swift SDK for OpenZiti

SkipZiti delivers a single Swift Package that targets both iOS and Android through [Skip Fuse](https://skip.tools/docs/modules/skip-fuse/) while wrapping the official [OpenZiti](https://openziti.github.io/ziti/overview.html) SDKs. With one Swift API surface you can enroll identities, establish Ziti-secured sessions, intercept HTTP(S) traffic, and integrate Ziti posture checks across Apple and Android apps.

> ℹ️ SkipZiti builds on the open-source work of the OpenZiti and Skip teams. See [Acknowledgements & Licenses](#acknowledgements--licenses) for required attributions and downstream obligations.

---

## Table of Contents
1. [Features](#features)
2. [Architecture Overview](#architecture-overview)
3. [Prerequisites](#prerequisites)
4. [Installation](#installation)
5. [Enrollment & Identity Lifecycle](#enrollment--identity-lifecycle)
6. [Using the Unified API](#using-the-unified-api)
7. [Build & Test](#build--test)
8. [Troubleshooting & Support](#troubleshooting--support)
9. [Acknowledgements & Licenses](#acknowledgements--licenses)

---

## Features
- **Single Swift API for Dual Platforms** – Ship the same Swift sources to iOS and Android. Skip Fuse compiles Swift natively for Android while the package links against OpenZiti’s Swift and JVM implementations.
- **Full Ziti Networking** – Dial and listen to Ziti services, perform posture checks, and access controller events by bridging `ZitiConnection`, `ZitiEvent`, and `ZitiTunnel` semantics into the dual-platform Swift module.
- **Transparent HTTP Routing** – Register the provided URL protocol layer to intercept HTTP/HTTPS requests and route them across your Ziti fabric, mirroring `ZitiUrlProtocol` on Apple and the “seamless mode” DNS interception on Android.
- **Integrated Enrollment Helpers** – Use shared Swift utilities to process one-time JWTs, create identities, and persist credentials (Apple Keychain or AndroidKeyStore) via OpenZiti’s native flows.
- **Composable Samples & Templates** – The package mirrors Skip’s `skip init --native-model` layout and ships starter demo targets so you can validate Ziti connectivity on emulators and simulators.

---

## Architecture Overview

SkipZiti is composed of three layers:

1. **Shared Swift Interface** — Public types (`SkipZiti`, `SkipZitiConnection`, `SkipZitiUrlProtocol`, etc.) expose enrollment, connection, and intercept APIs. These types are written once and compiled for both operating systems.
2. **Platform Bridges**  
   - **Apple**: Links directly to OpenZiti’s Swift XCFramework (`CZiti.xcframework`). The bridge mirrors the upstream SDK’s `Ziti` class, keychain helpers, and URL protocol implementation.  
   - **Android**: Uses Skip Fuse’s bridging layer to call into OpenZiti’s JVM library (`org.openziti:ziti` via `ziti-android`). Swift code interacts with generated Kotlin stubs, which invoke Android posture providers, DNS interceptors, and KeyStore APIs.
3. **Skip Tooling** — `skip.yml` configures native-mode compilation, enabling transparent Swift⇄Kotlin interop, Gradle dependency injection (OpenZiti AAR, Sodium, JNA), and Robolectric-backed testing through `skip test`.

```
+-----------------------+      +----------------------------+
|  Shared Swift API     | ---> | Skip Fuse Generated Kotlin |
|  (SkipZiti sources)   |      | + Android OpenZiti SDK     |
+-----------------------+      +----------------------------+
           |                              ^
           v                              |
 +----------------------+       +---------------------------+
 |  Apple Toolchains    |       | Android Toolchains        |
 |  + CZiti.xcframework |       | + org.openziti:ziti       |
 +----------------------+       +---------------------------+
```

---

## Prerequisites
- **Skip CLI with native-mode support** – Install via `brew install skiptools/skip/skip` and ensure your Skip license covers Skip Fuse usage. Run `skip checkup --native` to verify toolchains.
- **Swift Toolchain** – Xcode 15+ (Swift 5.9 or newer).
- **Android Toolchain** – Android Studio Flamingo or later, Android SDK 33+, Java 11.
- **OpenZiti Controller** – Access to a configured OpenZiti network for enrollment and service testing.
- **License Awareness** – Skip libraries are LGPL‑3.0 with a linking exception; OpenZiti SDKs are Apache-2.0. See [Acknowledgements & Licenses](#acknowledgements--licenses) for redistribution requirements.

---

## Installation

1. **Create a Skip Fuse package**
   ```bash
   skip init --native-model SkipZitiApp SkipZitiCore
   cd SkipZitiApp
   ```
2. **Add SkipZiti as a dependency**  
   Update `Package.swift` to include:
   ```swift
   .package(url: "https://github.com/your-org/SkipZiti.git", from: "0.1.0"),
   ```
   Then add `.product(name: "SkipZiti", package: "SkipZiti")` to your target dependencies.
3. **Resolve Android dependencies** – Ensure `skip.yml` pulls in `org.openziti:ziti`, `com.goterl:lazysodium-android`, and `net.java.dev.jna:jna`. The template in this repo already matches OpenZiti’s Gradle setup.
4. **Trust Skip Fuse plugin** – Confirm `Package.swift` lists the `skipstone` plugin so `swift build` runs the Skip pipeline.

---

## Enrollment & Identity Lifecycle

SkipZiti unifies the enrollment experience described in the upstream SDK readmes:

- **JWT Intake** – Invoke `SkipZitiEnroller.enroll(jwtURL:completion:)` (or the async alternative) to process one-time JWT files.  
- **Key Management** – On Apple, identities are stored in the Keychain using OpenZiti’s secure storage routines. On Android, the same Swift calls bridge to KeyStore-backed enrollment and controller CA storage.  
- **Persistence** – The enrollment response includes identity metadata (controller URLs, CA pool, key references). Use `SkipZitiIdentity.save(to:)` to persist JSON for future sessions.
- **Runtime Initialization** – Create `SkipZiti` instances with the stored identity and call `runAsync` to boot the libuv (Apple) or JVM (Android) event loop. The completion handler fires once posture checks and service catalogs are ready.

---

## Using the Unified API

```swift
import SkipZiti

final class SecureChatViewModel: ObservableObject {
    private var ziti: SkipZiti?
    private var connection: SkipZitiConnection?

    func start(zidURL: URL) async throws {
        guard let identity = SkipZitiIdentity(from: zidURL) else {
            throw ZitiError("Invalid identity file")
        }

        let ziti = SkipZiti(identity: identity)
        try await ziti.runAsync { error in
            if let error { throw error }
        }

        // Intercept HTTP requests once initialization succeeds
        SkipZitiUrlProtocol.register(ziti)

        // Dial a Ziti service
        let conn = try ziti.createConnection()
        try await conn.dial(service: "chat-service") { data in
            // handle inbound payloads
        }
        self.ziti = ziti
        self.connection = conn
    }
}
```

### HTTP Interception
1. Call `SkipZitiUrlProtocol.register(ziti)` within your init callback.  
2. Insert the protocol into custom URLSession configurations when needed:
   ```swift
   let config = URLSessionConfiguration.default
   config.protocolClasses?.insert(SkipZitiUrlProtocol.self, at: 0)
   ```

### Service Events & Posture Checks
- Subscribe to `ziti.registerEventCallback(_:mask:)` for real-time controller notices (service added/removed, edge router status).
- Use `SkipZitiPostureService` helpers to satisfy controller posture requirements (OS version, MAC addresses), mirroring Android’s `PostureProvider`.

---

## Build & Test

- **Build (all platforms)**  
  ```bash
  swift build
  ```
- **Parity Tests**  
  ```bash
  skip test
  ```
  Runs Swift XCTest bundles and the mirrored Kotlin tests via Robolectric.
- **Android Instrumented Tests** (optional)  
  ```bash
  ./gradlew connectedAndroidTest
  ```
- **Release Artifacts**  
  ```bash
  swift build -c release
  ```
  Produces Apple binaries + Android AARs in `.build/`.

---

## Troubleshooting & Support

- **Enrollment Issues** – Verify controller reachability and that the JWT has not expired. Check platform-specific secure storage (Keychain/KeyStore) permissions.  
- **Android Build Failures** – Confirm the required Gradle dependencies (Ziti, Sodium, JNA) are available and that Java 11 is selected.  
- **Skip Fuse Errors** – Run `skip doctor` / `skip checkup --native` for environment diagnostics.  
- **Community Resources**  
  - OpenZiti Docs: <https://docs.openziti.io/>  
  - OpenZiti Discourse: <https://openziti.discourse.group/>  
  - Skip Docs: <https://skip.tools/docs/>  

Report bugs or feature requests via GitHub issues in this repository. For upstream problems, use the respective Skip or OpenZiti trackers.

---

## Acknowledgements & Licenses

SkipZiti is released under the [MIT License](./LICENSE).

This project links to and redistributes components under the following licenses:

| Component | Source | License |
| --- | --- | --- |
| Skip Fuse, Skip UI, Skip Model, and related Skip packages | <https://source.skip.tools/> | GNU LGPL v3.0 **with linking exception**. Redistribution must include the LGPL text and exception. Users retain the right to relink with modified Skip libraries. |
| OpenZiti Swift SDK (`ziti-sdk-swift`) | <https://github.com/openziti/ziti-sdk-swift> | Apache License 2.0 |
| OpenZiti Android SDK (`ziti-sdk-android`) | <https://github.com/openziti/ziti-sdk-android> | Apache License 2.0 |

Notices:
- Portions of the Swift implementation are derived from the OpenZiti Swift SDK © NetFoundry Inc., used under Apache 2.0.
- Android posture, enrollment, and DNS interception functionality leverages OpenZiti’s JVM SDK under Apache 2.0.
- SkipZiti depends on Skip libraries © Skip Tools, distributed under LGPL-3.0 with a special exception permitting distribution of combined works without providing minimal corresponding source, provided the other LGPL terms are met.

When distributing binaries, include the upstream license texts and disclose any modifications you make to Skip or OpenZiti code. If you statically link SkipFuse, ensure recipients can replace or relink the LGPL components.

---

Made with ❤️ by the SkipZiti team. Contributions and feedback are welcome! Submit pull requests or open issues to help improve the dual-platform OpenZiti experience for Swift developers.
