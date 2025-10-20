import Foundation

#if SKIP
import skip.foundation
import SkipLib
import org.openziti.android.Ziti
import androidx.lifecycle.Observer

typealias AndroidZitiSDK = org.openziti.android.Ziti
typealias CoreZitiSDK = org.openziti.Ziti
typealias CoreZitiContext = org.openziti.ZitiContext
typealias CoreZitiServiceEvent = org.openziti.ZitiContext.ServiceEvent
typealias CoreZitiServiceUpdate = org.openziti.ZitiContext.ServiceUpdate
typealias AndroidService = org.openziti.api.Service
typealias AndroidInterceptConfig = org.openziti.api.InterceptConfig
typealias AndroidDialOptions = org.openziti.api.InterceptConfig.DialOptions
typealias AndroidPortRange = org.openziti.api.PortRange
typealias AndroidPostureQuerySet = org.openziti.edge.model.PostureQuerySet
typealias AndroidPostureQuery = org.openziti.edge.model.PostureQuery

public final class ZitiAndroidBridge: SkipZitiPlatformBridge {
    private let seamless: Bool
    private var configuration: SkipZitiConfiguration?
    private var emitEvent: ((SkipZitiClientEvent) -> Void)?
    private var observer: Observer<AndroidZitiSDK.IdentityEvent>?
    private let emitLock = NSLock()
    private var initialized = false
    private var serviceTasks: [String: Task<Void, Never>] = [:]
    private let serviceCacheLock = NSLock()
    private var serviceCache: [String: [String: SkipZitiServiceDescriptor]] = [:]

    public init(seamless: Bool = true) {
        self.seamless = seamless
    }

    public func start(configuration: SkipZitiConfiguration, emit: @escaping (SkipZitiClientEvent) -> Void) async throws {
        let context = ProcessInfo.processInfo.androidContext
        AndroidZitiSDK.init(context, seamless: seamless)
        initialized = true
        self.configuration = configuration
        self.emitEvent = emit
        self.serviceCache = [:]

        let observer = Observer<AndroidZitiSDK.IdentityEvent> { [weak self] event in
            guard let self, let event else { return }
            switch event {
            case let added as AndroidZitiSDK.IdentityAdded:
                self.attachServiceObserver(forAlias: added.name, defaultController: configuration.controllerURL)
                let record = self.record(forAlias: added.name, defaultController: configuration.controllerURL)
                self.publish(.identityAdded(record))
            case let removed as AndroidZitiSDK.IdentityRemoved:
                let removedDescriptors = self.detachServiceObserver(forAlias: removed.name)
                if !removedDescriptors.isEmpty {
                    let update = SkipZitiServiceUpdate(
                        identityAlias: removed.name,
                        changeSource: .delta,
                        added: [],
                        removed: removedDescriptors,
                        changed: []
                    )
                    self.publish(.serviceUpdate(update))
                }
                self.publish(.identityRemoved(removed.name))
            default:
                break
            }
        }
        AndroidZitiSDK.identityEvents().observeForever(observer)
        self.observer = observer

        let records = currentRecords(defaultController: configuration.controllerURL)
        publish(.ready(records))
        attachServiceObservers(defaultController: configuration.controllerURL)
    }

    public func enroll(jwt: Data, alias: String) async throws -> SkipZitiIdentityRecord {
        guard initialized, let configuration = configuration else {
            throw SkipZitiError.enrollmentFailed(reason: "Android bridge has not been bootstrapped")
        }

        let targetAlias = alias

        return try await withCheckedThrowingContinuation { continuation in
            var enrollmentObserver: Observer<AndroidZitiSDK.IdentityEvent>? = nil
            enrollmentObserver = Observer { event in
                guard let event = event else { return }
                if let added = event as? AndroidZitiSDK.IdentityAdded {
                    if targetAlias.isEmpty || added.name == targetAlias {
                        if let observer = enrollmentObserver {
                            AndroidZitiSDK.identityEvents().removeObserver(observer)
                        }
                        let record = self.record(forAlias: added.name, defaultController: configuration.controllerURL)
                        continuation.resume(returning: record)
                    }
                }
            }

            if let observer = enrollmentObserver {
                AndroidZitiSDK.identityEvents().observeForever(observer)
            }

            AndroidZitiSDK.enrollZiti(jwt.kotlin())
        }
    }

