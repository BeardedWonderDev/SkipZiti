#if !SKIP_BRIDGE
import Foundation

#if canImport(Ziti)
import Ziti

public final class ZitiSwiftBridge: SkipZitiPlatformBridge {
    private let identityName: String
    private var configuration: SkipZitiConfiguration?
    private var ziti: Ziti?
    private var emitEvent: ((SkipZitiClientEvent) -> Void)?
    private let emitLock = NSLock()
    private let serviceCacheLock = NSLock()
    private var serviceCache: [String: SkipZitiServiceDescriptor] = [:]
    private var postureChecks: BridgePostureChecks?
    private var currentIdentityAlias: String?

    public init(identityName: String) {
        self.identityName = identityName
    }

    public func start(configuration: SkipZitiConfiguration, emit: @escaping (SkipZitiClientEvent) -> Void) async throws {
        guard let identityPath = configuration.metadata.value(forKey: "identityFilePath") else {
            throw SkipZitiError.runtimeFailure(reason: "metadata[identityFilePath] is required for the Swift bridge")
        }

        guard let ziti = Ziti(fromFile: identityPath) else {
            throw SkipZitiError.runtimeFailure(reason: "Unable to load Ziti identity file at \(identityPath)")
        }

        self.configuration = configuration
        self.ziti = ziti
        self.emitEvent = emit
        self.serviceCache = [:]

        let postureChecks = BridgePostureChecks(
            configuration: configuration,
            aliasProvider: { [weak self] in self?.currentIdentityAlias },
            emitter: { [weak self] event in self?.publish(event) }
        )
        self.postureChecks = postureChecks

        ziti.registerEventCallback { [weak self] event in
            guard let self, let event else { return }
            self.handle(event: event)
        }

        ziti.runAsync(postureChecks) { [weak self] error in
            guard let self else { return }
            if let error {
                let reported = SkipZitiReportedError(
                    stage: .startup,
                    message: "Ziti startup failed",
                    details: error.localizedDescription,
                    recoverable: false
                )
                self.publish(.errorReported(reported))
                return
            }

            let readyRecord = self.record(from: ziti.id, controllerURL: configuration.controllerURL)
            self.currentIdentityAlias = readyRecord.alias
            self.publish(.ready([readyRecord]))
            self.publishInitialServiceSnapshotIfAvailable()
        }
    }

