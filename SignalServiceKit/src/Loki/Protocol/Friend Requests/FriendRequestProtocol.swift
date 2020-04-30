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

    // Mark: - Status
    private static func isPendingFriendRequest(_ status: LKFriendRequestStatus) -> Bool {
        return status == .requestSending || status == .requestSent || status == .requestReceived
    }

    // MARK: - General
    @objc(shouldInputBarBeEnabledForThread:)
    public static func shouldInputBarBeEnabled(for thread: TSThread) -> Bool {
        // Friend requests have nothing to do with groups, so if this isn't a contact thread the input bar should be enabled
        guard let thread = thread as? TSContactThread else { return true }
        // If this is a note to self, the input bar should be enabled
        if SessionProtocol.isMessageNoteToSelf(thread) { return true }
        let contactID = thread.contactIdentifier()
        var friendRequestStatuses: [LKFriendRequestStatus] = []
        storage.dbReadConnection.read { transaction in
            let linkedDeviceThreads = LokiDatabaseUtilities.getLinkedDeviceThreads(for: contactID, in: transaction)
            friendRequestStatuses = linkedDeviceThreads.map { device in
                return storage.getFriendRequestStatus(for: device.contactIdentifier(), transaction: transaction)
            }
        }
        // If the current user is friends with any of the other user's devices, the input bar should be enabled
        if friendRequestStatuses.contains(where: { $0 == .friends }) { return true }
        // If no friend request has been sent, the input bar should be enabled
        if friendRequestStatuses.allSatisfy({ $0 == .none || $0 == .requestExpired }) { return true }
        // There must be a pending friend request
        return false
    }

    @objc(shouldAttachmentButtonBeEnabledForThread:)
    public static func shouldAttachmentButtonBeEnabled(for thread: TSThread) -> Bool {
        // Friend requests have nothing to do with groups, so if this isn't a contact thread the attachment button should be enabled
        guard let thread = thread as? TSContactThread else { return true }
        // If this is a note to self, the attachment button should be enabled
        if SessionProtocol.isMessageNoteToSelf(thread) { return true }
        let contactID = thread.contactIdentifier()
        var friendRequestStatuses: [LKFriendRequestStatus] = []
        storage.dbReadConnection.read { transaction in
            let linkedDeviceThreads = LokiDatabaseUtilities.getLinkedDeviceThreads(for: contactID, in: transaction)
            friendRequestStatuses = linkedDeviceThreads.map { thread in
                storage.getFriendRequestStatus(for: thread.contactIdentifier(), transaction: transaction)
            }
        }
        // If the current user is friends with any of the other user's devices, the attachment button should be enabled
        if friendRequestStatuses.contains(where: { $0 == .friends }) { return true }
        // Otherwise don't allow attachments at all
        return false
    }

    // MARK: - Sending
    @objc(acceptFriendRequestFromHexEncodedPublicKey:using:)
    public static func acceptFriendRequest(from hexEncodedPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        // Accept all outstanding friend requests associated with this user and try to establish sessions with the
        // subset of their devices that haven't sent a friend request.
         guard ECKeyPair.isValidHexEncodedPublicKey(candidate: hexEncodedPublicKey) else {
             assertionFailure("Invalid session ID \(hexEncodedPublicKey)")
             return;
         }

        let linkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: hexEncodedPublicKey, in: transaction)
        for device in linkedDevices {
            let friendRequestStatus = storage.getFriendRequestStatus(for: device, transaction: transaction)
            if friendRequestStatus == .requestReceived {
                storage.setFriendRequestStatus(.friends, for: device, transaction: transaction)
                sendFriendRequestAcceptanceMessage(to: device, using: transaction)
            } else if friendRequestStatus == .requestSent {
                // We sent a friend request to this device before, how can we be sure that it hasn't expired?
            } else if friendRequestStatus == .none || friendRequestStatus == .requestExpired {
                // TODO: Need to track these so that we can expire them and resend incase the other user wasn't online after we sent
                let autoGeneratedFRMessageSend = MultiDeviceProtocol.getAutoGeneratedMultiDeviceFRMessageSend(for: device, in: transaction)
                OWSDispatch.sendingQueue().async {
                    let messageSender = SSKEnvironment.shared.messageSender
                    messageSender.sendMessage(autoGeneratedFRMessageSend)
                }
            }
        }
    }

    @objc(sendFriendRequestAcceptanceMessageToHexEncodedPublicKey:using:)
    public static func sendFriendRequestAcceptanceMessage(to hexEncodedPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        guard ECKeyPair.isValidHexEncodedPublicKey(candidate: hexEncodedPublicKey) else {
            assertionFailure("Invalid session ID \(hexEncodedPublicKey)")
            return;
        }

        // TODO: Should we create the threads here??
        guard let thread = TSContactThread.getWithContactId(hexEncodedPublicKey, transaction: transaction) else {
            print("[Loki] Not going to send friend request acceptance message because thread does not exist for \(hexEncodedPublicKey)")
            return
        }

        let ephemeralMessage = EphemeralMessage(in: thread)
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
        messageSenderJobQueue.add(message: ephemeralMessage, transaction: transaction)
    }

    @objc(declineFriendRequestFromHexEncodedPublicKey:using:)
    public static func declineFriendRequest(from hexEncodedPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        guard ECKeyPair.isValidHexEncodedPublicKey(candidate: hexEncodedPublicKey) else {
            assertionFailure("Invalid session ID \(hexEncodedPublicKey)")
            return;
        }

        let linkedDevices = LokiDatabaseUtilities.getLinkedDeviceHexEncodedPublicKeys(for: hexEncodedPublicKey, in: transaction)
        for device in linkedDevices {
            let friendRequestStatus = storage.getFriendRequestStatus(for: device, transaction: transaction)
            assert(friendRequestStatus != .friends, "Invalid state transition. Cannot decline a friend request from a device we're already friends with. hexEncodedPublicKey: \(device)")
            // We only want to decline any incoming requests
            if (friendRequestStatus == .requestReceived) {
                // Delete the pre key bundle for the given contact. This ensures that if we send a
                // new message after this, it restarts the friend request process from scratch.
                storage.removePreKeyBundle(forContact: device, transaction: transaction)
                storage.setFriendRequestStatus(.none, for: device, transaction: transaction)
            }
        }
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
        if senderLinkedDevices.contains(where: { storage.getFriendRequestStatus(for: $0, transaction: transaction) == .friends }) {
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
        let thread = TSContactThread.getOrCreateThread(withContactId: hexEncodedPublicKey, transaction: transaction)
        let friendRequestStatus = storage.getFriendRequestStatus(for: hexEncodedPublicKey, transaction: transaction);
        // We shouldn't be able to skip from none to friends
        guard friendRequestStatus != .none else { return }
        // Become friends
        storage.setFriendRequestStatus(.friends, for: hexEncodedPublicKey, transaction: transaction)
        if let existingFriendRequestMessage = thread.getLastInteraction(with: transaction) as? TSOutgoingMessage,
            existingFriendRequestMessage.isFriendRequest {
            existingFriendRequestMessage.saveFriendRequestStatus(.accepted, with: transaction)
        }
        /*
        // Send our P2P details
        if let addressMessage = LokiP2PAPI.onlineBroadcastMessage(forThread: thread) {
            let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
            messageSenderJobQueue.add(message: addressMessage, transaction: transaction)
        }
         */
    }

    @objc(handleFriendRequestMessageIfNeeded:associatedWith:wrappedIn:in:using:)
    public static func handleFriendRequestMessageIfNeeded(_ dataMessage: SSKProtoDataMessage, associatedWith message: TSIncomingMessage, wrappedIn envelope: SSKProtoEnvelope, in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) {
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
            var existingFriendRequestMessage: TSOutgoingMessage?
            thread.enumerateInteractions(with: transaction) { interaction, _ in
                if let outgoingMessage = interaction as? TSOutgoingMessage, outgoingMessage.isFriendRequest {
                    existingFriendRequestMessage = outgoingMessage
                }
            }
            if let existingFriendRequestMessage = existingFriendRequestMessage {
                existingFriendRequestMessage.saveFriendRequestStatus(.accepted, with: transaction)
            }
            sendFriendRequestAcceptanceMessage(to: hexEncodedPublicKey, using: transaction)
        } else if storage.getFriendRequestStatus(for: hexEncodedPublicKey, transaction: transaction) != .friends {
            // Checking that the sender of the message isn't already a friend is necessary because otherwise
            // the following situation can occur: Alice and Bob are friends. Bob loses his database and his
            // friend request status is reset to LKThreadFriendRequestStatusNone. Bob now sends Alice a friend
            // request. Alice's thread's friend request status is reset to
            // LKThreadFriendRequestStatusRequestReceived.
            storage.setFriendRequestStatus(.requestReceived, for: hexEncodedPublicKey, transaction: transaction)
            // Except for the message.friendRequestStatus = LKMessageFriendRequestStatusPending line below, all of this is to ensure that
            // there's only ever one message with status LKMessageFriendRequestStatusPending in a thread (where a thread is the combination
            // of all threads belonging to the linked devices of a user).
            let linkedDeviceThreads = LokiDatabaseUtilities.getLinkedDeviceThreads(for: hexEncodedPublicKey, in: transaction)
            for thread in linkedDeviceThreads {
                thread.enumerateInteractions(with: transaction) { interaction, _ in
                    guard let incomingMessage = interaction as? TSIncomingMessage, incomingMessage.friendRequestStatus != .none else { return }
                    incomingMessage.saveFriendRequestStatus(.none, with: transaction)
                }
            }
            message.friendRequestStatus = .pending
            // Don't save yet. This is done in finalizeIncomingMessage:thread:masterThread:envelope:transaction.
        }
    }
}
