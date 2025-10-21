#if !SKIP_BRIDGE
import Foundation

public enum SkipZitiError: Error, Equatable, Sendable {
    case unsupportedPlatform(reason: String)
    case enrollmentFailed(reason: String)
    case storageFailure(reason: String)
    case runtimeFailure(reason: String)
}

public enum SkipZitiLogLevel: String, Sendable {
    case trace
    case debug
    case info
    case warn
    case error
}

public struct SkipZitiKeyValue: Sendable, Equatable {
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}

public struct SkipZitiStringMap: Sendable, Equatable, Hashable {
    private var storage: [String: String]

    public init(entries: [SkipZitiKeyValue] = []) {
        var dictionary: [String: String] = [:]
        for entry in entries {
            dictionary[entry.key] = entry.value
        }
        self.storage = dictionary
    }

    public init(dictionary: [String: String]) {
        self.storage = dictionary
    }

    public var entries: [SkipZitiKeyValue] {
        get {
            storage
                .sorted { $0.key < $1.key }
                .map { SkipZitiKeyValue(key: $0.key, value: $0.value) }
        }
        set {
            var dictionary: [String: String] = [:]
            for entry in newValue {
                dictionary[entry.key] = entry.value
            }
            storage = dictionary
        }
    }

    public mutating func merge(_ dictionary: [String: String]) {
        for (key, value) in dictionary {
            storage[key] = value
        }
    }

    public mutating func merge(_ other: SkipZitiStringMap) {
        merge(other.storage)
    }

    public func value(forKey key: String) -> String? {
        storage[key]
    }

    public mutating func remove(_ key: String) {
        storage.removeValue(forKey: key)
    }

    public func contains(_ key: String) -> Bool {
        storage[key] != nil
    }

    internal var dictionaryRepresentation: [String: String] { storage }

    public static func == (lhs: SkipZitiStringMap, rhs: SkipZitiStringMap) -> Bool {
        lhs.storage == rhs.storage
    }

    public func hash(into hasher: inout Hasher) {
        for (key, value) in storage.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)
            hasher.combine(value)
        }
    }

    internal func toDictionary() -> [String: String] { storage }
}

public struct SkipZitiConfiguration: Sendable {
    public var controllerURL: URL
    public var logLevel: SkipZitiLogLevel
    public var metadata: SkipZitiStringMap

    public init(controllerURL: URL, logLevel: SkipZitiLogLevel = .info, metadata: SkipZitiStringMap = SkipZitiStringMap()) {
        self.controllerURL = controllerURL
        self.logLevel = logLevel
        self.metadata = metadata
    }

    #if !SKIP
    @_disfavoredOverload
    public init(controllerURL: URL, logLevel: SkipZitiLogLevel = .info, metadata: [String: String]? = nil) {
        self.init(controllerURL: controllerURL, logLevel: logLevel, metadata: SkipZitiStringMap(dictionary: metadata ?? [:]))
    }
    #endif
}

public protocol SkipZitiIdentityStore: Sendable {
    func persist(record: SkipZitiIdentityRecord) throws
    func fetchAll() throws -> [SkipZitiIdentityRecord]
    func delete(alias: String) throws
}

public struct SkipZitiIdentityRecord: Sendable, Equatable, Hashable {
    public var alias: String
    public var controllerURL: URL
    public var fingerprint: String
    public var enrolledAt: Date
    public var platformAlias: String?
    public var metadata: SkipZitiStringMap

    public init(
        alias: String,
        controllerURL: URL,
        fingerprint: String,
        enrolledAt: Date? = nil,
        platformAlias: String? = nil,
        metadata: SkipZitiStringMap = SkipZitiStringMap()
    ) {
        self.alias = alias
        self.controllerURL = controllerURL
        self.fingerprint = fingerprint
        self.enrolledAt = enrolledAt ?? Date()
        self.platformAlias = platformAlias
        self.metadata = metadata
    }

