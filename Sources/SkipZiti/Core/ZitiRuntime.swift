import Foundation

public enum SkipZitiError: Error, Sendable {
    case runtimeNotStarted
    case duplicateStartAttempt
    case enrollmentFailed(reason: String)
    case storageFailure(reason: String)
}

public protocol SecureIdentityStore: Sendable {
    func persist(identity: ZitiIdentityPayload) throws -> ZitiIdentityRecord
    func fetchIdentities() throws -> [ZitiIdentityRecord]
    func deleteIdentity(withAlias alias: String) throws
}

public struct ZitiIdentityPayload: Sendable, Hashable {
    public var certificate: Data
    public var privateKey: Data
    public var controller: URL
    public var alias: String

    public init(certificate: Data, privateKey: Data, controller: URL, alias: String) {
        self.certificate = certificate
        self.privateKey = privateKey
        self.controller = controller
        self.alias = alias
    }
}

public struct ZitiIdentityRecord: Sendable, Hashable {
    public enum Status: Sendable, Equatable {
        case ready
        case postureViolation(details: String)
        case revoked
    }

    public var alias: String
    public var controllerURL: URL
    public var fingerprint: String
    public var status: Status
    public var enrolledAt: Date

    public init(
        alias: String,
        controllerURL: URL,
        fingerprint: String,
        status: Status = .ready,
        enrolledAt: Date = .now
    ) {
        self.alias = alias
        self.controllerURL = controllerURL
        self.fingerprint = fingerprint
        self.status = status
        self.enrolledAt = enrolledAt
    }
}

public struct ZitiConfiguration: Sendable {
    public enum LogLevel: String, Sendable {
        case trace
        case debug
        case info
        case warn
        case error
    }

    public var controllerURL: URL
    public var logLevel: LogLevel
    public var identityStore: any SecureIdentityStore
    public var enableTelemetry: Bool

    public init(
        controllerURL: URL,
        logLevel: LogLevel = .info,
        identityStore: any SecureIdentityStore,
        enableTelemetry: Bool = true
    ) {
        self.controllerURL = controllerURL
        self.logLevel = logLevel
        self.identityStore = identityStore
        self.enableTelemetry = enableTelemetry
    }
}

public actor ZitiRuntime {
    public enum State: Sendable {
        case idle
        case starting
        case running
        case stopping
    }

    private let configuration: ZitiConfiguration
    private var state: State = .idle
    private var observers: [UUID: @Sendable (State) -> Void] = [:]

    public init(configuration: ZitiConfiguration) {
        self.configuration = configuration
    }

    @discardableResult
    public func start() async throws -> State {
        guard state == .idle else {
            throw SkipZitiError.duplicateStartAttempt
        }
        state = .starting
        notifyObservers()
        try await Task.sleep(nanoseconds: 10_000_000) // placeholder for libuv bootstrap
        state = .running
        notifyObservers()
        return state
    }

    @discardableResult
    public func shutdown() async -> State {
        guard state == .running else {
            return state
        }
        state = .stopping
        notifyObservers()
        try? await Task.sleep(nanoseconds: 10_000_000) // placeholder for teardown
        state = .idle
        notifyObservers()
        return state
    }

    public func currentState() -> State {
        state
    }

    @discardableResult
    public func addStateObserver(_ block: @escaping @Sendable (State) -> Void) -> UUID {
        let token = UUID()
        observers[token] = block
        block(state)
        return token
    }

    public func removeStateObserver(_ token: UUID) {
        observers.removeValue(forKey: token)
    }

    private func notifyObservers() {
        observers.values.forEach { observer in
            observer(state)
        }
    }
}
