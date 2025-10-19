import Foundation

public struct ZitiServiceDescriptor: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var postureRequirements: [String]

    public init(id: String, name: String, postureRequirements: [String] = []) {
        self.id = id
        self.name = name
        self.postureRequirements = postureRequirements
    }
}

public struct TunnelChannel: Sendable {
    private let continuation: AsyncStream<Data>.Continuation
    private let inbox: AsyncStream<Data>

    init(continuation: AsyncStream<Data>.Continuation, inbox: AsyncStream<Data>) {
        self.continuation = continuation
        self.inbox = inbox
    }

    public var messages: AsyncStream<Data> {
        inbox
    }

    public func send(_ data: Data) async throws {
        continuation.yield(data)
    }

    public func close() {
        continuation.finish()
    }
}

public enum ZitiClientEvent: Sendable, Equatable {
    case starting
    case ready([ZitiServiceDescriptor])
    case identityAdded(ZitiIdentityRecord)
    case identityRemoved(String)
    case stopped
}

public final class ZitiClient: @unchecked Sendable {
    public let configuration: ZitiConfiguration

    private let runtime: ZitiRuntime
    private let identityManager: ZitiIdentityManager
    private let eventStream: AsyncStream<ZitiClientEvent>
    private let eventContinuation: AsyncStream<ZitiClientEvent>.Continuation

    private init(
        configuration: ZitiConfiguration,
        runtime: ZitiRuntime,
        identityManager: ZitiIdentityManager,
        eventStream: AsyncStream<ZitiClientEvent>,
        continuation: AsyncStream<ZitiClientEvent>.Continuation
    ) {
        self.configuration = configuration
        self.runtime = runtime
        self.identityManager = identityManager
        self.eventStream = eventStream
        self.eventContinuation = continuation
    }

    public static func bootstrap(
        configuration: ZitiConfiguration,
        controller: any ControllerClient
    ) async throws -> ZitiClient {
        let runtime = ZitiRuntime(configuration: configuration)
        let identityManager = ZitiIdentityManager(
            storage: configuration.identityStore,
            controller: controller
        )
        var continuation: AsyncStream<ZitiClientEvent>.Continuation!
        let stream = AsyncStream<ZitiClientEvent> { cont in
            continuation = cont
        }
        let client = ZitiClient(
            configuration: configuration,
            runtime: runtime,
            identityManager: identityManager,
            eventStream: stream,
            continuation: continuation
        )
        continuation.yield(.starting)
        try await runtime.start()
        let cached = try await identityManager.cachedIdentities()
        cached.forEach { continuation.yield(.identityAdded($0)) }
        continuation.yield(.ready([]))
        return client
    }

    public var events: AsyncStream<ZitiClientEvent> {
        eventStream
    }

    public func enrollIdentity(request: EnrollmentRequest) async -> EnrollmentResult {
        let result = await identityManager.enroll(request: request)
        if case .success(let record) = result {
            eventContinuation.yield(.identityAdded(record))
        }
        return result
    }

    public func revokeIdentity(alias: String) async -> Result<Void, SkipZitiError> {
        let result = await identityManager.revokeIdentity(withAlias: alias)
        if case .success = result {
            eventContinuation.yield(.identityRemoved(alias))
        }
        return result
    }

    public func openTunnel(for service: ZitiServiceDescriptor) -> TunnelChannel {
        var continuation: AsyncStream<Data>.Continuation!
        let inbox = AsyncStream<Data> { cont in
            continuation = cont
        }
        return TunnelChannel(continuation: continuation, inbox: inbox)
    }

    public func shutdown() async {
        _ = await runtime.shutdown()
        eventContinuation.yield(.stopped)
        eventContinuation.finish()
    }
}