    #if !SKIP
    public init(
        alias: String,
        controllerURL: URL,
        fingerprint: String,
        enrolledAt: Date? = nil,
        platformAlias: String? = nil,
        metadata: [String: String]? = nil
    ) {
        self.init(
            alias: alias,
            controllerURL: controllerURL,
            fingerprint: fingerprint,
            enrolledAt: enrolledAt,
            platformAlias: platformAlias,
            metadata: SkipZitiStringMap(dictionary: metadata ?? [:])
        )
    }
    #endif
}

public enum SkipZitiClientEvent: Sendable, Equatable {
    case starting
    case ready([SkipZitiIdentityRecord])
    case identityAdded(SkipZitiIdentityRecord)
    case identityRemoved(String)
    case statusMessage(String)
    case serviceUpdate(SkipZitiServiceUpdate)
    case postureEvent(SkipZitiPostureQueryEvent)
    case errorReported(SkipZitiReportedError)
    case stopped
}

public struct SkipZitiServicePermissions: Sendable, Equatable {
    public var canDial: Bool
    public var canBind: Bool

    public init(canDial: Bool, canBind: Bool) {
        self.canDial = canDial
        self.canBind = canBind
    }
}

public struct SkipZitiPortRange: Sendable, Equatable {
    public var lowerBound: Int
    public var upperBound: Int

    public init(lowerBound: Int, upperBound: Int) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}

public struct SkipZitiServiceIntercept: Sendable, Equatable {
    public var addresses: [String]
    public var protocols: [String]
    public var portRanges: [SkipZitiPortRange]
    public var sourceIP: String?
    public var dialIdentity: String?
    public var connectTimeoutSeconds: Int?

    public init(
        addresses: [String],
        protocols: [String],
        portRanges: [SkipZitiPortRange],
        sourceIP: String? = nil,
        dialIdentity: String? = nil,
        connectTimeoutSeconds: Int? = nil
    ) {
        self.addresses = addresses
        self.protocols = protocols
        self.portRanges = portRanges
        self.sourceIP = sourceIP
        self.dialIdentity = dialIdentity
        self.connectTimeoutSeconds = connectTimeoutSeconds
    }
}

public struct SkipZitiPostureQuery: Sendable, Equatable {
    public var id: String
    public var type: String
    public var isPassing: Bool
    public var timeout: Int64?
    public var timeoutRemaining: Int64?

    public init(
        id: String,
        type: String,
        isPassing: Bool,
        timeout: Int64? = nil,
        timeoutRemaining: Int64? = nil
    ) {
        self.id = id
        self.type = type
        self.isPassing = isPassing
        self.timeout = timeout
        self.timeoutRemaining = timeoutRemaining
    }
}

public struct SkipZitiPostureCheckSet: Sendable, Equatable {
    public var policyId: String
    public var policyType: String
    public var isPassing: Bool
    public var queries: [SkipZitiPostureQuery]

    public init(
        policyId: String,
        policyType: String,
        isPassing: Bool,
        queries: [SkipZitiPostureQuery]
    ) {
        self.policyId = policyId
        self.policyType = policyType
        self.isPassing = isPassing
        self.queries = queries
    }
}

public struct SkipZitiServiceDescriptor: Sendable, Equatable {
    public var name: String
    public var identifier: String
    public var isEncrypted: Bool
    public var permissions: SkipZitiServicePermissions
    public var intercepts: [SkipZitiServiceIntercept]
    public var postureChecks: [SkipZitiPostureCheckSet]
    public var attributes: SkipZitiStringMap

    public init(
        name: String,
        identifier: String,
        isEncrypted: Bool,
        permissions: SkipZitiServicePermissions,
        intercepts: [SkipZitiServiceIntercept],
        postureChecks: [SkipZitiPostureCheckSet],
        attributes: SkipZitiStringMap = SkipZitiStringMap()
    ) {
        self.name = name
        self.identifier = identifier
        self.isEncrypted = isEncrypted
        self.permissions = permissions
        self.intercepts = intercepts
        self.postureChecks = postureChecks
        self.attributes = attributes
    }