    public func enroll(jwt: Data, alias: String) async throws -> SkipZitiIdentityRecord {
        guard let configuration else {
            throw SkipZitiError.enrollmentFailed(reason: "Swift bridge has not been bootstrapped")
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SkipZiti-\(UUID().uuidString).jwt")
        try jwt.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let identity = try await withCheckedThrowingContinuation { continuation in
            Ziti.enroll(tempURL.path) { identity, error in
                if let error {
                    continuation.resume(throwing: SkipZitiError.enrollmentFailed(reason: error.localizedDescription))
                    return
                }
                guard let identity else {
                    continuation.resume(throwing: SkipZitiError.enrollmentFailed(reason: "Ziti enrollment returned no identity"))
                    return
                }
                continuation.resume(returning: identity)
            }
        }

        if let outputDirectory = configuration.metadata.value(forKey: "identityOutputDirectory") {
            let directoryURL = URL(fileURLWithPath: outputDirectory)
            try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let outputURL = directoryURL.appendingPathComponent("\(identity.id).zid")
            _ = identity.save(outputURL.path)
        }

        let record = record(from: identity, controllerURL: configuration.controllerURL)
        publish(.identityAdded(record))
        return record
    }

    public func revoke(alias: String) async throws {
        let keychain = ZitiKeychain(tag: alias)
        if let error = keychain.deleteKeyPair() {
            throw SkipZitiError.storageFailure(reason: error.localizedDescription)
        }
        if let error = keychain.deleteCertificate() {
            throw SkipZitiError.storageFailure(reason: error.localizedDescription)
        }
        publish(.identityRemoved(alias))
    }

    public func shutdown() async {
        postureChecks = nil
        ziti?.shutdown()
        publish(.stopped)
    }

    public func cachedIdentities() async throws -> [SkipZitiIdentityRecord] {
        guard let ziti = ziti, let configuration = configuration else { return [] }
        return [record(from: ziti.id, controllerURL: configuration.controllerURL)]
    }

    private func handle(event: ZitiEvent) {
        if let context = event.contextEvent {
            handle(contextEvent: context)
        }
        if let serviceEvent = event.serviceEvent {
            handle(serviceEvent: serviceEvent)
        }
        if let routerEvent = event.routerEvent {
            publish(.statusMessage("Router \(routerEvent.name) \(routerEvent.status.debug)"))
        }
        if let authEvent = event.authEvent {
            publish(.statusMessage("Authentication event: \(authEvent.type.debug)"))
        }
    }

    private func handle(contextEvent: ZitiEvent.ContextEvent) {
        if contextEvent.status == Ziti.ZITI_OK {
            publish(.statusMessage("Ziti context ready"))
            return
        }

        let message = contextEvent.err ?? "status: \(contextEvent.status)"
        let recoverable = contextEvent.status == Ziti.ZITI_CONTROLLER_UNAVAILABLE
        let error = SkipZitiReportedError(
            stage: .runtime,
            message: "Ziti context status update",
            details: message,
            recoverable: recoverable
        )
        publish(.errorReported(error))
    }

    private func handle(serviceEvent: ZitiEvent.ServiceEvent) {
        let added = serviceEvent.added.map(descriptor(from:))
        let removed = serviceEvent.removed.map(descriptor(from:))
        let changed = serviceEvent.changed.map(descriptor(from:))

        serviceCacheLock.lock()
        for descriptor in added + changed {
            serviceCache[descriptor.identifier] = descriptor
        }
        for descriptor in removed {
            serviceCache[descriptor.identifier] = nil
        }
        serviceCacheLock.unlock()

        guard !added.isEmpty || !removed.isEmpty || !changed.isEmpty else { return }

        let update = SkipZitiServiceUpdate(
            identityAlias: currentIdentityAlias,
            changeSource: .delta,
            added: added,
            removed: removed,
            changed: changed
        )
        publish(.serviceUpdate(update))
    }

    private func publishInitialServiceSnapshotIfAvailable() {
        serviceCacheLock.lock()
        let snapshot = Array(serviceCache.values)
        serviceCacheLock.unlock()

        guard !snapshot.isEmpty else { return }

        let update = SkipZitiServiceUpdate(
            identityAlias: currentIdentityAlias,
            changeSource: .initial,
            added: snapshot,
            removed: [],
            changed: []
        )
        publish(.serviceUpdate(update))
    }

    private func descriptor(from service: ZitiService) -> SkipZitiServiceDescriptor {
        let intercepts = interceptSummary(from: service)
        let postureChecks = postureCheckSets(from: service.postureQuerySets)

        var attributes = SkipZitiStringMap()
        if let client = service.tunnelClientConfigV1, let encoded = encodeAsJSON(client) {
            attributes.merge(SkipZitiStringMap(dictionary: ["tunnelClientConfig": encoded]))
        }
        if let server = service.tunnelServerConfigV1, let encoded = encodeAsJSON(server) {
            attributes.merge(SkipZitiStringMap(dictionary: ["tunnelServerConfig": encoded]))
        }
        if let url = service.urlClientConfigV1, let encoded = encodeAsJSON(url) {
            attributes.merge(SkipZitiStringMap(dictionary: ["urlClientConfig": encoded]))
        }
        if let host = service.hostConfigV1, let encoded = encodeAsJSON(host) {
            attributes.merge(SkipZitiStringMap(dictionary: ["hostConfig": encoded]))
        }
        if let raw = encodeAsJSON(service) {
            attributes.merge(SkipZitiStringMap(dictionary: ["rawService": raw]))
        }

        let summary = SkipZitiServiceSummary(
            name: service.name ?? "unknown-service",
            identifier: service.id ?? UUID().uuidString,
            isEncrypted: service.encrypted ?? false,
            permFlags: service.permFlags ?? 0,
            intercepts: intercepts,
            postureChecks: postureChecks,
            attributes: attributes
        )

        return SkipZitiServiceDescriptor.fromSummary(summary)
    }

    private func interceptSummary(from service: ZitiService) -> [SkipZitiServiceSummary.Intercept] {
        guard let config = service.interceptConfigV1 else { return [] }
        let portRanges = config.portRanges.map { SkipZitiPortRange(lowerBound: $0.low, upperBound: $0.high) }
        return [
            SkipZitiServiceSummary.Intercept(
                addresses: config.addresses,
                protocols: config.protocols,
                portRanges: portRanges,
                sourceIP: config.sourceIp,
                dialIdentity: config.dialOptions?.identity,
                connectTimeoutSeconds: config.dialOptions?.connectTimeoutSeconds
            )
        ]
    }

    private func postureCheckSets(from sets: [ZitiPostureQuerySet]?) -> [SkipZitiPostureCheckSet] {
        guard let sets else { return [] }
        return sets.map { set in
            let queries = (set.postureQueries ?? []).map { query in
                SkipZitiPostureQuery(
                    id: query.id ?? "",
                    type: query.queryType ?? "",
                    isPassing: query.isPassing ?? false,
                    timeout: query.timeout,
                    timeoutRemaining: query.timeoutRemaining
                )
            }
            return SkipZitiPostureCheckSet(
                policyId: set.policyId ?? "",
                policyType: set.policyType ?? "",
                isPassing: set.isPassing ?? false,
                queries: queries
            )
        }
    }

    private func record(from identity: ZitiIdentity, controllerURL: URL) -> SkipZitiIdentityRecord {
        let fingerprintSource: Data
        if let certs = identity.certs, let data = certs.data(using: .utf8) {
            fingerprintSource = data
        } else if let nameData = identity.id.data(using: .utf8) {
            fingerprintSource = nameData
        } else {
            fingerprintSource = Data()
        }

        let metadata: SkipZitiStringMap = {
            serviceCacheLock.lock()
            defer { serviceCacheLock.unlock() }
            let count = serviceCache.count
            var map = SkipZitiStringMap()
            map.merge(SkipZitiStringMap(dictionary: [
                "bridgeIdentityName": identityName,
                "knownServiceCount": "\(count)"
            ]))
            return map
        }()

        return SkipZitiIdentityRecord(
            alias: identity.id,
            controllerURL: controllerURL,
            fingerprint: fingerprintSource.base64EncodedString(),
            platformAlias: identity.id,
            metadata: metadata
        )
    }

    private func encodeAsJSON<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func publish(_ event: SkipZitiClientEvent) {
        emitLock.lock()
        emitEvent?(event)
        emitLock.unlock()
    }
}

private final class BridgePostureChecks: ZitiPostureChecks {
    private struct ProcessExpectation: Decodable {
        var path: String
        var running: Bool?
        var hash: String?
        var signers: [String]?

