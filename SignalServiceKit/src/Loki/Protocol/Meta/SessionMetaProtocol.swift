import PromiseKit

// A few notes about making changes in this file:
//
// • Don't use a database transaction if you can avoid it.
// • If you do need to use a database transaction, use a read transaction if possible.
// • Consider making it the caller's responsibility to manage the database transaction (this helps avoid nested or unnecessary transactions).
// • Think carefully about adding a function; there might already be one for what you need.
// • Document the expected cases for everything.
// • Express those cases in tests.

/// See [Receipts, Transcripts & Typing Indicators](https://github.com/loki-project/session-protocol-docs/wiki/Receipts,-Transcripts-&-Typing-Indicators) for more information.
@objc(LKSessionMetaProtocol)
public final class SessionMetaProtocol : NSObject {

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
    @objc(isMessageNoteToSelf:)
    public static func isMessageNoteToSelf(_ thread: TSThread) -> Bool {
        guard let thread = thread as? TSContactThread else { return false }
        var isNoteToSelf = false
        storage.dbReadConnection.read { transaction in
            isNoteToSelf = LokiDatabaseUtilities.isUserLinkedDevice(thread.contactIdentifier(), transaction: transaction)
        }
        return isNoteToSelf
    }

    // MARK: Transcripts
    @objc(shouldSendTranscriptForMessage:in:)
    public static func shouldSendTranscript(for message: TSOutgoingMessage, in thread: TSThread) -> Bool {
        let isOpenGroupMessage = (thread as? TSGroupThread)?.isPublicChat == true
        let wouldSignalRequireTranscript = (AreRecipientUpdatesEnabled() || !message.hasSyncedTranscript)
        return wouldSignalRequireTranscript && !isOpenGroupMessage
    }

    // MARK: Typing Indicators
    /// Invoked only if typing indicators are enabled. Provides an opportunity to not
    /// send them if certain conditions are met.
    @objc(shouldSendTypingIndicatorForThread:)
    public static func shouldSendTypingIndicator(for thread: TSThread) -> Bool {
        return thread.friendRequestStatus == .friends && !thread.isGroupThread()
    }

    // MARK: Receipts
    @objc(shouldSendReceiptForThread:)
    public static func shouldSendReceipt(for thread: TSThread) -> Bool {
        return thread.friendRequestStatus == .friends && !thread.isGroupThread()
    }

    // MARK: - Receiving
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
        // TODO: Figure out why we sometimes don't append the short ID
        if appendShortID {
            let shortID = hexEncodedPublicKey.substring(from: hexEncodedPublicKey.index(hexEncodedPublicKey.endIndex, offsetBy: -8))
            displayName = "\(rawDisplayName) (...\(shortID))"
        } else {
            displayName = rawDisplayName
        }
        guard !displayName.isEmpty else { return }
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
