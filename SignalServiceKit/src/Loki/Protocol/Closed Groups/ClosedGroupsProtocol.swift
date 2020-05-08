import PromiseKit

// A few notes about making changes in this file:
//
// • Don't use a database transaction if you can avoid it.
// • If you do need to use a database transaction, use a read transaction if possible.
// • Consider making it the caller's responsibility to manage the database transaction (this helps avoid nested or unnecessary transactions).
// • Think carefully about adding a function; there might already be one for what you need.
// • Document the expected cases for everything.
// • Express those cases in tests.

@objc(LKClosedGroupsProtocol)
public final class ClosedGroupsProtocol : NSObject {

    internal static var storage: OWSPrimaryStorage { OWSPrimaryStorage.shared() }

    // MARK: - Receiving
    @objc(shouldIgnoreClosedGroupMessage:inThread:wrappedIn:using:)
    public static func shouldIgnoreClosedGroupMessage(_ dataMessage: SSKProtoDataMessage, in thread: TSThread, wrappedIn envelope: SSKProtoEnvelope, using transaction: YapDatabaseReadTransaction) -> Bool {
        guard let thread = thread as? TSGroupThread, thread.groupModel.groupType == .closedGroup,
            dataMessage.group?.type == .deliver else { return false }
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        return !thread.isUser(inGroup: hexEncodedPublicKey, transaction: transaction)
    }

    @objc(shouldIgnoreClosedGroupUpdateMessage:in:using:)
    public static func shouldIgnoreClosedGroupUpdateMessage(_ envelope: SSKProtoEnvelope, in thread: TSGroupThread?, using transaction: YapDatabaseReadTransaction) -> Bool {
        guard let thread = thread else { return false }
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        return !thread.isUserAdmin(inGroup: hexEncodedPublicKey, transaction: transaction)
    }

    @objc(establishSessionsIfNeededWithClosedGroupMembers:in:)
    public static func establishSessionsIfNeeded(with closedGroupMembers: [String], in thread: TSGroupThread) {
        storage.dbReadWriteConnection.readWrite { transaction in
            closedGroupMembers.forEach { hexEncodedPublicKey in
                guard hexEncodedPublicKey != getUserHexEncodedPublicKey() else { return }
                let hasSession = storage.containsSession(hexEncodedPublicKey, deviceId: Int32(OWSDevicePrimaryDeviceId), protocolContext: transaction)
                guard !hasSession else { return }
                let thread = TSContactThread.getOrCreateThread(withContactId: hexEncodedPublicKey, transaction: transaction)
                thread.save(with: transaction)
                let sessionRequestMessage = SessionRequestMessage(thread: thread)
                let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
                messageSenderJobQueue.add(message: sessionRequestMessage, transaction: transaction)
            }
        }
    }
}