    #if !SKIP
    public init(
        name: String,
        identifier: String,
        isEncrypted: Bool,
        permissions: SkipZitiServicePermissions,
        intercepts: [SkipZitiServiceIntercept],
        postureChecks: [SkipZitiPostureCheckSet],
        attributes: [String: String]? = nil
    ) {
        self.init(
            name: name,
            identifier: identifier,
            isEncrypted: isEncrypted,
            permissions: permissions,
            intercepts: intercepts,
            postureChecks: postureChecks,
            attributes: SkipZitiStringMap(dictionary: attributes ?? [:])
        )
    }
    #endif
}

public struct SkipZitiServiceUpdate: Sendable, Equatable {
    public enum ChangeSource: String, Sendable {
        case initial
        case delta
    }

    public var identityAlias: String?
    public var changeSource: ChangeSource
    public var added: [SkipZitiServiceDescriptor]
    public var removed: [SkipZitiServiceDescriptor]
    public var changed: [SkipZitiServiceDescriptor]

    public init(
        identityAlias: String? = nil,
        changeSource: ChangeSource = .delta,
        added: [SkipZitiServiceDescriptor] = [],
        removed: [SkipZitiServiceDescriptor] = [],
        changed: [SkipZitiServiceDescriptor] = []
    ) {
        self.identityAlias = identityAlias
        self.changeSource = changeSource
        self.added = added
        self.removed = removed
        self.changed = changed
    }
}

public struct SkipZitiPostureQueryEvent: Sendable, Equatable {
    public enum QueryType: String, Sendable {
        case macAddress
        case operatingSystem
        case domain
        case process
        case unknown
    }

    public enum Resolution: Sendable, Equatable {
        case satisfied(String?)
        case unsupported
        case failed(String)
    }

    public var identityAlias: String?
    public var queryType: QueryType
    public var resolution: Resolution

    public init(
        identityAlias: String? = nil,
        queryType: QueryType,
        resolution: Resolution
    ) {
        self.identityAlias = identityAlias
        self.queryType = queryType
        self.resolution = resolution
    }
}

public struct SkipZitiReportedError: Error, Sendable, Equatable {
    public enum Stage: String, Sendable {
        case startup
        case enrollment
        case runtime
    }

    public var stage: Stage
    public var message: String
    public var details: String?
    public var recoverable: Bool

    public init(stage: Stage, message: String, details: String? = nil, recoverable: Bool = true) {
        self.stage = stage
        self.message = message
        self.details = details
        self.recoverable = recoverable
    }
}

public extension SkipZitiReportedError {
    static func bridgeFailure(
        from error: any Error,
        stage: Stage,
        defaultMessage: String,
        recoverable: Bool,
        defaultDetails: String? = nil
    ) -> SkipZitiReportedError {
        if let reported = error as? SkipZitiReportedError {
            return reported
        }

        if let zitiError = error as? SkipZitiError {
            switch zitiError {
            case let .unsupportedPlatform(reason):
                return SkipZitiReportedError(
                    stage: .startup,
                    message: reason,
                    details: defaultDetails,
                    recoverable: false
                )
            case let .enrollmentFailed(reason):
                return SkipZitiReportedError(
                    stage: .enrollment,
                    message: reason,
                    details: defaultDetails,
                    recoverable: false
                )
            case let .storageFailure(reason):
                return SkipZitiReportedError(
                    stage: .runtime,
                    message: reason,
                    details: defaultDetails,
                    recoverable: recoverable
                )
            case let .runtimeFailure(reason):
                return SkipZitiReportedError(
                    stage: .runtime,
                    message: reason,
                    details: defaultDetails,
                    recoverable: recoverable
                )
            }
        }

        let details = defaultDetails ?? String(describing: error)
        return SkipZitiReportedError(
            stage: stage,
            message: defaultMessage,
            details: details,
            recoverable: recoverable
        )
    }
}

