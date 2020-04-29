import PromiseKit

// A few notes about making changes in this file:
//
// • Don't use a database transaction if you can avoid it.
// • If you do need to use a database transaction, use a read transaction if possible.
// • Consider making it the caller's responsibility to manage the database transaction (this helps avoid nested or unnecessary transactions).
// • Think carefully about adding a function; there might already be one for what you need.
// • Document the expected cases for everything.
// • Express those cases in tests.

@objc(LKSessionProtocol)
public final class SessionProtocol : NSObject {

    internal static var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }

    // MARK: Initialization
    private override init() { }

    // MARK: - Sending

    // MARK: Message Destination
    @objc(getDestinationsForOutgoingSyncMessage)
    public static func objc_getDestinationsForOutgoingSyncMessage() -> NSMutableSet {
        return NSMutableSet(set: getDestinationsForOutgoingSyncMessage())
    }

    public static func getDestinationsForOutgoingSyncMessage() -> Set<String> {
        var result: Set<String> = []
        storage.dbReadConnection.read { transaction in
            // Aim the message at all linked devices, including this one
            // TODO: Should we exclude the current device?
            result = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: getUserHexEncodedPublicKey(), in: transaction)
        }
        return result
    }

    @objc(getDestinationsForOutgoingGroupMessage:inThread:)
    public static func objc_getDestinations(for outgoingGroupMessage: TSOutgoingMessage, in thread: TSThread) -> NSMutableSet {
        return NSMutableSet(set: getDestinations(for: outgoingGroupMessage, in: thread))
    }

    public static func getDestinations(for outgoingGroupMessage: TSOutgoingMessage, in thread: TSThread) -> Set<String> {
        guard let thread = thread as? TSGroupThread else { preconditionFailure("Can't get destinations for group message in non-group thread.") }
        var result: Set<String> = []
        if thread.isPublicChat {
            storage.dbReadConnection.read { transaction in
                if let openGroup = LokiDatabaseUtilities.getPublicChat(for: thread.uniqueId!, in: transaction) {
                    result = [ openGroup.server ] // Aim the message at the open group server
                } else {
                    // TODO: Handle?
                }
            }
        } else {
            result = Set(outgoingGroupMessage.sendingRecipientIds()).intersection(thread.groupModel.groupMemberIds) // This is what Signal does
        }
        return result
    }

    // MARK: Note to Self
    // BEHAVIOR NOTE: OWSMessageSender.sendMessageToService:senderCertificate:success:failure: aborts early and just sends
    // a sync message instead if the message it's supposed to send is considered a note to self (INCLUDING linked devices).
    // BEHAVIOR NOTE: OWSMessageSender.sendMessage: aborts early and does nothing if the message is target at
    // the current user (EXCLUDING linked devices).
    // BEHAVIOR NOTE: OWSMessageSender.handleMessageSentLocally:success:failure: doesn't send a sync transcript if the message
    // that was sent is considered a note to self (INCLUDING linked devices) but it does then mark the message as read.

    // TODO: Check that the behaviors described above make sense

    @objc(isMessageNoteToSelf:)
    public static func isMessageNoteToSelf(_ thread: TSThread) -> Bool {
        guard let thread = thread as? TSContactThread else { return false }
        var isNoteToSelf = false
        storage.dbReadConnection.read { transaction in
            isNoteToSelf = LokiDatabaseUtilities.isUserLinkedDevice(thread.contactIdentifier(), transaction: transaction)
        }
        return isNoteToSelf
    }

    @objc(isMessageNoteToSelf:inThread:)
    public static func isMessageNoteToSelf(_ message: TSOutgoingMessage, in thread: TSThread) -> Bool {
        guard let thread = thread as? TSContactThread, !(message is OWSOutgoingSyncMessage) && !(message is DeviceLinkMessage) else { return false }
        var isNoteToSelf = false
        storage.dbReadConnection.read { transaction in
            isNoteToSelf = LokiDatabaseUtilities.isUserLinkedDevice(thread.contactIdentifier(), transaction: transaction)
        }
        return isNoteToSelf
    }

    // MARK: Transcripts
    @objc(shouldSendTranscriptForMessage:in:)
    public static func shouldSendTranscript(for message: TSOutgoingMessage, in thread: TSThread) -> Bool {
        let isNoteToSelf = isMessageNoteToSelf(message, in: thread)
        let isOpenGroupMessage = (thread as? TSGroupThread)?.isPublicChat == true
        let wouldSignalRequireTranscript = (AreRecipientUpdatesEnabled() || !message.hasSyncedTranscript)
        return wouldSignalRequireTranscript && !isNoteToSelf && !isOpenGroupMessage && !(message is DeviceLinkMessage)
    }

    // MARK: Typing Indicators
    /// Invoked only if typing indicators are enabled. Provides an opportunity to not
    /// send them if certain conditions are met.
    @objc(shouldSendTypingIndicatorForThread:)
    public static func shouldSendTypingIndicator(for thread: TSThread) -> Bool {
        return !thread.isGroupThread() && !isMessageNoteToSelf(thread)
    }

    // MARK: Receipts
    // Used from OWSReadReceiptManager
    @objc(shouldSendReadReceiptForThread:)
    public static func shouldSendReadReceipt(for thread: TSThread) -> Bool {
        return !isMessageNoteToSelf(thread) && !thread.isGroupThread()
    }

    // TODO: Not sure how these two relate
    // EDIT: I think the one below is used to block delivery receipts. That means that
    // right now we do send delivery receipts in note to self, but not read receipts. Other than that their behavior should
    // be identical. Should we just not send any kind of receipt in note to self?

    // Used from OWSOutgoingReceiptManager
    @objc(shouldSendReceiptForThread:)
    public static func shouldSendReceipt(for thread: TSThread) -> Bool {
        return thread.friendRequestStatus == .friends && !thread.isGroupThread()
    }

    // MARK: - Receiving

    // When a message comes in, OWSMessageManager does things in this order:
    // 1. Checks if the message is a friend request from before restoration and ignores it if so
    // 2. Handles friend request acceptance if needed
    // 3. Checks if the message is a duplicate sync message and ignores it if so
    // 4. Handles pre keys if needed (this also might trigger a session reset)
    // 5. Updates P2P info if the message is a P2P address message
    // 6. Handle device linking requests or authorizations if needed (it now doesn't continue along the normal message handling path)
    // - If the message is a data message and has the session request flag set, processing stops here
    // - If the message is a data message and has the session restore flag set, processing stops here
    // 7. If the message got to this point, and it has an updated profile key attached, it'll now handle the profile key
    // - If the message is a closed group message, it'll now check if it needs to be ignored
    // ...

    // MARK: - Decryption
    @objc(shouldSkipMessageDecryptResult:)
    public static func shouldSkipMessageDecryptResult(_ result: OWSMessageDecryptResult) -> Bool {
        // Called from OWSMessageReceiver to prevent messages from even being added to the processing queue
        // TODO: Why is this function needed at all?
        return result.source == getUserHexEncodedPublicKey() // This intentionally doesn't take into account multi device
    }

    // MARK: Profile Updating
    @objc(updateDisplayNameIfNeededForHexEncodedPublicKey:using:appendingShortID:in:)
    public static func updateDisplayNameIfNeeded(for hexEncodedPublicKey: String, using dataMessage: SSKProtoDataMessage, appendingShortID appendShortID: Bool, in transaction: YapDatabaseReadWriteTransaction) {
        guard let profile = dataMessage.profile, let rawDisplayName = profile.displayName else { return }
        let displayName: String
        if appendShortID {
            let shortID = hexEncodedPublicKey.substring(from: hexEncodedPublicKey.index(hexEncodedPublicKey.endIndex, offsetBy: -8))
            displayName = "\(rawDisplayName) (...\(shortID))"
        } else {
            displayName = rawDisplayName
        }
        let profileManager = SSKEnvironment.shared.profileManager
        profileManager.updateProfileForContact(withID: hexEncodedPublicKey, displayName: displayName, with: transaction)
    }

    @objc(updateProfileKeyIfNeededForHexEncodedPublicKey:using:)
    public static func updateProfileKeyIfNeeded(for hexEncodedPublicKey: String, using dataMessage: SSKProtoDataMessage) {
        guard dataMessage.hasProfileKey, let profileKey = dataMessage.profileKey else { return }
        let profilePictureURL = dataMessage.profile?.profilePicture
        guard profileKey.count == kAES256_KeyByteLength else {
            print("[Loki] Unexpected profile key size: \(profileKey.count).")
            return
        }
        let profileManager = SSKEnvironment.shared.profileManager
        // This dispatches async on the main queue internally where it starts a new write transaction
        profileManager.setProfileKeyData(profileKey, forRecipientId: hexEncodedPublicKey, avatarURL: profilePictureURL)
    }

    // MARK: P2P
    @objc(handleP2PAddressMessageIfNeeded:wrappedIn:)
    public static func handleP2PAddressMessageIfNeeded(_ protoContent: SSKProtoContent, wrappedIn envelope: SSKProtoEnvelope) {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let addressMessage = protoContent.lokiAddressMessage, let address = addressMessage.ptpAddress else { return }
        let portAsUInt32 = addressMessage.ptpPort
        guard portAsUInt32 != 0, portAsUInt32 < UInt16.max else { return }
        let port = UInt16(portAsUInt32)
        LokiP2PAPI.didReceiveLokiAddressMessage(forContact: hexEncodedPublicKey, address: address, port: port, receivedThroughP2P: envelope.isPtpMessage)
    }
}
