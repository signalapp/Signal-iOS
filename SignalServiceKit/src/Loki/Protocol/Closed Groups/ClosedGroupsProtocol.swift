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
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let thread = thread as? TSGroupThread, thread.groupModel.groupType == .closedGroup,
            dataMessage.group?.type == .deliver else { return false }
        return !thread.isUser(inGroup: hexEncodedPublicKey, transaction: transaction)
    }

    @objc(shouldIgnoreClosedGroupUpdateMessage:in:using:)
    public static func shouldIgnoreClosedGroupUpdateMessage(_ envelope: SSKProtoEnvelope, in thread: TSGroupThread?, using transaction: YapDatabaseReadTransaction) -> Bool {
        // The envelope source is set during UD decryption
        let hexEncodedPublicKey = envelope.source!
        guard let thread = thread else  { return false }
        return !thread.isUserAdmin(inGroup: hexEncodedPublicKey, transaction: transaction) // TODO: I wonder how this was happening in the first place?
    }

    @objc(establishSessionsIfNeededWithClosedGroupMembers:in:using:)
    public static func establishSessionsIfNeeded(with closedGroupMembers: [String], in thread: TSGroupThread, using transaction: YapDatabaseReadWriteTransaction) {
        for member in closedGroupMembers {
            guard member != getUserHexEncodedPublicKey() else { continue }
            let hasSession = storage.containsSession(member, deviceId: 1, protocolContext: transaction) // TODO: Instead of 1 we should use the primary device ID thingy
            if hasSession { continue }
            let thread = TSContactThread.getOrCreateThread(withContactId: member, transaction: transaction)
            let sessionRequestMessage = LKSessionRequestMessage(thread: thread)
            let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
            messageSenderJobQueue.add(message: sessionRequestMessage, transaction: transaction)
        }
    }
}

