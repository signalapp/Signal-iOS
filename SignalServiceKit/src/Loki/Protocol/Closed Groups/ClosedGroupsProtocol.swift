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
        func establishSessionsIfNeeded(with hexEncodedPublicKeys: Set<String>) {
            storage.dbReadWriteConnection.readWrite { transaction in
                hexEncodedPublicKeys.forEach { hexEncodedPublicKey in
                    guard hexEncodedPublicKey != getUserHexEncodedPublicKey() else { return }
                    let hasSession = storage.containsSession(hexEncodedPublicKey, deviceId: Int32(OWSDevicePrimaryDeviceId), protocolContext: transaction)
                    guard !hasSession else { return }
                    let thread = TSContactThread.getOrCreateThread(withContactId: hexEncodedPublicKey, transaction: transaction)
                    let sessionRequestMessage = SessionRequestMessage(thread: thread)
                    let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueue
                    messageSenderJobQueue.add(message: sessionRequestMessage, transaction: transaction)
                }
            }
        }
        // We could just let the multi device message sending logic take care of slave devices, but that'd mean
        // making a request to the file server for each member involved. With the line below we (hopefully) reduce
        // that to one request.
        LokiFileServerAPI.getDeviceLinks(associatedWith: Set(closedGroupMembers)).map {
            Set($0.flatMap { [ $0.master.hexEncodedPublicKey, $0.slave.hexEncodedPublicKey ] }).union(closedGroupMembers)
        }.done { hexEncodedPublicKeys in
            DispatchQueue.main.async {
                establishSessionsIfNeeded(with: hexEncodedPublicKeys)
            }
        }.catch { _ in
            // Try the inefficient way if the file server failed
            DispatchQueue.main.async {
                establishSessionsIfNeeded(with: Set(closedGroupMembers))
            }
        }
    }
}

