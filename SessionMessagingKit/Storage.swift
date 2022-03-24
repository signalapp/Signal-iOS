import PromiseKit
import Sodium

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
    func getAllContacts() -> Set<Contact>
    func getAllContacts(with transaction: YapDatabaseReadTransaction) -> Set<Contact>

    // MARK: - Closed Groups

    func getUserClosedGroupPublicKeys() -> Set<String>
    func getZombieMembers(for groupPublicKey: String) -> Set<String>
    func setZombieMembers(for groupPublicKey: String, to zombies: Set<String>, using transaction: Any)
    func isClosedGroup(_ publicKey: String) -> Bool

    // MARK: - Jobs

    func persist(_ job: Job, using transaction: Any)
    func markJobAsSucceeded(_ job: Job, using transaction: Any)
    func markJobAsFailed(_ job: Job, using transaction: Any)
    func getAllPendingJobs(of type: Job.Type) -> [Job]
    func getAttachmentUploadJob(for attachmentID: String) -> AttachmentUploadJob?
    func getMessageSendJob(for messageSendJobID: String) -> MessageSendJob?
    func resumeMessageSendJobIfNeeded(_ messageSendJobID: String)
    func isJobCanceled(_ job: Job) -> Bool

    // MARK: - Authorization

    func getAuthToken(for room: String, on server: String) -> String?
    func setAuthToken(for room: String, on server: String, to newValue: String, using transaction: Any)
    func removeAuthToken(for room: String, on server: String, using transaction: Any)

    // MARK: - Open Groups

    func getAllV2OpenGroups() -> [String:OpenGroupV2]
    func getV2OpenGroup(for threadID: String) -> OpenGroupV2?
    func v2GetThreadID(for v2OpenGroupID: String) -> String?
    func updateMessageIDCollectionByPruningMessagesWithIDs(_ messageIDs: Set<String>, using transaction: Any)
    
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

    // MARK: - Open Group Metadata

    func setUserCount(to newValue: UInt64, forV2OpenGroupWithID openGroupID: String, using transaction: Any)

    // MARK: - Message Handling

    func getReceivedMessageTimestamps(using transaction: Any) -> [UInt64]
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
}
