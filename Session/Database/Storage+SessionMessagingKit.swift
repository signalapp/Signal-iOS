import Foundation
import PromiseKit

extension Storage : SessionMessagingKitStorageProtocol {

    // MARK: Signal Protocol
    public func getOrGenerateRegistrationID(using transaction: Any) -> UInt32 {
        SSKEnvironment.shared.tsAccountManager.getOrGenerateRegistrationId(transaction as! YapDatabaseReadWriteTransaction)
    }

    public func getSenderCertificate(for publicKey: String) -> SMKSenderCertificate {
        let (promise, seal) = Promise<SMKSenderCertificate>.pending()
        SSKEnvironment.shared.udManager.ensureSenderCertificate { senderCertificate in
            seal.fulfill(senderCertificate)
        } failure: { error in
            // Should never fail
        }
        return try! promise.wait()
    }

    // MARK: Shared Sender Keys
    private static let closedGroupPrivateKeyCollection = "LokiClosedGroupPrivateKeyCollection"

    public func getClosedGroupPrivateKey(for publicKey: String) -> String? {
        var result: String?
        Storage.read { transaction in
            result = transaction.object(forKey: publicKey, inCollection: Storage.closedGroupPrivateKeyCollection) as? String
        }
        return result
    }

    internal static func setClosedGroupPrivateKey(_ privateKey: String, for publicKey: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(privateKey, forKey: publicKey, inCollection: Storage.closedGroupPrivateKeyCollection)
    }

    internal static func removeClosedGroupPrivateKey(for publicKey: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: publicKey, inCollection: Storage.closedGroupPrivateKeyCollection)
    }

    func getUserClosedGroupPublicKeys() -> Set<String> {
        var result: Set<String> = []
        Storage.read { transaction in
            result = Set(transaction.allKeys(inCollection: Storage.closedGroupPrivateKeyCollection))
        }
        return result
    }

    public func isClosedGroup(_ publicKey: String) -> Bool {
        getUserClosedGroupPublicKeys().contains(publicKey)
    }

    // MARK: Jobs
    public func persist(_ job: Job, using transaction: Any) { fatalError("Not implemented.") }
    public func markJobAsSucceeded(_ job: Job, using transaction: Any) { fatalError("Not implemented.") }
    public func markJobAsFailed(_ job: Job, using transaction: Any) { fatalError("Not implemented.") }

    // MARK: Authorization
    private static func getAuthTokenCollection(for server: String) -> String {
        return (server == FileServerAPI.server) ? "LokiStorageAuthTokenCollection" : "LokiGroupChatAuthTokenCollection"
    }

    public func getAuthToken(for server: String) -> String? {
        let collection = Storage.getAuthTokenCollection(for: server)
        var result: String? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: server, inCollection: collection) as? String
        }
        return result
    }

    public func setAuthToken(for server: String, to newValue: String, using transaction: Any) {
        let collection = Storage.getAuthTokenCollection(for: server)
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: server, inCollection: collection)
    }

    public func removeAuthToken(for server: String, using transaction: Any) {
        let collection = Storage.getAuthTokenCollection(for: server)
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: server, inCollection: collection)
    }

    // MARK: Open Group Public Keys
    private static let openGroupPublicKeyCollection = "LokiOpenGroupPublicKeyCollection"

    public func getOpenGroupPublicKey(for server: String) -> String? {
        var result: String? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: server, inCollection: Storage.openGroupPublicKeyCollection) as? String
        }
        return result
    }

    public func setOpenGroupPublicKey(for server: String, to newValue: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: server, inCollection: Storage.openGroupPublicKeyCollection)
    }

    // MARK: Last Message Server ID
    private static let lastMessageServerIDCollection = "LokiGroupChatLastMessageServerIDCollection"

    public func getLastMessageServerID(for group: UInt64, on server: String) -> UInt64? {
        var result: UInt64? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: "\(server).\(group)", inCollection: Storage.lastMessageServerIDCollection) as? UInt64
        }
        return result
    }

    public func setLastMessageServerID(for group: UInt64, on server: String, to newValue: UInt64, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: "\(server).\(group)", inCollection: Storage.lastMessageServerIDCollection)
    }

    public func removeLastMessageServerID(for group: UInt64, on server: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: "\(server).\(group)", inCollection: Storage.lastMessageServerIDCollection)
    }

    // MARK: Last Deletion Server ID
    private static let lastDeletionServerIDCollection = "LokiGroupChatLastDeletionServerIDCollection"

    public func getLastDeletionServerID(for group: UInt64, on server: String) -> UInt64? {
        var result: UInt64? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: "\(server).\(group)", inCollection: Storage.lastDeletionServerIDCollection) as? UInt64
        }
        return result
    }

    public func setLastDeletionServerID(for group: UInt64, on server: String, to newValue: UInt64, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: "\(server).\(group)", inCollection: Storage.lastDeletionServerIDCollection)
    }

    public func removeLastDeletionServerID(for group: UInt64, on server: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: "\(server).\(group)", inCollection: Storage.lastDeletionServerIDCollection)
    }

    // MARK: Open Group Metadata
    private static let openGroupUserCountCollection = "LokiPublicChatUserCountCollection"
    private static let openGroupMessageIDCollection = "LKMessageIDCollection"

    public func setUserCount(to newValue: Int, forOpenGroupWithID openGroupID: String, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(newValue, forKey: openGroupID, inCollection: Storage.openGroupUserCountCollection)
    }

    public func getIDForMessage(withServerID serverID: UInt64) -> UInt64? {
        var result: UInt64? = nil
        Storage.read { transaction in
            result = transaction.object(forKey: String(serverID), inCollection: Storage.openGroupMessageIDCollection) as? UInt64
        }
        return result
    }
    
    public func setOpenGroupDisplayName(to displayName: String, for publicKey: String, on channel: UInt64, server: String, using transaction: Any) {
        let collection = "\(server).\(channel)" // FIXME: This should be a proper collection
        (transaction as! YapDatabaseReadWriteTransaction).setObject(displayName, forKey: publicKey, inCollection: collection)
    }
    
    public func setLastProfilePictureUploadDate(_ date: Date)  {
        UserDefaults.standard[.lastProfilePictureUpload] = date
    }
}