    public func revoke(alias: String) async throws {
        guard let context = allContexts().first(where: { $0.name() == alias }) else {
            throw SkipZitiError.storageFailure(reason: "Identity \(alias) not found")
        }

        AndroidZitiSDK.deleteIdentity(context)
        let removedDescriptors = detachServiceObserver(forAlias: alias)
        if !removedDescriptors.isEmpty {
            let update = SkipZitiServiceUpdate(
                identityAlias: alias,
                changeSource: .delta,
                added: [],
                removed: removedDescriptors,
                changed: []
            )
            publish(.serviceUpdate(update))
        }
    }

    public func shutdown() async {
        if let observer = observer {
            AndroidZitiSDK.identityEvents().removeObserver(observer)
            self.observer = nil
        }
        for task in serviceTasks.values {
            task.cancel()
        }
        serviceTasks.removeAll()
        serviceCacheLock.lock()
        serviceCache.removeAll()
        serviceCacheLock.unlock()
        publish(.stopped)
    }

    public func cachedIdentities() async throws -> [SkipZitiIdentityRecord] {
        guard let configuration = configuration else { return [] }
        return currentRecords(defaultController: configuration.controllerURL)
    }

    private func attachServiceObservers(defaultController: URL) {
        allContexts().forEach { context in
            attachServiceObserver(for: context, defaultController: defaultController)
        }
    }

    private func attachServiceObserver(forAlias alias: String, defaultController: URL) {
        guard let context = context(forAlias: alias) else { return }
        attachServiceObserver(for: context, defaultController: defaultController)
    }

    private func attachServiceObserver(for context: CoreZitiContext, defaultController: URL) {
        let alias = context.name()
        if serviceTasks[alias] != nil { return }

        let stream = AsyncStream<CoreZitiServiceEvent>(flow: context.serviceUpdates())
        let task = Task.detached { [weak self] in
            for await event in stream {
                guard let self else { break }
                self.processServiceEvent(event, context: context, defaultController: defaultController)
            }
        }
        serviceTasks[alias] = task
    }

    @discardableResult
    private func detachServiceObserver(forAlias alias: String) -> [SkipZitiServiceDescriptor] {
        if let task = serviceTasks.removeValue(forKey: alias) {
            task.cancel()
        }
        serviceCacheLock.lock()
        let removed = serviceCache.removeValue(forKey: alias)?.map { $0.value } ?? []
        serviceCacheLock.unlock()
        return removed
    }

    private func context(forAlias alias: String) -> CoreZitiContext? {
        allContexts().first { $0.name() == alias }
    }

    private func currentRecords(defaultController: URL) -> [SkipZitiIdentityRecord] {
        allContexts().map { record(from: $0, defaultController: defaultController) }
    }

    private func processServiceEvent(_ event: CoreZitiServiceEvent, context: CoreZitiContext, defaultController: URL) {
        guard let service = event.getService() else { return }
        let alias = context.name()
        let descriptor = descriptor(from: service, defaultController: defaultController)

        var added: [SkipZitiServiceDescriptor] = []
        var removed: [SkipZitiServiceDescriptor] = []
        var changed: [SkipZitiServiceDescriptor] = []

        serviceCacheLock.lock()
        var aliasCache = serviceCache[alias] ?? [:]
        switch event.getType() {
        case CoreZitiServiceUpdate.available:
            if aliasCache[descriptor.identifier] != nil {
                aliasCache[descriptor.identifier] = descriptor
                changed.append(descriptor)
            } else {
                aliasCache[descriptor.identifier] = descriptor
                added.append(descriptor)
            }
        case CoreZitiServiceUpdate.configurationChange:
            aliasCache[descriptor.identifier] = descriptor
            changed.append(descriptor)
        case CoreZitiServiceUpdate.unavailable:
            if let existing = aliasCache.removeValue(forKey: descriptor.identifier) {
                removed.append(existing)
            } else {
                removed.append(descriptor)
            }
        default:
            break
        }
        serviceCache[alias] = aliasCache
        serviceCacheLock.unlock()

        guard !added.isEmpty || !removed.isEmpty || !changed.isEmpty else { return }

        let update = SkipZitiServiceUpdate(
            identityAlias: alias,
            changeSource: .delta,
            added: added,
            removed: removed,
            changed: changed
        )
        publish(.serviceUpdate(update))
    }

