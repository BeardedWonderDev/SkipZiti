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
        do {
            try await bridge.start(configuration: configuration) { event in
                client.emit(event)
            }
        } catch {
            client.handleBridgeError(
                error,
                stage: .startup,
                defaultMessage: "Failed to start SkipZiti bridge",
                recoverable: false
            )
            throw error
        }

        do {
            try await client.persistInitialIdentities()
        } catch {
            client.handleBridgeError(
                error,
                stage: .runtime,
                defaultMessage: "Failed to cache initial SkipZiti identities",
                recoverable: true
            )
            throw error
        }
        return client
    }

    public func enroll(jwt: Data, alias: String) async throws -> SkipZitiIdentityRecord {
        do {
            let record = try await bridge.enroll(jwt: jwt, alias: alias)
            do {
                try persist(record: record)
            } catch {
                handleBridgeError(
                    error,
                    stage: .runtime,
                    defaultMessage: "Failed to persist enrolled identity",
                    recoverable: true
                )
                throw error
            }
            return record
        } catch {
            handleBridgeError(
                error,
                stage: .enrollment,
                defaultMessage: "SkipZiti enrollment failed",
                recoverable: false
            )
            throw error
        }
    }

    public func revoke(alias: String) async throws {
        do {
            try await bridge.revoke(alias: alias)
        } catch {
            handleBridgeError(
                error,
                stage: .runtime,
                defaultMessage: "SkipZiti revoke failed",
                recoverable: false
            )
            throw error
        }

        do {
            try identityStore?.delete(alias: alias)
        } catch {
            handleBridgeError(
                error,
                stage: .runtime,
                defaultMessage: "Failed to remove identity from local store",
                recoverable: true
            )
            throw error
        }
    }

    public func cachedIdentities() async throws -> [SkipZitiIdentityRecord] {
        if let store = identityStore {
            do {
                return try store.fetchAll()
            } catch {
                handleBridgeError(
                    error,
                    stage: .runtime,
                    defaultMessage: "Failed to load cached SkipZiti identities",
                    recoverable: true
                )
                throw error
            }
        }
        do {
            return try await bridge.cachedIdentities()
        } catch {
            handleBridgeError(
                error,
                stage: .runtime,
                defaultMessage: "Failed to fetch identities from SkipZiti bridge",
                recoverable: true
            )
            throw error
        }
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

    @discardableResult
    private func handleBridgeError(
        _ error: Error,
        stage: SkipZitiReportedError.Stage,
        defaultMessage: String,
        recoverable: Bool,
        defaultDetails: String? = nil
    ) -> SkipZitiReportedError {
        let reported = SkipZitiReportedError.bridgeFailure(
            from: error,
            stage: stage,
            defaultMessage: defaultMessage,
            recoverable: recoverable,
            defaultDetails: defaultDetails
        )
        emit(.errorReported(reported))
        return reported
    }
}
#endif