        func description() -> String {
            var components: [String] = []
            components.append("path=\(path)")
            if let running {
                components.append("running=\(running)")
            }
            if let hash, !hash.isEmpty {
                components.append("hash=\(hash)")
            }
            if let signers, !signers.isEmpty {
                components.append("signers=\(signers.joined(separator: ","))")
            }
            return components.joined(separator: " ")
        }
    }

    private let aliasProvider: () -> String?
    private let emitter: (SkipZitiClientEvent) -> Void
    private let macAddresses: [String]?
    private let domain: String?
    private let osType: String
    private let osVersion: String
    private let osBuild: String?
    private let processes: [String: ProcessExpectation]

    init(
        configuration: SkipZitiConfiguration,
        aliasProvider: @escaping () -> String?,
        emitter: @escaping (SkipZitiClientEvent) -> Void
    ) {
        self.aliasProvider = aliasProvider
        self.emitter = emitter
        self.macAddresses = BridgePostureChecks.parseList(configuration.metadata.value(forKey: "posture.macAddresses"))
        self.domain = configuration.metadata.value(forKey: "posture.domain")
        let osInfo = BridgePostureChecks.resolveOSInfo(metadata: configuration.metadata)
        self.osType = osInfo.type
        self.osVersion = osInfo.version
        self.osBuild = osInfo.build
        self.processes = BridgePostureChecks.parseProcesses(configuration.metadata.value(forKey: "posture.processes"))

        super.init()

        self.macQuery = { [weak self] ctx, respond in
            guard let self else { return }
            if let macs = self.macAddresses, !macs.isEmpty {
                respond(ctx, macs)
                self.emit(type: .macAddress, resolution: .satisfied(macs.joined(separator: ",")))
            } else {
                respond(ctx, nil)
                self.emit(type: .macAddress, resolution: .unsupported)
            }
        }

        self.domainQuery = { [weak self] ctx, respond in
            guard let self else { return }
            respond(ctx, self.domain)
            if let domain = self.domain {
                self.emit(type: .domain, resolution: .satisfied(domain))
            } else {
                self.emit(type: .domain, resolution: .unsupported)
            }
        }

        self.osQuery = { [weak self] ctx, respond in
            guard let self else { return }
            respond(ctx, self.osType, self.osVersion, self.osBuild)
            let summary = "\(self.osType) \(self.osVersion)"
            self.emit(type: .operatingSystem, resolution: .satisfied(summary))
        }

        self.processQuery = { [weak self] ctx, path, respond in
            guard let self else { return }
            if let expectation = self.processes[path] {
                respond(ctx, path, expectation.running ?? false, expectation.hash, expectation.signers)
                self.emit(type: .process, resolution: .satisfied(expectation.description()))
            } else {
                respond(ctx, path, false, nil, nil)
                self.emit(type: .process, resolution: .failed("No metadata for \(path)"))
            }
        }
    }

