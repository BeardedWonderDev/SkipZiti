import Foundation

public struct EnrollmentRequest: Sendable, Hashable {
    public var jwtData: Data
    public var alias: String

    public init(jwtData: Data, alias: String) {
        self.jwtData = jwtData
        self.alias = alias
    }
}

public enum EnrollmentResult: Sendable {
    case success(ZitiIdentityRecord)
    case postureViolation(details: String)
    case failure(SkipZitiError)
}

public protocol ControllerClient: Sendable {
    func enroll(csr: Data, alias: String) async throws -> ZitiIdentityPayload
    func revoke(alias: String) async throws
}

public actor ZitiIdentityManager {
    internal let storage: any SecureIdentityStore
    internal let controller: any ControllerClient

    public init(storage: any SecureIdentityStore, controller: any ControllerClient) {
        self.storage = storage
        self.controller = controller
    }

    public func enroll(request: EnrollmentRequest) async -> EnrollmentResult {
        do {
            let csr = try CSRBuilder(jwtData: request.jwtData, alias: request.alias).make()
            let payload = try await controller.enroll(csr: csr, alias: request.alias)
            let record = try storage.persist(identity: payload)
            return .success(record)
        } catch let error as SkipZitiError {
            return .failure(error)
        } catch {
            return .failure(.enrollmentFailed(reason: error.localizedDescription))
        }
    }

    public func cachedIdentities() async throws -> [ZitiIdentityRecord] {
        try storage.fetchIdentities()
    }

    public func revokeIdentity(withAlias alias: String) async -> Result<Void, SkipZitiError> {
        do {
            try await controller.revoke(alias: alias)
            try storage.deleteIdentity(withAlias: alias)
            return .success(())
        } catch let error as SkipZitiError {
            return .failure(error)
        } catch {
            return .failure(.storageFailure(reason: error.localizedDescription))
        }
    }
}

public struct CSRBuilder {
    internal let jwtData: Data
    internal let alias: String

    public init(jwtData: Data, alias: String) {
        self.jwtData = jwtData
        self.alias = alias
    }

    public func make() throws -> Data {
        guard !jwtData.isEmpty else {
            throw SkipZitiError.enrollmentFailed(reason: "JWT payload is empty for alias \(alias)")
        }
        // Placeholder CSR generation until OpenZiti bindings are wired.
        return Data("CSR:\(alias)".utf8)
    }
}
