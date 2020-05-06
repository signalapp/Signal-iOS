import PromiseKit

// A few notes about making changes in this file:
//
// • Don't use a database transaction if you can avoid it.
// • If you do need to use a database transaction, use a read transaction if possible.
// • Consider making it the caller's responsibility to manage the database transaction (this helps avoid nested or unnecessary transactions).
// • Think carefully about adding a function; there might already be one for what you need.
// • Document the expected cases for everything.
// • Express those cases in tests.

@objc(LKSessionManagementProtocol)
public final class SessionManagementProtocol : NSObject {

    internal static var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }

    // MARK: - General
    // BEHAVIOR NOTE: OWSMessageSender.throws_encryptedMessageForMessageSend:recipientId:plaintext:transaction: sets
    // isFriendRequest to true if the message in question is a friend request or a device linking request, but NOT if
    // it's a session request.

    // TODO: Does the above make sense?

    @objc(createPreKeys)
    public static func createPreKeys() {
        // We don't generate new pre keys here like Signal does.
        // This is because we need the records to be linked to a contact since we don't have a central server.
        // It's done automatically when we generate a pre key bundle to send to a contact (generatePreKeyBundleForContact:).
        // You can use getOrCreatePreKeyForContact: to generate one if needed.
        let signedPreKeyRecord = storage.generateRandomSignedRecord()
        signedPreKeyRecord.markAsAcceptedByService()
        storage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
        storage.setCurrentSignedPrekeyId(signedPreKeyRecord.id)
        print("[Loki] Pre keys created successfully.")
    }

    @objc(refreshSignedPreKey)
    public static func refreshSignedPreKey() {
        // We don't generate new pre keys here like Signal does.
        // This is because we need the records to be linked to a contact since we don't have a central server.
        // It's done automatically when we generate a pre key bundle to send to a contact (generatePreKeyBundleForContact:).
        // You can use getOrCreatePreKeyForContact: to generate one if needed.
        guard storage.currentSignedPrekeyId() == nil else {
            print("[Loki] Skipping signed pre key refresh; using existing signed pre key.")
            return
        }
        let signedPreKeyRecord = storage.generateRandomSignedRecord()
        signedPreKeyRecord.markAsAcceptedByService()
        storage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
        storage.setCurrentSignedPrekeyId(signedPreKeyRecord.id)
        TSPreKeyManager.clearPreKeyUpdateFailureCount()
        TSPreKeyManager.clearSignedPreKeyRecords()
        print("[Loki] Signed pre key refreshed successfully.")
    }

    @objc(rotateSignedPreKey)
    public static func rotateSignedPreKey() {
        // This is identical to what Signal does, except that it doesn't upload the signed pre key
        // to a server.
        let signedPreKeyRecord = storage.generateRandomSignedRecord()
        signedPreKeyRecord.markAsAcceptedByService()
        storage.storeSignedPreKey(signedPreKeyRecord.id, signedPreKeyRecord: signedPreKeyRecord)
        storage.setCurrentSignedPrekeyId(signedPreKeyRecord.id)
        TSPreKeyManager.clearPreKeyUpdateFailureCount()
        TSPreKeyManager.clearSignedPreKeyRecords()
        print("[Loki] Signed pre key rotated successfully.")
    }

    @objc(shouldUseFallbackEncryptionForMessage:)
    public static func shouldUseFallbackEncryption(_ message: TSOutgoingMessage) -> Bool {
        return !isSessionRequired(for: message)
    }

    @objc(isSessionRequiredForMessage:)
    public static func isSessionRequired(for message: TSOutgoingMessage) -> Bool {
        if message is FriendRequestMessage { return false }
        else if message is SessionRequestMessage { return false }
        else if let message = message as? DeviceLinkMessage, message.kind == .request { return false }
        return true
    }

    // MARK: - Sending
    // TODO: Confusing that we have this but also a receiving version
    @objc(sending_startSessionResetInThread:using:)
    public static func sending_startSessionReset(in thread: TSThread, using transaction: YapDatabaseReadWriteTransaction) {
        guard let thread = thread as? TSContactThread else {
            print("[Loki] Can't restore session for non contact thread.")
            return
        }
        let messageSender = SSKEnvironment.shared.messageSender
        let devices = thread.sessionRestoreDevices // TODO: Rename this
        for device in devices {
            guard device.count != 0 else { continue }
            getSessionResetMessageSend(for: device, in: transaction).done(on: OWSDispatch.sendingQueue()) { sessionResetMessageSend in
                messageSender.sendMessage(sessionResetMessageSend)
            }
        }
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeLokiSessionResetInProgress)
        infoMessage.save(with: transaction)
        thread.sessionResetStatus = .requestReceived
        thread.save(with: transaction)
        thread.removeAllSessionRestoreDevices(with: transaction)
    }

    @objc(getSessionResetMessageForHexEncodedPublicKey:in:)
    public static func getSessionResetMessage(for hexEncodedPublicKey: String, in transaction: YapDatabaseReadWriteTransaction) -> SessionRestoreMessage {
        let thread = TSContactThread.getOrCreateThread(withContactId: hexEncodedPublicKey, transaction: transaction)
        let result = SessionRestoreMessage(thread: thread)
        result.skipSave = true // TODO: Why is this necessary again?
        return result
    }

    @objc(getSessionResetMessageSendForHexEncodedPublicKey:in:)
    public static func objc_getSessionResetMessageSend(for hexEncodedPublicKey: String, in transaction: YapDatabaseReadWriteTransaction) -> AnyPromise {
        return AnyPromise.from(getSessionResetMessageSend(for: hexEncodedPublicKey, in: transaction))
    }

    public static func getSessionResetMessageSend(for hexEncodedPublicKey: String, in transaction: YapDatabaseReadWriteTransaction) -> Promise<OWSMessageSend> {
        let thread = TSContactThread.getOrCreateThread(withContactId: hexEncodedPublicKey, transaction: transaction)
        let message = getSessionResetMessage(for: hexEncodedPublicKey, in: transaction)
        let recipient = SignalRecipient.getOrBuildUnsavedRecipient(forRecipientId: hexEncodedPublicKey, transaction: transaction)
        let udManager = SSKEnvironment.shared.udManager
        let senderCertificate = udManager.getSenderCertificate()
        let (promise, seal) = Promise<OWSMessageSend>.pending()
        // Dispatch async on the main queue to avoid nested write transactions
        DispatchQueue.main.async {
            var recipientUDAccess: OWSUDAccess?
            if let senderCertificate = senderCertificate {
                recipientUDAccess = udManager.udAccess(forRecipientId: hexEncodedPublicKey, requireSyncAccess: true) // Starts a new write transaction internally
            }
            let messageSend = OWSMessageSend(message: message, thread: thread, recipient: recipient, senderCertificate: senderCertificate,
                udAccess: recipientUDAccess, localNumber: getUserHexEncodedPublicKey(), success: {

            }, failure: { error in

            })
            seal.fulfill(messageSend)
        }
        return promise
    }

    // MARK: - Receiving
    @objc(handleDecryptionError:forHexEncodedPublicKey:using:)
    public static func handleDecryptionError(_ rawValue: Int32, for hexEncodedPublicKey: String, using transaction: YapDatabaseReadWriteTransaction) {
        let type = TSErrorMessageType(rawValue: rawValue)
        let masterHexEncodedPublicKey = storage.getMasterHexEncodedPublicKey(for: hexEncodedPublicKey, in: transaction) ?? hexEncodedPublicKey
        let thread = TSContactThread.getOrCreateThread(withContactId: masterHexEncodedPublicKey, transaction: transaction)
        // Show the session reset prompt upon certain errors
        switch type {
        case .noSession, .invalidMessage, .invalidKeyException:
            // Store the source device's public key in case it was a secondary device
            thread.addSessionRestoreDevice(hexEncodedPublicKey, transaction: transaction)
        default: break
        }
    }

    @objc(isSessionRestoreMessage:)
    public static func isSessionRestoreMessage(_ dataMessage: SSKProtoDataMessage) -> Bool {
        let sessionRestoreFlag = SSKProtoDataMessage.SSKProtoDataMessageFlags.sessionRestore
        return dataMessage.flags & UInt32(sessionRestoreFlag.rawValue) != 0
    }

    @objc(isSessionRequestMessage:)
    public static func isSessionRequestMessage(_ dataMessage: SSKProtoDataMessage) -> Bool {
        let sessionRequestFlag = SSKProtoDataMessage.SSKProtoDataMessageFlags.sessionRequest
        return dataMessage.flags & UInt32(sessionRequestFlag.rawValue) != 0
    }

    // TODO: This needs an explanation of when we expect pre key bundles to be attached
    @objc(handlePreKeyBundleMessageIfNeeded:wrappedIn:using:)
    public static func handlePreKeyBundleMessageIfNeeded(_ protoContent: SSKProtoContent, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadWriteTransaction) {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let preKeyBundleMessage = protoContent.prekeyBundleMessage else { return }
        print("[Loki] Received a pre key bundle message from: \(hexEncodedPublicKey).")
        guard let preKeyBundle = preKeyBundleMessage.getPreKeyBundle(with: transaction) else {
            print("[Loki] Couldn't parse pre key bundle received from: \(hexEncodedPublicKey).")
            return
        }
        storage.setPreKeyBundle(preKeyBundle, forContact: hexEncodedPublicKey, transaction: transaction)
        // If we received a friend request (i.e. also a new pre key bundle), but we were already friends with the other user, reset the session.
        // The envelope type is set during UD decryption.
        // TODO: Should this ignore session requests?
        if envelope.type == .friendRequest,
            let thread = TSContactThread.getWithContactId(hexEncodedPublicKey, transaction: transaction), // TODO: Should this be getOrCreate?
            thread.isContactFriend {
            receiving_startSessionReset(in: thread, using: transaction)
        }
    }

    // TODO: Confusing that we have this but also a sending version
    @objc(receiving_startSessionResetInThread:using:)
    public static func receiving_startSessionReset(in thread: TSContactThread, using transaction: YapDatabaseReadWriteTransaction) {
        let hexEncodedPublicKey = thread.contactIdentifier()
        print("[Loki] Session reset request received from: \(hexEncodedPublicKey).")
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeLokiSessionResetInProgress)
        infoMessage.save(with: transaction)
        // Archive all sessions
        storage.archiveAllSessions(forContact: hexEncodedPublicKey, protocolContext: transaction)
        // Update session reset status
        thread.sessionResetStatus = .requestReceived
        thread.save(with: transaction)
        // Send an ephemeral message to trigger session reset for the other party as well
        let ephemeralMessage = EphemeralMessage(in: thread)
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
        messageSenderJobQueue.add(message: ephemeralMessage, transaction: transaction)
    }
}