    private func emit(type: SkipZitiPostureQueryEvent.QueryType, resolution: SkipZitiPostureQueryEvent.Resolution) {
        let event = SkipZitiPostureQueryEvent(
            identityAlias: aliasProvider(),
            queryType: type,
            resolution: resolution
        )
        emitter(.postureEvent(event))
    }

    private static func parseList(_ raw: String?) -> [String]? {
        guard let raw else { return nil }
        let components = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return components.isEmpty ? nil : components
    }

    private static func parseProcesses(_ raw: String?) -> [String: ProcessExpectation] {
        guard let raw, let data = raw.data(using: .utf8) else { return [:] }
        guard let decoded = try? JSONDecoder().decode([ProcessExpectation].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: decoded.map { ($0.path, $0) })
    }

    private static func resolveOSInfo(metadata: SkipZitiStringMap) -> (type: String, version: String, build: String?) {
        let detected = ProcessInfo.processInfo.operatingSystemVersion
        let defaultVersion = "\(detected.majorVersion).\(detected.minorVersion).\(detected.patchVersion)"
        let type: String
        #if os(macOS)
        type = "macOS"
        #elseif os(iOS)
        type = "iOS"
        #elseif os(tvOS)
        type = "tvOS"
        #elseif os(watchOS)
        type = "watchOS"
        #else
        type = "AppleOS"
        #endif

        let resolvedType = metadata.value(forKey: "posture.os.type") ?? type
        let resolvedVersion = metadata.value(forKey: "posture.os.version") ?? defaultVersion
        let resolvedBuild = metadata.value(forKey: "posture.os.build")
        return (resolvedType, resolvedVersion, resolvedBuild)
    }
}
#else
public final class ZitiSwiftBridge: SkipZitiPlatformBridge {
    public init(identityName: String) {}

    public func start(configuration: SkipZitiConfiguration, emit: @escaping (SkipZitiClientEvent) -> Void) async throws {
        throw SkipZitiError.unsupportedPlatform(reason: "OpenZiti Swift SDK is not linked in this build")
    }

    public func shutdown() async {}

    public func enroll(jwt: Data, alias: String) async throws -> SkipZitiIdentityRecord {
        throw SkipZitiError.unsupportedPlatform(reason: "OpenZiti Swift SDK is not linked in this build")
    }

    public func revoke(alias: String) async throws {
        throw SkipZitiError.unsupportedPlatform(reason: "OpenZiti Swift SDK is not linked in this build")
    }

    public func cachedIdentities() async throws -> [SkipZitiIdentityRecord] {
        []
    }
}
#endif
#endif