    private func descriptor(from service: AndroidService, defaultController: URL) -> SkipZitiServiceDescriptor {
        let name = service.getName() ?? "unknown-service"
        let identifier = service.getId() ?? UUID().uuidString
        let encrypted = service.getEncryptionRequired()?.booleanValue ?? false

        var canDial = false
        var canBind = false
        if let permissionsList = service.getPermissions() {
            permissionsList.forEach { permission in
                guard let permission else { return }
                let value = String(describing: permission).lowercased()
                if value.contains("dial") { canDial = true }
                if value.contains("bind") { canBind = true }
            }
        }

        let intercepts = intercepts(from: service.interceptConfig())
        let postureChecks = postureChecks(from: service)

        var attributes = SkipZitiStringMap()
        attributes.merge(SkipZitiStringMap(dictionary: [
            "platform": "android",
            "controller": defaultController.absoluteString
        ]))
        if let strategy = service.getTerminatorStrategy() {
            attributes.merge(SkipZitiStringMap(dictionary: ["terminatorStrategy": strategy]))
        }
        if let rawConfigs = service.getConfig() {
            var keys: [String] = []
            rawConfigs.keySet().forEach { key in
                if let key = key as? String {
                    keys.append(key)
                }
            }
            if !keys.isEmpty {
                attributes.merge(SkipZitiStringMap(dictionary: ["configKeys": keys.joined(separator: ",")]))
            }
        }
        attributes.merge(SkipZitiStringMap(dictionary: ["rawDescription": service.toString()]))

        return SkipZitiServiceDescriptor(
            name: name,
            identifier: identifier,
            isEncrypted: encrypted,
            permissions: SkipZitiServicePermissions(canDial: canDial, canBind: canBind),
            intercepts: intercepts,
            postureChecks: postureChecks,
            attributes: attributes
        )
    }

    private func intercepts(from config: AndroidInterceptConfig?) -> [SkipZitiServiceIntercept] {
        guard let config else { return [] }

        var protocols: [String] = []
        if let set = config.getProtocols() {
            set.forEach { value in
                guard let value else { return }
                protocols.append(String(describing: value))
            }
        }

        var addresses: [String] = []
        if let set = config.getAddresses() {
            set.forEach { value in
                guard let value else { return }
                addresses.append(String(describing: value))
            }
        }

        var portRanges: [SkipZitiPortRange] = []
        if let ranges = config.getPortRanges() {
            ranges.forEach { range in
                guard let range = range as? AndroidPortRange else { return }
                portRanges.append(SkipZitiPortRange(lowerBound: Int(range.getLow()), upperBound: Int(range.getHigh())))
            }
        }

        let dialIdentity = config.getDialOptions()?.getIdentity()
        let connectTimeout = config.getDialOptions()?.getConnectTimeoutSeconds()?.intValue

        return [
            SkipZitiServiceIntercept(
                addresses: addresses,
                protocols: protocols,
                portRanges: portRanges,
                sourceIP: config.getSourceIp(),
                dialIdentity: dialIdentity,
                connectTimeoutSeconds: connectTimeout
            )
        ]
    }

