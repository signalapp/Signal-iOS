import PromiseKit
import Sodium
import Curve25519Kit
import YapDatabase
import SessionSnodeKit

public protocol SessionMessagingKitStorageProtocol {

    // MARK: - Shared

    @discardableResult
    func write(with block: @escaping (Any) -> Void) -> Promise<Void>
    @discardableResult
    func write(with block: @escaping (Any) -> Void, completion: @escaping () -> Void) -> Promise<Void>
    func writeSync(with block: @escaping (Any) -> Void)

    // MARK: - General

    func getUserPublicKey() -> String?
    func getUserKeyPair() -> ECKeyPair?
    func getUserED25519KeyPair() -> Box.KeyPair?
    func getUser() -> Contact?
    func getUser(using transaction: YapDatabaseReadTransaction?) -> Contact?
    
    // MARK: - Contacts
    
    func getContact(with sessionID: String) -> Contact?
    func getContact(with sessionID: String, using transaction: Any) -> Contact?
    func setContact(_ contact: Contact, using transaction: Any)
    func getAllContacts() -> Set<Contact>
    func getAllContacts(with transaction: YapDatabaseReadTransaction) -> Set<Contact>
    
    // MARK: - Blinded Id cache
    
    func getBlindedIdMapping(with blindedId: String) -> BlindedIdMapping?
    func getBlindedIdMapping(with blindedId: String, using transaction: YapDatabaseReadTransaction) -> BlindedIdMapping?
    func cacheBlindedIdMapping(_ mapping: BlindedIdMapping)
    func cacheBlindedIdMapping(_ mapping: BlindedIdMapping, using transaction: YapDatabaseReadWriteTransaction)
    func enumerateBlindedIdMapping(with block: @escaping (BlindedIdMapping, UnsafeMutablePointer<ObjCBool>) -> ())
    func enumerateBlindedIdMapping(using transaction: YapDatabaseReadTransaction, with block: @escaping (BlindedIdMapping, UnsafeMutablePointer<ObjCBool>) -> ())

    // MARK: - Closed Groups

    func getClosedGroupEncryptionKeyPairs(for groupPublicKey: String) -> [ECKeyPair]
    func getLatestClosedGroupEncryptionKeyPair(for groupPublicKey: String) -> ECKeyPair?
    func addClosedGroupEncryptionKeyPair(_ keyPair: ECKeyPair, for groupPublicKey: String, using transaction: Any)
    func removeAllClosedGroupEncryptionKeyPairs(for groupPublicKey: String, using transaction: Any)
    func getUserClosedGroupPublicKeys() -> Set<String>
    func getUserClosedGroupPublicKeys(using transaction: YapDatabaseReadTransaction) -> Set<String>
    func getZombieMembers(for groupPublicKey: String) -> Set<String>
    func setZombieMembers(for groupPublicKey: String, to zombies: Set<String>, using transaction: Any)
    func isClosedGroup(_ publicKey: String) -> Bool
    func isClosedGroup(_ publicKey: String, using transaction: YapDatabaseReadTransaction) -> Bool

    // MARK: - Jobs

    func persist(_ job: Job, using transaction: Any)
    func markJobAsSucceeded(_ job: Job, using transaction: Any)
    func markJobAsFailed(_ job: Job, using transaction: Any)
    func getAllPendingJobs(of type: Job.Type) -> [Job]
    func getAttachmentUploadJob(for attachmentID: String) -> AttachmentUploadJob?
    func getMessageSendJob(for messageSendJobID: String) -> MessageSendJob?
    func getMessageSendJob(for messageSendJobID: String, using transaction: Any) -> MessageSendJob?
    func resumeMessageSendJobIfNeeded(_ messageSendJobID: String)
    func isJobCanceled(_ job: Job) -> Bool

    // MARK: - Open Groups

    func getAllOpenGroups() -> [String: OpenGroup]
    func getThreadID(for openGroupID: String) -> String?
    
    func getOpenGroupImage(for room: String, on server: String) -> Data?
    func setOpenGroupImage(to data: Data, for room: String, on server: String, using transaction: Any)
    
    func getOpenGroup(for threadID: String) -> OpenGroup?
    func setOpenGroup(_ openGroup: OpenGroup, for threadID: String, using transaction: Any)
    func removeOpenGroup(for threadID: String, using transaction: Any)
    
