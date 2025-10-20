#if !SKIP_BRIDGE
import Foundation

public final class SkipZitiInMemoryIdentityStore: SkipZitiIdentityStore, @unchecked Sendable {
    private var storage: [String: SkipZitiIdentityRecord] = [:]
    private let lock = NSLock()

    public init() {}

    public func persist(record: SkipZitiIdentityRecord) throws {
        lock.lock()
        storage[record.alias] = record
        lock.unlock()
    }

    public func fetchAll() throws -> [SkipZitiIdentityRecord] {
        lock.lock()
        let records = Array(storage.values)
        lock.unlock()
        return records
    }

    public func delete(alias: String) throws {
        lock.lock()
        storage.removeValue(forKey: alias)
        lock.unlock()
    }
}
#endif