    private func postureChecks(from service: AndroidService) -> [SkipZitiPostureCheckSet] {
        guard let postureSets = service.getPostureQueries() else { return [] }
        var results: [SkipZitiPostureCheckSet] = []
        postureSets.forEach { element in
            guard let set = element as? AndroidPostureQuerySet else { return }
            var queries: [SkipZitiPostureQuery] = []
            if let postureList = set.getPostureQueries() {
                postureList.forEach { queryElement in
                    guard let query = queryElement as? AndroidPostureQuery else { return }
                    let timeoutRemainingValue = query.getTimeoutRemaining()
                    let timeoutRemaining = timeoutRemainingValue == nil ? nil : Int64(timeoutRemainingValue!.longValue)
                    queries.append(
                        SkipZitiPostureQuery(
                            id: query.getId() ?? "",
                            type: String(describing: query.getQueryType() ?? ""),
                            isPassing: query.getIsPassing()?.boolValue ?? false,
                            timeout: Int64(query.getTimeout()?.longValue ?? 0),
                            timeoutRemaining: timeoutRemaining
                        )
                    )
                }
            }
            let postureSet = SkipZitiPostureCheckSet(
                policyId: set.getPolicyId() ?? "",
                policyType: String(describing: set.getPolicyType() ?? ""),
                isPassing: set.getIsPassing()?.boolValue ?? false,
                queries: queries
            )
            results.append(postureSet)
        }
        return results
    }

    private func record(forAlias alias: String, defaultController: URL) -> SkipZitiIdentityRecord {
        if let context = allContexts().first(where: { $0.name() == alias }) {
            return record(from: context, defaultController: defaultController)
        }
        return SkipZitiIdentityRecord(
            alias: alias,
            controllerURL: defaultController,
            fingerprint: Data(alias.utf8).base64EncodedString(),
            platformAlias: alias,
            metadata: SkipZitiStringMap()
        )
    }

    private func record(from context: CoreZitiContext, defaultController: URL) -> SkipZitiIdentityRecord {
        let controllerString = context.controller()
        let controllerURL = URL(string: controllerString) ?? defaultController
        let fingerprint = Data(context.name().utf8).base64EncodedString()
        var metadata = normalizedStatusMetadata(for: context.getStatus())
        metadata.merge(SkipZitiStringMap(dictionary: [
            "controller": controllerURL.absoluteString,
            "serviceCount": "\(serviceCount(for: context.name()))"
        ]))
        return SkipZitiIdentityRecord(
            alias: context.name(),
            controllerURL: controllerURL,
            fingerprint: fingerprint,
            platformAlias: context.name(),
            metadata: metadata
        )
    }

    private func publish(_ event: SkipZitiClientEvent) {
        emitLock.lock()
        emitEvent?(event)
        emitLock.unlock()
    }

    private func normalizedStatusMetadata(for status: CoreZitiContext.Status?) -> SkipZitiStringMap {
        guard let status else {
            var map = SkipZitiStringMap()
            map.merge(SkipZitiStringMap(dictionary: [
                "statusCode": "unknown",
                "statusDisplay": "Unknown"
            ]))
            return map
        }
        let raw = status.toString()
        let normalized = raw.replacingOccurrences(of: " ", with: "_").lowercased()
        var map = SkipZitiStringMap()
        map.merge(SkipZitiStringMap(dictionary: [
            "statusCode": raw,
            "statusDisplay": raw,
            "statusNormalized": normalized
        ]))
        return map
    }

    private func serviceCount(for alias: String) -> Int {
        serviceCacheLock.lock()
        defer { serviceCacheLock.unlock() }
        return serviceCache[alias]?.count ?? 0
    }

    private func allContexts() -> [CoreZitiContext] {
        var contexts: [CoreZitiContext] = []
        CoreZitiSDK.getContexts().forEach { element in
            if let context = element as? CoreZitiContext {
                contexts.append(context)
            }
        }
        return contexts
    }
}
#elseif !SKIP_BRIDGE
public final class ZitiAndroidBridge: SkipZitiPlatformBridge {
    public init(seamless: Bool = true) {}

    public func start(configuration: SkipZitiConfiguration, emit: @escaping (SkipZitiClientEvent) -> Void) async throws {
        throw SkipZitiError.unsupportedPlatform(reason: "Android bridge available only when building with Skip")
    }

    public func shutdown() async {}

    public func enroll(jwt: Data, alias: String) async throws -> SkipZitiIdentityRecord {
        throw SkipZitiError.unsupportedPlatform(reason: "Android bridge available only when building with Skip")
    }

    public func revoke(alias: String) async throws {
        throw SkipZitiError.unsupportedPlatform(reason: "Android bridge available only when building with Skip")
    }

    public func cachedIdentities() async throws -> [SkipZitiIdentityRecord] {
        []
    }
}
#endif
