import Foundation
import SkipZitiCore
import SkipZitiIdentity
import SkipZitiServices

public typealias SkipZitiIdentityRecord = ZitiIdentityRecord
public typealias SkipZitiIdentityPayload = ZitiIdentityPayload
public typealias SkipZitiServiceDescriptor = ZitiServiceDescriptor
public typealias SkipZitiClientEvent = ZitiClientEvent
public typealias SkipZitiTunnelChannel = TunnelChannel

public protocol SkipZitiControllerClient: ControllerClient {}

public enum SkipZiti {
    public static func bootstrap(
        controllerURL: URL,
        identityStore: any SecureIdentityStore,
        controller: any SkipZitiControllerClient,
        logLevel: ZitiConfiguration.LogLevel = .info
    ) async throws -> ZitiClient {
        let configuration = ZitiConfiguration(
            controllerURL: controllerURL,
            logLevel: logLevel,
            identityStore: identityStore
        )
        return try await ZitiClient.bootstrap(configuration: configuration, controller: controller)
    }
}

public final class InMemoryIdentityStore: @unchecked Sendable, SecureIdentityStore {
    private var storage: [String: ZitiIdentityRecord] = [:]
    private let lock = NSLock()

    public init() {}

    public func persist(identity: ZitiIdentityPayload) throws -> ZitiIdentityRecord {
        let record = ZitiIdentityRecord(
            alias: identity.alias,
            controllerURL: identity.controller,
            fingerprint: identity.certificate.base64EncodedString()
        )
        lock.lock()
        storage[record.alias] = record
        lock.unlock()
        return record
    }

    public func fetchIdentities() throws -> [ZitiIdentityRecord] {
        lock.lock()
        let values = Array(storage.values)
        lock.unlock()
        return values
    }

    public func deleteIdentity(withAlias alias: String) throws {
        lock.lock()
        storage.removeValue(forKey: alias)
        lock.unlock()
    }
}