public struct SkipZitiServiceSummary: Sendable, Equatable {
    public struct Intercept: Sendable, Equatable {
        public var addresses: [String]
        public var protocols: [String]
        public var portRanges: [SkipZitiPortRange]
        public var sourceIP: String?
        public var dialIdentity: String?
        public var connectTimeoutSeconds: Int?

        public init(
            addresses: [String],
            protocols: [String],
            portRanges: [SkipZitiPortRange],
            sourceIP: String? = nil,
            dialIdentity: String? = nil,
            connectTimeoutSeconds: Int? = nil
        ) {
            self.addresses = addresses
            self.protocols = protocols
            self.portRanges = portRanges
            self.sourceIP = sourceIP
            self.dialIdentity = dialIdentity
            self.connectTimeoutSeconds = connectTimeoutSeconds
        }
    }

    public var name: String
    public var identifier: String
    public var isEncrypted: Bool
    public var permFlags: Int64
    public var intercepts: [Intercept]
    public var postureChecks: [SkipZitiPostureCheckSet]
    public var attributes: SkipZitiStringMap

    public init(
        name: String,
        identifier: String,
        isEncrypted: Bool,
        permFlags: Int64,
        intercepts: [Intercept],
        postureChecks: [SkipZitiPostureCheckSet],
        attributes: SkipZitiStringMap = SkipZitiStringMap()
    ) {
        self.name = name
        self.identifier = identifier
        self.isEncrypted = isEncrypted
        self.permFlags = permFlags
        self.intercepts = intercepts
        self.postureChecks = postureChecks
        self.attributes = attributes
    }

    #if !SKIP
    public init(
        name: String,
        identifier: String,
        isEncrypted: Bool,
        permFlags: Int64,
        intercepts: [Intercept],
        postureChecks: [SkipZitiPostureCheckSet],
        attributes: [String: String]? = nil
    ) {
        self.init(
            name: name,
            identifier: identifier,
            isEncrypted: isEncrypted,
            permFlags: permFlags,
            intercepts: intercepts,
            postureChecks: postureChecks,
            attributes: SkipZitiStringMap(dictionary: attributes ?? [:])
        )
    }
    #endif
}

public extension SkipZitiServiceDescriptor {
    static func fromSummary(_ summary: SkipZitiServiceSummary) -> SkipZitiServiceDescriptor {
        // Bit masks defined by OpenZiti: 0x01 dial, 0x02 bind.
        let permissions = SkipZitiServicePermissions(
            canDial: (summary.permFlags & Int64(0x01)) != 0,
            canBind: (summary.permFlags & Int64(0x02)) != 0
        )

        let intercepts = summary.intercepts.map {
            SkipZitiServiceIntercept(
                addresses: $0.addresses,
                protocols: $0.protocols,
                portRanges: $0.portRanges,
                sourceIP: $0.sourceIP,
                dialIdentity: $0.dialIdentity,
                connectTimeoutSeconds: $0.connectTimeoutSeconds
            )
        }

        return SkipZitiServiceDescriptor(
            name: summary.name,
            identifier: summary.identifier,
            isEncrypted: summary.isEncrypted,
            permissions: permissions,
            intercepts: intercepts,
            postureChecks: summary.postureChecks,
            attributes: summary.attributes
        )
    }
}

public protocol SkipZitiPlatformBridge: Sendable {
    func start(configuration: SkipZitiConfiguration, emit: @escaping @Sendable (SkipZitiClientEvent) -> Void) async throws
    func shutdown() async
    func enroll(jwt: Data, alias: String) async throws -> SkipZitiIdentityRecord
    func revoke(alias: String) async throws
    func cachedIdentities() async throws -> [SkipZitiIdentityRecord]
}
#endif
