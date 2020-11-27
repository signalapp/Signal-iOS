import SessionProtocolKit

public protocol SessionMessagingKitStorageProtocol {

    // MARK: - Shared

    func with(_ work: @escaping (Any) -> Void)
    func withAsync(_ work: @escaping (Any) -> Void, completion: @escaping () -> Void)

    // MARK: - General

    func getUserPublicKey() -> String?
    func getUserKeyPair() -> ECKeyPair?
    func getUserDisplayName() -> String?
    func getUserProfileKey() -> Data?
    func getUserProfilePictureURL() -> String?

    // MARK: - Signal Protocol

    func getOrGenerateRegistrationID(using transaction: Any) -> UInt32
    func getSenderCertificate(for publicKey: String) -> SMKSenderCertificate

    // MARK: - Shared Sender Keys

    func getClosedGroupPrivateKey(for publicKey: String) -> String?
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

    func getAuthToken(for server: String) -> String?
    func setAuthToken(for server: String, to newValue: String, using transaction: Any)
    func removeAuthToken(for server: String, using transaction: Any)

    // MARK: - Open Groups
    
    func getOpenGroup(for threadID: String) -> OpenGroup?
    
    // MARK: - Open Group Public Keys

    func getOpenGroupPublicKey(for server: String) -> String?
    func setOpenGroupPublicKey(for server: String, to newValue: String, using transaction: Any)

    // MARK: - Last Message Server ID
    func getLastMessageServerID(for group: UInt64, on server: String) -> UInt64?
    func setLastMessageServerID(for group: UInt64, on server: String, to newValue: UInt64, using transaction: Any)
    func removeLastMessageServerID(for group: UInt64, on server: String, using transaction: Any)

    // MARK: - Last Deletion Server ID

    func getLastDeletionServerID(for group: UInt64, on server: String) -> UInt64?
    func setLastDeletionServerID(for group: UInt64, on server: String, to newValue: UInt64, using transaction: Any)
    func removeLastDeletionServerID(for group: UInt64, on server: String, using transaction: Any)

    // MARK: - Open Group Metadata

    func setUserCount(to newValue: Int, forOpenGroupWithID openGroupID: String, using transaction: Any)
    func getIDForMessage(withServerID serverID: UInt64) -> UInt64?
    func setOpenGroupDisplayName(to displayName: String, for publicKey: String, on channel: UInt64, server: String, using transaction: Any)
    func setLastProfilePictureUploadDate(_ date: Date) // Stored in user defaults so no transaction is needed

    // MARK: - Message Handling

    func getReceivedMessageTimestamps(using transaction: Any) -> [UInt64]
    func addReceivedMessageTimestamp(_ timestamp: UInt64, using transaction: Any)
    /// Returns the ID of the thread the message was stored under along with the ID of the `TSIncomingMessage` that was constructed.
    func persist(_ message: VisibleMessage, groupPublicKey: String?, using transaction: Any) -> (String, String)?
    /// Returns the IDs of the saved attachments.
    func persist(_ attachments: [VisibleMessage.Attachment], using transaction: Any) -> [String]
    /// Also touches the associated message.
    func setAttachmentState(to state: TSAttachmentPointerState, for pointer: TSAttachmentPointer, associatedWith tsIncomingMessageID: String, using transaction: Any)
    /// Also touches the associated message.
    func persist(_ stream: TSAttachmentStream, associatedWith tsIncomingMessageID: String, using transaction: Any)
}
