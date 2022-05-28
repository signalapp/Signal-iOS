import PromiseKit
import Sodium
import SessionSnodeKit

public protocol SessionMessagingKitStorageProtocol {

    // MARK: - Shared

    @discardableResult
    func write(with block: @escaping (Any) -> Void) -> Promise<Void>
    @discardableResult
    func write(with block: @escaping (Any) -> Void, completion: @escaping () -> Void) -> Promise<Void>
    func writeSync(with block: @escaping (Any) -> Void)

    // MARK: - Authorization

    func getAuthToken(for room: String, on server: String) -> String?
    func setAuthToken(for room: String, on server: String, to newValue: String, using transaction: Any)
    func removeAuthToken(for room: String, on server: String, using transaction: Any)

    // MARK: - Open Groups

    func getAllV2OpenGroups() -> [String:OpenGroupV2]
    func getV2OpenGroup(for threadID: String) -> OpenGroupV2?
    func v2GetThreadID(for v2OpenGroupID: String) -> String?
    
    // MARK: - Open Group Public Keys

    func getOpenGroupPublicKey(for server: String) -> String?
    func setOpenGroupPublicKey(for server: String, to newValue: String, using transaction: Any)

    // MARK: - Last Message Server ID

    func getLastMessageServerID(for room: String, on server: String) -> Int64?
    func setLastMessageServerID(for room: String, on server: String, to newValue: Int64, using transaction: Any)
    func removeLastMessageServerID(for room: String, on server: String, using transaction: Any)

    // MARK: - Last Deletion Server ID

    func getLastDeletionServerID(for room: String, on server: String) -> Int64?
    func setLastDeletionServerID(for room: String, on server: String, to newValue: Int64, using transaction: Any)
    func removeLastDeletionServerID(for room: String, on server: String, using transaction: Any)
    
    // MARK: - OpenGroupServerIdToUniqueIdLookup

    func getOpenGroupServerIdLookup(_ serverId: UInt64, in room: String, on server: String, using transaction: YapDatabaseReadTransaction) -> OpenGroupServerIdLookup?
    func addOpenGroupServerIdLookup(_ serverId: UInt64?, tsMessageId: String?, in room: String, on server: String, using transaction: YapDatabaseReadWriteTransaction)
    func addOpenGroupServerIdLookup(_ lookup: OpenGroupServerIdLookup, using transaction: YapDatabaseReadWriteTransaction)
    func removeOpenGroupServerIdLookup(_ serverId: UInt64, in room: String, on server: String, using transaction: YapDatabaseReadWriteTransaction)

    // MARK: - Open Group Metadata

    func setUserCount(to newValue: UInt64, forV2OpenGroupWithID openGroupID: String, using transaction: Any)
}

extension Storage: SessionMessagingKitStorageProtocol {}
