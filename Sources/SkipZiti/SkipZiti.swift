#if !SKIP_BRIDGE
import Foundation

public enum SkipZiti {
    public static func bootstrap(
        configuration: SkipZitiConfiguration,
        bridge: any SkipZitiPlatformBridge,
        identityStore: (any SkipZitiIdentityStore)? = nil
    ) async throws -> SkipZitiClient {
        try await SkipZitiClient.bootstrap(configuration: configuration, bridge: bridge, identityStore: identityStore)
    }

    #if canImport(Ziti)
    public static func bootstrapUsingNativeSwiftSDK(
        identityName: String,
        controllerURL: URL,
        logLevel: SkipZitiLogLevel = .info,
        metadata: SkipZitiStringMap = SkipZitiStringMap(),
        identityStore: (any SkipZitiIdentityStore)? = nil
    ) async throws -> SkipZitiClient {
        let configuration = SkipZitiConfiguration(controllerURL: controllerURL, logLevel: logLevel, metadata: metadata)
        let bridge = ZitiSwiftBridge(identityName: identityName)
        return try await SkipZitiClient.bootstrap(configuration: configuration, bridge: bridge, identityStore: identityStore)
    }
    #endif

    #if SKIP
    public static func bootstrapUsingAndroidSDK(
        controllerURL: URL,
        logLevel: SkipZitiLogLevel = .info,
        seamless: Bool = true,
        metadata: SkipZitiStringMap = SkipZitiStringMap(),
        identityStore: (any SkipZitiIdentityStore)? = nil
    ) async throws -> SkipZitiClient {
        let configuration = SkipZitiConfiguration(controllerURL: controllerURL, logLevel: logLevel, metadata: metadata)
        let bridge = ZitiAndroidBridge(seamless: seamless)
        return try await SkipZitiClient.bootstrap(configuration: configuration, bridge: bridge, identityStore: identityStore)
    }
    #endif
}

#if !SKIP
public extension SkipZiti {
    static func bootstrapUsingNativeSwiftSDK(
        identityName: String,
        controllerURL: URL,
        logLevel: SkipZitiLogLevel = .info,
        metadata: [String: String]?,
        identityStore: (any SkipZitiIdentityStore)? = nil
    ) async throws -> SkipZitiClient {
        let configuration = SkipZitiConfiguration(
            controllerURL: controllerURL,
            logLevel: logLevel,
            metadata: SkipZitiStringMap(dictionary: metadata ?? [:])
        )
        let bridge = ZitiSwiftBridge(identityName: identityName)
        return try await SkipZitiClient.bootstrap(configuration: configuration, bridge: bridge, identityStore: identityStore)
    }

    static func bootstrapUsingAndroidSDK(
        controllerURL: URL,
        logLevel: SkipZitiLogLevel = .info,
        seamless: Bool = true,
        metadata: [String: String]?,
        identityStore: (any SkipZitiIdentityStore)? = nil
    ) async throws -> SkipZitiClient {
        let configuration = SkipZitiConfiguration(
            controllerURL: controllerURL,
            logLevel: logLevel,
            metadata: SkipZitiStringMap(dictionary: metadata ?? [:])
        )
        let bridge = ZitiAndroidBridge(seamless: seamless)
        return try await SkipZitiClient.bootstrap(configuration: configuration, bridge: bridge, identityStore: identityStore)
    }
}
#endif

#endif
