#if !SKIP_BRIDGE
import Foundation

public final class SkipZitiClient: @unchecked Sendable {
    public let configuration: SkipZitiConfiguration

    private let bridge: any SkipZitiPlatformBridge
    private let eventStream: AsyncStream<SkipZitiClientEvent>
    private let identityStore: (any SkipZitiIdentityStore)?
    private let continuationLock = NSLock()
    private var eventContinuation: AsyncStream<SkipZitiClientEvent>.Continuation?

    private init(
        configuration: SkipZitiConfiguration,
        bridge: any SkipZitiPlatformBridge,
        eventStream: AsyncStream<SkipZitiClientEvent>,
        continuation: AsyncStream<SkipZitiClientEvent>.Continuation,
        identityStore: (any SkipZitiIdentityStore)?
    ) {
        self.configuration = configuration
        self.bridge = bridge
        self.eventStream = eventStream
        self.identityStore = identityStore
        self.eventContinuation = continuation
    }

    public var events: AsyncStream<SkipZitiClientEvent> { eventStream }

    public static func bootstrap(
        configuration: SkipZitiConfiguration,
        bridge: any SkipZitiPlatformBridge,
        identityStore: (any SkipZitiIdentityStore)? = nil
    ) async throws -> SkipZitiClient {
        var continuation: AsyncStream<SkipZitiClientEvent>.Continuation!
        let stream = AsyncStream<SkipZitiClientEvent> { cont in
            continuation = cont
            cont.yield(.starting)
        }

        let client = SkipZitiClient(
            configuration: configuration,
            bridge: bridge,
            eventStream: stream,
            continuation: continuation,
            identityStore: identityStore
        )
        try await bridge.start(configuration: configuration) { event in
            client.emit(event)
        }
        try await client.persistInitialIdentities()
        return client
    }

    public func enroll(jwt: Data, alias: String) async throws -> SkipZitiIdentityRecord {
        let record = try await bridge.enroll(jwt: jwt, alias: alias)
        try persist(record: record)
        return record
    }

    public func revoke(alias: String) async throws {
        try await bridge.revoke(alias: alias)
        try identityStore?.delete(alias: alias)
    }

    public func cachedIdentities() async throws -> [SkipZitiIdentityRecord] {
        if let store = identityStore {
            return try store.fetchAll()
        }
        return try await bridge.cachedIdentities()
    }

    public func shutdown() async {
        await bridge.shutdown()
        emit(.stopped)
    }

    private func persistInitialIdentities() async throws {
        guard let store = identityStore else { return }
        let records = try await bridge.cachedIdentities()
        for record in records {
            try store.persist(record: record)
        }
    }

    private func persist(record: SkipZitiIdentityRecord) throws {
        try identityStore?.persist(record: record)
    }

    private func emit(_ event: SkipZitiClientEvent) {
        continuationLock.lock()
        defer { continuationLock.unlock() }
        guard let continuation = eventContinuation else { return }
        continuation.yield(event)
        if case .stopped = event {
            continuation.finish()
            eventContinuation = nil
        }
    }
}
#endif
