import Foundation
import PromiseKit

extension Storage : SessionMessagingKitStorageProtocol {

    // MARK: - Signal Protocol
    
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



    // MARK: - Shared Sender Keys

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



    // MARK: - Jobs

    public func persist(_ job: Job, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).setObject(job, forKey: job.id!, inCollection: type(of: job).collection)
    }

    public func markJobAsSucceeded(_ job: Job, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: job.id!, inCollection: type(of: job).collection)
    }

    public func markJobAsFailed(_ job: Job, using transaction: Any) {
        (transaction as! YapDatabaseReadWriteTransaction).removeObject(forKey: job.id!, inCollection: type(of: job).collection)
    }

    public func getAllPendingJobs(of type: Job.Type) -> [Job] {
        var result: [Job] = []
        Storage.read { transaction in
            transaction.enumerateRows(inCollection: type.collection) { _, object, _, _ in
                guard let job = object as? Job else { return }
                result.append(job)
            }
        }
        return result
    }



    // MARK: - Authorization

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



    // MARK: - Open Group Public Keys

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



    // MARK: - Last Message Server ID

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



    // MARK: - Last Deletion Server ID

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



    // MARK: - Open Group Metadata

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

    

    // MARK: - Message Handling

    public func isBlocked(_ publicKey: String) -> Bool {
        return SSKEnvironment.shared.blockingManager.isRecipientIdBlocked(publicKey)
    }

    public func updateProfile(for publicKey: String, from profile: VisibleMessage.Profile, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let profileManager = SSKEnvironment.shared.profileManager
        if let displayName = profile.displayName {
            profileManager.updateProfileForContact(withID: publicKey, displayName: displayName, with: transaction)
        }
        if let profileKey = profile.profileKey, let profilePictureURL = profile.profilePictureURL, profileKey.count == kAES256_KeyByteLength {
            profileManager.setProfileKeyData(profileKey, forRecipientId: publicKey, avatarURL: profilePictureURL)
        }
    }

    /// Returns the ID of the thread the message was stored under along with the `TSIncomingMessage` that was constructed.
    public func persist(_ message: VisibleMessage, using transaction: Any) -> (String, Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        let thread = TSContactThread.getOrCreateThread(withContactId: message.sender!, transaction: transaction)
        let message = TSIncomingMessage.from(message, associatedWith: thread, using: transaction)
        message.save(with: transaction)
        return (thread.uniqueId!, message)
    }

    public func showTypingIndicatorIfNeeded(for senderPublicKey: String) {
        var threadOrNil: TSContactThread?
        Storage.read { transaction in
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        func showTypingIndicatorsIfNeeded() {
            SSKEnvironment.shared.typingIndicators.didReceiveTypingStartedMessage(inThread: thread, recipientId: senderPublicKey, deviceId: 1)
        }
        if Thread.current.isMainThread {
            showTypingIndicatorsIfNeeded()
        } else {
            DispatchQueue.main.async {
                showTypingIndicatorsIfNeeded()
            }
        }
    }

    public func hideTypingIndicatorIfNeeded(for senderPublicKey: String) {
        var threadOrNil: TSContactThread?
        Storage.read { transaction in
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        func hideTypingIndicatorsIfNeeded() {
            SSKEnvironment.shared.typingIndicators.didReceiveTypingStoppedMessage(inThread: thread, recipientId: senderPublicKey, deviceId: 1)
        }
        if Thread.current.isMainThread {
            hideTypingIndicatorsIfNeeded()
        } else {
            DispatchQueue.main.async {
                hideTypingIndicatorsIfNeeded()
            }
        }
    }

    public func cancelTypingIndicatorsIfNeeded(for senderPublicKey: String) {
        var threadOrNil: TSContactThread?
        Storage.read { transaction in
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        func cancelTypingIndicatorsIfNeeded() {
            SSKEnvironment.shared.typingIndicators.didReceiveIncomingMessage(inThread: thread, recipientId: senderPublicKey, deviceId: 1)
        }
        if Thread.current.isMainThread {
            cancelTypingIndicatorsIfNeeded()
        } else {
            DispatchQueue.main.async {
                cancelTypingIndicatorsIfNeeded()
            }
        }
    }

    public func notifyUserIfNeeded(for message: Any, threadID: String) {
        guard let thread = TSThread.fetch(uniqueId: threadID) else { return }
        Storage.read { transaction in
            SSKEnvironment.shared.notificationsManager!.notifyUser(for: (message as! TSIncomingMessage), in: thread, transaction: transaction)
        }
    }

    public func markMessagesAsRead(_ timestamps: [UInt64], from senderPublicKey: String, at timestamp: UInt64) {
        SSKEnvironment.shared.readReceiptManager.processReadReceipts(fromRecipientId: senderPublicKey, sentTimestamps: timestamps.map { NSNumber(value: $0) }, readTimestamp: timestamp)
    }

    public func setExpirationTimer(to duration: UInt32, for senderPublicKey: String, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var threadOrNil: TSContactThread?
        Storage.read { transaction in
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        let configuration = OWSDisappearingMessagesConfiguration(threadId: thread.uniqueId!, enabled: true, durationSeconds: duration)
        configuration.save(with: transaction)
        let senderDisplayName = SSKEnvironment.shared.profileManager.profileNameForRecipient(withID: senderPublicKey, transaction: transaction)
        let message = OWSDisappearingConfigurationUpdateInfoMessage(timestamp: NSDate.millisecondTimestamp(), thread: thread,
            configuration: configuration, createdByRemoteName: senderDisplayName, createdInExistingGroup: false)
        message.save(with: transaction)
        SSKEnvironment.shared.disappearingMessagesJob.startIfNecessary()
    }

    public func disableExpirationTimer(for senderPublicKey: String, using transaction: Any) {
        let transaction = transaction as! YapDatabaseReadWriteTransaction
        var threadOrNil: TSContactThread?
        Storage.read { transaction in
            threadOrNil = TSContactThread.getWithContactId(senderPublicKey, transaction: transaction)
        }
        guard let thread = threadOrNil else { return }
        let configuration = OWSDisappearingMessagesConfiguration(threadId: thread.uniqueId!, enabled: false, durationSeconds: 24 * 60 * 60)
        configuration.save(with: transaction)
        let senderDisplayName = SSKEnvironment.shared.profileManager.profileNameForRecipient(withID: senderPublicKey, transaction: transaction)
        let message = OWSDisappearingConfigurationUpdateInfoMessage(timestamp: NSDate.millisecondTimestamp(), thread: thread,
            configuration: configuration, createdByRemoteName: senderDisplayName, createdInExistingGroup: false)
        message.save(with: transaction)
        SSKEnvironment.shared.disappearingMessagesJob.startIfNecessary()
    }
}
