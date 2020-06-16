import PromiseKit

// A few notes about making changes in this file:
//
// • Don't use a database transaction if you can avoid it.
// • If you do need to use a database transaction, use a read transaction if possible.
// • Consider making it the caller's responsibility to manage the database transaction (this helps avoid nested or unnecessary transactions).
// • Think carefully about adding a function; there might already be one for what you need.
// • Document the expected cases for everything.
// • Express those cases in tests.

/// See [The Session Friend Request Protocol](https://github.com/loki-project/session-protocol-docs/wiki/Friend-Requests) for more information.
@objc(LKFriendRequestProtocol)
public final class FriendRequestProtocol : NSObject {

    internal static var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }

    // MARK: - Friend Request UI Status
    @objc(LKFriendRequestUIStatus)
    public enum FriendRequestUIStatus : Int {
        case friends, received, sent, none, expired
    }

    // MARK: - General
    @objc(isFriendsWithAnyLinkedDeviceOfHexEncodedPublicKey:)
    public static func isFriendsWithAnyLinkedDevice(of hexEncodedPublicKey: String) -> Bool {
        var result = false
        storage.dbReadConnection.read { transaction in
            let linkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: hexEncodedPublicKey, in: transaction)
            let friendRequestStatuses = linkedDevices.map {
                storage.getFriendRequestStatus(for: $0, transaction: transaction)
            }
            result = friendRequestStatuses.contains { $0 == .friends }
        }
        return result
    }

    @objc(shouldInputBarBeEnabledForThread:)
    public static func shouldInputBarBeEnabled(for thread: TSThread) -> Bool {
        // Friend requests have nothing to do with groups, so if this isn't a contact thread the input bar should be enabled
        guard let thread = thread as? TSContactThread else { return true }
        // If this is a note to self the input bar should be enabled
        if thread.isNoteToSelf() { return true }
        // Gather friend request statuses
        let contactID = thread.contactIdentifier()
        var linkedDeviceFriendRequestStatuses: [LKFriendRequestStatus] = []
        storage.dbReadConnection.read { transaction in
            let linkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: contactID, in: transaction)
            linkedDeviceFriendRequestStatuses = linkedDevices.map {
                storage.getFriendRequestStatus(for: $0, transaction: transaction)
            }
        }
        // If the current user is friends with any of the other user's devices, the input bar should be enabled
        if linkedDeviceFriendRequestStatuses.contains(where: { $0 == .friends }) { return true }
        // If no friend request has been sent, the input bar should be enabled
        if linkedDeviceFriendRequestStatuses.allSatisfy({ $0 == .none || $0 == .requestExpired }) { return true }
        // There must be a pending friend request
        return false
    }

    @objc(shouldAttachmentButtonBeEnabledForThread:)
    public static func shouldAttachmentButtonBeEnabled(for thread: TSThread) -> Bool {
        // Friend requests have nothing to do with groups, so if this isn't a contact thread the attachment button should be enabled
        guard let thread = thread as? TSContactThread else { return true }
        // If this is a note to self, the attachment button should be enabled
        if thread.isNoteToSelf() { return true }
        /// Gather friend request statuses
        let contactID = thread.contactIdentifier()
        var linkedDeviceFriendRequestStatuses: [LKFriendRequestStatus] = []
        storage.dbReadConnection.read { transaction in
            let linkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: contactID, in: transaction)
            linkedDeviceFriendRequestStatuses = linkedDevices.map {
                storage.getFriendRequestStatus(for: $0, transaction: transaction)
            }
        }
        // If the current user is friends with any of the other user's devices, the attachment button should be enabled
        if linkedDeviceFriendRequestStatuses.contains(where: { $0 == .friends }) { return true }
        // Otherwise don't allow attachments
        return false
    }

    @objc(getFriendRequestUIStatusForThread:)
    public static func getFriendRequestUIStatus(for thread: TSThread) -> FriendRequestUIStatus {
        // Friend requests have nothing to do with groups
        guard let thread = thread as? TSContactThread else { return .none }
        // If this is a note to self then we don't want to show the friend request UI
        guard !thread.isNoteToSelf() else { return .none }
        // Gather friend request statuses for all linked devices
        var friendRequestStatuses: [LKFriendRequestStatus] = []
        storage.dbReadConnection.read { transaction in
            let linkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: thread.contactIdentifier(), in: transaction)
            friendRequestStatuses = linkedDevices.map {
                storage.getFriendRequestStatus(for: $0, transaction: transaction)
            }
        }
        // Return
        if friendRequestStatuses.contains(where: { $0 == .friends }) { return .friends }
        if friendRequestStatuses.contains(where: { $0 == .requestReceived }) { return .received }
        if friendRequestStatuses.contains(where: { $0 == .requestSent || $0 == .requestSending }) { return .sent }
        if friendRequestStatuses.contains(where: { $0 == .requestExpired }) { return .expired }
        return .none
    }

    // MARK: - Sending
    @objc(acceptFriendRequestFromHexEncodedPublicKey:using:)
    public static func acceptFriendRequest(from hexEncodedPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        guard ECKeyPair.isValidHexEncodedPublicKey(candidate: hexEncodedPublicKey) else {
            print("[Loki] Invalid Session ID: \(hexEncodedPublicKey).")
            return
        }
        let userHexEncodedPublicKey = getUserHexEncodedPublicKey()
        let userLinkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: userHexEncodedPublicKey, in: transaction)
        // Accept all outstanding friend requests associated with this user and try to establish sessions with the
        // subset of their devices that haven't sent a friend request.
        let linkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: hexEncodedPublicKey, in: transaction)
        for device in linkedDevices {
            let friendRequestStatus = storage.getFriendRequestStatus(for: device, transaction: transaction)
            if friendRequestStatus == .requestReceived {
                storage.setFriendRequestStatus(.friends, for: device, transaction: transaction)
                sendFriendRequestAcceptanceMessage(to: device, using: transaction)
                // Send a contact sync message if needed
                guard !userLinkedDevices.contains(hexEncodedPublicKey) else { return }
                let masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: hexEncodedPublicKey, in: transaction) ?? hexEncodedPublicKey
                let syncManager = SSKEnvironment.shared.syncManager
                syncManager.syncContact(masterHexEncodedPublicKey, transaction: transaction)
            } else if friendRequestStatus == .requestSent {
                // We sent a friend request to this device before, how can we be sure that it hasn't expired?
            } else if !userLinkedDevices.contains(device) && (friendRequestStatus == .none || friendRequestStatus == .requestExpired) {
                // TODO: We should track these so that we can expire them and resend if needed
                MultiDeviceProtocol.getAutoGeneratedMultiDeviceFRMessageSend(for: device, in: transaction)
                .done(on: OWSDispatch.sendingQueue()) { autoGeneratedFRMessageSend in
                    let messageSender = SSKEnvironment.shared.messageSender
                    messageSender.sendMessage(autoGeneratedFRMessageSend)
                }
            }
        }
    }

    @objc(sendFriendRequestAcceptanceMessageToHexEncodedPublicKey:using:)
    public static func sendFriendRequestAcceptanceMessage(to hexEncodedPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        guard ECKeyPair.isValidHexEncodedPublicKey(candidate: hexEncodedPublicKey) else {
            print("[Loki] Invalid Session ID: \(hexEncodedPublicKey).")
            return
        }
        let thread = TSContactThread.getOrCreateThread(withContactId: hexEncodedPublicKey, transaction: transaction)
        let ephemeralMessage = EphemeralMessage(thread: thread)
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
        messageSenderJobQueue.add(message: ephemeralMessage, transaction: transaction)
    }

    @objc(declineFriendRequestFromHexEncodedPublicKey:using:)
    public static func declineFriendRequest(from hexEncodedPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        guard ECKeyPair.isValidHexEncodedPublicKey(candidate: hexEncodedPublicKey) else {
            print("[Loki] Invalid Session ID: \(hexEncodedPublicKey).")
            return
        }
        let linkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: hexEncodedPublicKey, in: transaction)
        for device in linkedDevices {
            let friendRequestStatus = storage.getFriendRequestStatus(for: device, transaction: transaction)
            // We only want to decline incoming requests
            if friendRequestStatus == .requestReceived {
                // Delete the pre key bundle for the given contact. This ensures that if we send a
                // new message after this, it restarts the friend request process from scratch.
                storage.removePreKeyBundle(forContact: device, transaction: transaction)
                storage.setFriendRequestStatus(.none, for: device, transaction: transaction)
            }
        }
    }

    @objc(shouldUpdateFriendRequestStatusFromMessage:)
    public static func shouldUpdateFriendRequestStatus(from message: TSOutgoingMessage) -> Bool {
        // The order of these checks matters
        if message.thread.isGroupThread() { return false }
        if message.thread.contactIdentifier() == getUserHexEncodedPublicKey() { return false }
        if (message as? DeviceLinkMessage)?.kind == .request { return true }
        if message is SessionRequestMessage { return false }
        return message is FriendRequestMessage
    }

    @objc(setFriendRequestStatusToSendingIfNeededForHexEncodedPublicKey:transaction:)
    public static func setFriendRequestStatusToSendingIfNeeded(for hexEncodedPublicKey: String, transaction: YapDatabaseReadWriteTransaction) {
        let friendRequestStatus = storage.getFriendRequestStatus(for: hexEncodedPublicKey, transaction: transaction)
        guard friendRequestStatus == .none || friendRequestStatus == .requestExpired else { return }
        storage.setFriendRequestStatus(.requestSending, for: hexEncodedPublicKey, transaction: transaction)
    }

    @objc(setFriendRequestStatusToSentIfNeededForHexEncodedPublicKey:transaction:)
    public static func setFriendRequestStatusToSentIfNeeded(for hexEncodedPublicKey: String, transaction: YapDatabaseReadWriteTransaction) {
        let friendRequestStatus = storage.getFriendRequestStatus(for: hexEncodedPublicKey, transaction: transaction)
        guard friendRequestStatus == .none || friendRequestStatus == .requestExpired || friendRequestStatus == .requestSending else { return }
        storage.setFriendRequestStatus(.requestSent, for: hexEncodedPublicKey, transaction: transaction)
    }

    @objc(setFriendRequestStatusToFailedIfNeededForHexEncodedPublicKey:transaction:)
    public static func setFriendRequestStatusToFailedIfNeeded(for hexEncodedPublicKey: String, transaction: YapDatabaseReadWriteTransaction) {
        let friendRequestStatus = storage.getFriendRequestStatus(for: hexEncodedPublicKey, transaction: transaction)
        guard friendRequestStatus == .requestSending else { return }
        storage.setFriendRequestStatus(.none, for: hexEncodedPublicKey, transaction: transaction)
    }

    // MARK: - Receiving
    @objc(isFriendRequestFromBeforeRestoration:)
    public static func isFriendRequestFromBeforeRestoration(_ envelope: SSKProtoEnvelope) -> Bool {
        // The envelope type is set during UD decryption
        let restorationTimeInMs = UInt64(storage.getRestorationTime() * 1000)
        return (envelope.type == .friendRequest && envelope.timestamp < restorationTimeInMs)
    }

    @objc(canFriendRequestBeAutoAcceptedForHexEncodedPublicKey:using:)
    public static func canFriendRequestBeAutoAccepted(for hexEncodedPublicKey: String, using transaction: YapDatabaseReadTransaction) -> Bool {
        if storage.getFriendRequestStatus(for: hexEncodedPublicKey, transaction: transaction) == .requestSent {
            // This can happen if Alice sent Bob a friend request, Bob declined, but then Bob changed his
            // mind and sent a friend request to Alice. In this case we want Alice to auto-accept the request
            // and send a friend request accepted message back to Bob. We don't check that sending the
            // friend request accepted message succeeds. Even if it doesn't, the thread's current friend
            // request status will be set to LKThreadFriendRequestStatusFriends for Alice making it possible
            // for Alice to send messages to Bob. When Bob receives a message, his thread's friend request status
            // will then be set to LKThreadFriendRequestStatusFriends. If we do check for a successful send
            // before updating Alice's thread's friend request status to LKThreadFriendRequestStatusFriends,
            // we can end up in a deadlock where both users' threads' friend request statuses are
            // LKThreadFriendRequestStatusRequestSent.
            return true
        }
        // Auto-accept any friend requests from the user's own linked devices
        let userLinkedDeviceHexEncodedPublicKeys = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: getUserHexEncodedPublicKey(), in: transaction)
        if userLinkedDeviceHexEncodedPublicKeys.contains(hexEncodedPublicKey) { return true }
        // Auto-accept if the user is friends with any of the sender's linked devices.
        let senderLinkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: hexEncodedPublicKey, in: transaction)
        if senderLinkedDevices.contains(where: {
            storage.getFriendRequestStatus(for: $0, transaction: transaction) == .friends
        }) {
            return true
        }
        // We can't auto-accept
        return false
    }

    @objc(handleFriendRequestAcceptanceIfNeeded:in:)
    public static func handleFriendRequestAcceptanceIfNeeded(_ envelope: SSKProtoEnvelope, in transaction: YapDatabaseReadWriteTransaction) {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        // The envelope type is set during UD decryption.
        guard !envelope.isGroupChatMessage && envelope.type != .friendRequest else { return }
        // If we get an envelope that isn't a friend request, then we can infer that we had to use
        // Signal cipher decryption and thus that we have a session with the other person.
        let friendRequestStatus = storage.getFriendRequestStatus(for: hexEncodedPublicKey, transaction: transaction);
        // We shouldn't be able to skip from none to friends
        guard friendRequestStatus == .requestSending || friendRequestStatus == .requestSent
            || friendRequestStatus == .requestReceived else { return }
        // Become friends
        storage.setFriendRequestStatus(.friends, for: hexEncodedPublicKey, transaction: transaction)
        // Send a contact sync message if needed
        guard !LokiDatabaseUtilities.isUserLinkedDevice(hexEncodedPublicKey, transaction: transaction) else { return }
        let masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: hexEncodedPublicKey, in: transaction) ?? hexEncodedPublicKey
        let syncManager = SSKEnvironment.shared.syncManager
        syncManager.syncContact(masterHexEncodedPublicKey, transaction: transaction)
    }

    @objc(handleFriendRequestMessageIfNeededFromEnvelope:using:)
    public static func handleFriendRequestMessageIfNeeded(from envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        guard !envelope.isGroupChatMessage else {
            print("[Loki] Ignoring friend request in group chat.")
            return
        }
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        // The envelope type is set during UD decryption.
        guard envelope.type == .friendRequest else {
            print("[Loki] Ignoring friend request logic for non friend request type envelope.")
            return
        }
        if canFriendRequestBeAutoAccepted(for: hexEncodedPublicKey, using: transaction) {
            storage.setFriendRequestStatus(.friends, for: hexEncodedPublicKey, transaction: transaction)
            sendFriendRequestAcceptanceMessage(to: hexEncodedPublicKey, using: transaction)
        } else if storage.getFriendRequestStatus(for: hexEncodedPublicKey, transaction: transaction) != .friends {
            // Checking that the sender of the message isn't already a friend is necessary because otherwise
            // the following situation can occur: Alice and Bob are friends. Bob loses his database and his
            // friend request status is reset to LKThreadFriendRequestStatusNone. Bob now sends Alice a friend
            // request. Alice's thread's friend request status is reset to
            // LKThreadFriendRequestStatusRequestReceived.
            storage.setFriendRequestStatus(.requestReceived, for: hexEncodedPublicKey, transaction: transaction)
        }
    }
}