    func getUserCount(forOpenGroupWithID openGroupID: String) -> UInt64?
    func setUserCount(to newValue: UInt64, forOpenGroupWithID openGroupID: String, using transaction: Any)
    
    func getOpenGroupServer(name: String) -> OpenGroupAPI.Server?
    func setOpenGroupServer(_ server: OpenGroupAPI.Server, using transaction: Any)
    func removeOpenGroupServer(name: String, using transaction: Any)
    
    // MARK: - -- Open Group Public Keys

    func getOpenGroupPublicKey(for server: String) -> String?
    func setOpenGroupPublicKey(for server: String, to newValue: String, using transaction: Any)
    func removeOpenGroupPublicKey(for server: String, using transaction: Any)

    // MARK: - -- Open Group Sequence Number

    func getOpenGroupSequenceNumber(for room: String, on server: String) -> Int64?
    func setOpenGroupSequenceNumber(for room: String, on server: String, to newValue: Int64, using transaction: Any)
    func removeOpenGroupSequenceNumber(for room: String, on server: String, using transaction: Any)
    
    // MARK: - OpenGroupServerIdToUniqueIdLookup

    func getOpenGroupServerIdLookup(_ serverId: UInt64, in room: String, on server: String, using transaction: YapDatabaseReadTransaction) -> OpenGroupServerIdLookup?
    func addOpenGroupServerIdLookup(_ serverId: UInt64?, tsMessageId: String?, in room: String, on server: String, using transaction: YapDatabaseReadWriteTransaction)
    func addOpenGroupServerIdLookup(_ lookup: OpenGroupServerIdLookup, using transaction: YapDatabaseReadWriteTransaction)
    func removeOpenGroupServerIdLookup(_ serverId: UInt64, in room: String, on server: String, using transaction: YapDatabaseReadWriteTransaction)
    
    // MARK: - -- Open Group Inbox Latest Message Id

    func getOpenGroupInboxLatestMessageId(for server: String) -> Int64?
    func setOpenGroupInboxLatestMessageId(for server: String, to newValue: Int64, using transaction: Any)
    func removeOpenGroupInboxLatestMessageId(for server: String, using transaction: Any)
    
    // MARK: - -- Open Group Outbox Latest Message Id

    func getOpenGroupOutboxLatestMessageId(for server: String) -> Int64?
    func setOpenGroupOutboxLatestMessageId(for server: String, to newValue: Int64, using transaction: Any)
    func removeOpenGroupOutboxLatestMessageId(for server: String, using transaction: Any)

    // MARK: - Message Handling

    func getAllMessageRequestThreads() -> [String: TSContactThread]
    func getAllMessageRequestThreads(using transaction: YapDatabaseReadTransaction) -> [String: TSContactThread]
    
    func getReceivedMessageTimestamps(using transaction: Any) -> [UInt64]
    func removeReceivedMessageTimestamps(_ timestamps: Set<UInt64>, using transaction: Any)
    func addReceivedMessageTimestamp(_ timestamp: UInt64, using transaction: Any)
    /// Returns the ID of the thread.
    func getOrCreateThread(for publicKey: String, groupPublicKey: String?, openGroupID: String?, using transaction: Any) -> String?
    /// Returns the ID of the `TSIncomingMessage` that was constructed.
    func persist(_ message: VisibleMessage, quotedMessage: TSQuotedMessage?, linkPreview: OWSLinkPreview?, groupPublicKey: String?, openGroupID: String?, using transaction: Any) -> String?
    /// Returns the IDs of the saved attachments.
    func persist(_ attachments: [VisibleMessage.Attachment], using transaction: Any) -> [String]
    /// Also touches the associated message.
    func setAttachmentState(to state: TSAttachmentPointerState, for pointer: TSAttachmentPointer, associatedWith tsIncomingMessageID: String, using transaction: Any)
    /// Also touches the associated message.
    func persist(_ stream: TSAttachmentStream, associatedWith tsIncomingMessageID: String, using transaction: Any)
    
    // MARK: - Calls
    
    func getReceivedCalls(for publicKey: String, using transaction: Any) -> Set<String>
    func setReceivedCalls(to receivedCalls: Set<String>, for publicKey: String, using transaction: Any)
}

extension Storage: SessionMessagingKitStorageProtocol, SessionSnodeKitStorageProtocol {}
