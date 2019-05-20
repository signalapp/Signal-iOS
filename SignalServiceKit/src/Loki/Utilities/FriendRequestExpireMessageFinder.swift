
/*
 This class is used for finding friend request messages which are expired.
 This is modelled after `OWSDisappearingMessagesFinder`.
 */
@objc(OWSLokiFriendRequestExpireMessageFinder)
public class FriendRequestExpireMessageFinder : NSObject {
    public static let friendRequestExpireColumn = "friend_request_expires_at"
    public static let friendRequestExpireIndex = "loki_index_friend_request_expires_at"
    
    public func nextExpirationTimestamp(with transaction: YapDatabaseReadTransaction) -> UInt64? {
        let query = "WHERE \(FriendRequestExpireMessageFinder.friendRequestExpireColumn) > 0 ORDER BY \(FriendRequestExpireMessageFinder.friendRequestExpireColumn) ASC"
        
        let dbQuery = YapDatabaseQuery(string: query, parameters: [])
        let ext = transaction.ext(FriendRequestExpireMessageFinder.friendRequestExpireIndex) as? YapDatabaseSecondaryIndexTransaction
        var firstMessage: TSMessage? = nil
        ext?.enumerateKeysAndObjects(matching: dbQuery) { (collection, key, object, stop) in
            firstMessage = object as? TSMessage
            stop.pointee = true
        }
        
        guard let expireTime = firstMessage?.friendRequestExpiresAt, expireTime > 0 else { return nil }
        
        return expireTime
    }
    
    public func enumurateExpiredMessages(with block: (TSMessage) -> Void, transaction: YapDatabaseReadTransaction) {
        for messageId in fetchExpiredMessageIds(with: transaction) {
            guard let message = TSMessage.fetch(uniqueId: messageId, transaction: transaction) else { continue }
            block(message)
        }
    }
    
    private func fetchExpiredMessageIds(with transaction: YapDatabaseReadTransaction) -> [String] {
        var messageIds = [String]()
        let now = NSDate.ows_millisecondTimeStamp()

        let query = "WHERE \(FriendRequestExpireMessageFinder.friendRequestExpireColumn) > 0 AND \(FriendRequestExpireMessageFinder.friendRequestExpireColumn) <= \(now)"
        // When (expireAt == 0) then the friend request SHOULD NOT expire
        let dbQuery = YapDatabaseQuery(string: query, parameters: [])
        if let ext = transaction.ext(FriendRequestExpireMessageFinder.friendRequestExpireIndex) as? YapDatabaseSecondaryIndexTransaction {
            ext.enumerateKeys(matching: dbQuery) { (_, key, _) in
                messageIds.append(key)
            }
        }

        return Array(messageIds)
    }
    
}

// MARK: YapDatabaseExtension

public extension FriendRequestExpireMessageFinder {
    
    @objc public static var indexDatabaseExtension: YapDatabaseSecondaryIndex {
        let setup = YapDatabaseSecondaryIndexSetup()
        setup.addColumn(friendRequestExpireColumn, with: .integer)
        
        let handler = YapDatabaseSecondaryIndexHandler.withObjectBlock { (transaction, dict, collection, key, object) in
            guard let message = object as? TSMessage else { return }
            
            // Only select messages whose status is sent
            guard message is TSOutgoingMessage && message.isFriendRequest else { return }
            
            // TODO: Replace this with unlock timer
            dict[friendRequestExpireColumn] = message.friendRequestExpiresAt
        }
        
        return YapDatabaseSecondaryIndex(setup: setup, handler: handler)
    }
    
    @objc public static var databaseExtensionName: String {
        return friendRequestExpireIndex
    }
    
    @objc public static func asyncRegisterDatabaseExtensions(_ storage: OWSStorage) {
        storage.register(indexDatabaseExtension, withName: friendRequestExpireIndex)
    }
}

