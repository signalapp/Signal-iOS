import PromiseKit

// A few notes about making changes in this file:
//
// • Don't use a database transaction if you can avoid it.
// • If you do need to use a database transaction, use a read transaction if possible.
// • For write transactions, consider making it the caller's responsibility to manage the database transaction (this helps avoid unnecessary transactions).
// • Think carefully about adding a function; there might already be one for what you need.
// • Document the expected cases in which a function will be used
// • Express those cases in tests.

/// See [Receipts, Transcripts & Typing Indicators](https://github.com/loki-project/session-protocol-docs/wiki/Receipts,-Transcripts-&-Typing-Indicators) for more information.
@objc(LKSessionMetaProtocol)
public final class SessionMetaProtocol : NSObject {

    internal static var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }

    // MARK: - Sending

    // MARK: Message Destination(s)
    @objc public static func getDestinationsForOutgoingSyncMessage() -> NSMutableSet {
        return NSMutableSet(set: [ getUserHexEncodedPublicKey() ]) // return NSMutableSet(set: MultiDeviceProtocol.getUserLinkedDevices())
    }

    @objc(getDestinationsForOutgoingGroupMessage:inThread:)
    public static func getDestinations(for outgoingGroupMessage: TSOutgoingMessage, in thread: TSThread) -> NSMutableSet {
        guard let thread = thread as? TSGroupThread else { preconditionFailure("Can't get destinations for group message in non-group thread.") }
        var result: Set<String> = []
        if thread.isPublicChat {
            storage.dbReadConnection.read { transaction in
                if let openGroup = LokiDatabaseUtilities.getPublicChat(for: thread.uniqueId!, in: transaction) {
                    result = [ openGroup.server ] // Aim the message at the open group server
                } else {
                    // Should never occur
                }
            }
        } else {
            if let groupThread = thread as? TSGroupThread, groupThread.usesSharedSenderKeys {
                let groupPublicKey = LKGroupUtilities.getDecodedGroupID(groupThread.groupModel.groupId)
                result = [ groupPublicKey ]
            } else {
                result = Set(outgoingGroupMessage.sendingRecipientIds())
                    .intersection(thread.groupModel.groupMemberIds)
                    .subtracting([ getUserHexEncodedPublicKey() ]) // .subtracting(MultiDeviceProtocol.getUserLinkedDevices())
            }
        }
        return NSMutableSet(set: result)
    }

    // MARK: Note to Self
    @objc(isThreadNoteToSelf:)
    public static func isThreadNoteToSelf(_ thread: TSThread) -> Bool {
        guard let thread = thread as? TSContactThread else { return false }
        return thread.contactIdentifier() == getUserHexEncodedPublicKey()
        /*
        var isNoteToSelf = false
        storage.dbReadConnection.read { transaction in
            isNoteToSelf = LokiDatabaseUtilities.isUserLinkedDevice(thread.contactIdentifier(), transaction: transaction)
        }
        return isNoteToSelf
         */
    }

    // MARK: Transcripts
    @objc(shouldSendTranscriptForMessage:inThread:)
    public static func shouldSendTranscript(for message: TSOutgoingMessage, in thread: TSThread) -> Bool {
        guard message.shouldSyncTranscript() else { return false }
        let isOpenGroupMessage = (thread as? TSGroupThread)?.isPublicChat == true
        let wouldSignalRequireTranscript = (AreRecipientUpdatesEnabled() || !message.hasSyncedTranscript)
        guard wouldSignalRequireTranscript && !isOpenGroupMessage else { return false }
        return false
        /*
        var usesMultiDevice = false
        storage.dbReadConnection.read { transaction in
            usesMultiDevice = !storage.getDeviceLinks(for: getUserHexEncodedPublicKey(), in: transaction).isEmpty
                || UserDefaults.standard[.masterHexEncodedPublicKey] != nil
        }
        return usesMultiDevice
         */
    }

    // MARK: Typing Indicators
    /// Invoked only if typing indicators are enabled in the settings. Provides an opportunity
    /// to avoid sending them if certain conditions are met.
    @objc(shouldSendTypingIndicatorInThread:)
    public static func shouldSendTypingIndicator(in thread: TSThread) -> Bool {
        return !thread.isGroupThread() && thread.numberOfInteractions() > 0
    }

    // MARK: Receipts
    @objc(shouldSendReceiptInThread:)
    public static func shouldSendReceipt(in thread: TSThread) -> Bool {
        return !thread.isGroupThread()
    }

    // MARK: - Receiving
    
    @objc(isErrorMessageFromBeforeRestoration:)
    public static func isErrorMessageFromBeforeRestoration(_ errorMessage: TSErrorMessage) -> Bool {
        let restorationTimeInMs = UInt64(storage.getRestorationTime() * 1000)
        return errorMessage.timestamp < restorationTimeInMs
    }

    @objc(updateDisplayNameIfNeededForPublicKey:using:transaction:)
    public static func updateDisplayNameIfNeeded(for publicKey: String, using dataMessage: SSKProtoDataMessage, in transaction: YapDatabaseReadWriteTransaction) {
        guard let profile = dataMessage.profile, let displayName = profile.displayName, !displayName.isEmpty else { return }
        let profileManager = SSKEnvironment.shared.profileManager
        profileManager.updateProfileForContact(withID: publicKey, displayName: displayName, with: transaction)
    }

    @objc(updateProfileKeyIfNeededForPublicKey:using:)
    public static func updateProfileKeyIfNeeded(for publicKey: String, using dataMessage: SSKProtoDataMessage) {
        guard dataMessage.hasProfileKey, let profileKey = dataMessage.profileKey else { return }
        guard profileKey.count == kAES256_KeyByteLength else {
            return print("[Loki] Unexpected profile key size: \(profileKey.count).")
        }
        let profilePictureURL = dataMessage.profile?.profilePicture
        let profileManager = SSKEnvironment.shared.profileManager
        profileManager.setProfileKeyData(profileKey, forRecipientId: publicKey, avatarURL: profilePictureURL)
    }
}
