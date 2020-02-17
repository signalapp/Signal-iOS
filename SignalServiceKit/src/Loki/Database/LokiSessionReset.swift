import Foundation
import SignalMetadataKit

@objc(LKSessionReset)
public class LokiSessionReset: NSObject, SessionResetProtocol {
    private let storage: OWSPrimaryStorage

    @objc public init(storage: OWSPrimaryStorage) {
        self.storage = storage
    }

    enum Errors : Error {
        case invalidPreKey
        case preKeyIdsDontMatch
    }

    public func verifyFriendRequestAcceptPreKey(for recipientId: String, whisperMessage: CipherMessage, protocolContext: Any?) throws {
         guard let transaction = protocolContext as? YapDatabaseReadWriteTransaction else {
            owsFailDebug("Could not verify friend request accept prekey because invalid transaction was passed")
            return
        }

        guard let preKeyMessage = whisperMessage as? PreKeyWhisperMessage else { return }

        guard let storedPreKey = storage.getPreKey(forContact: recipientId, transaction: transaction) else {
            Logger.error("Received a friend request from a public key for which no prekey bundle was created.")
            throw Errors.invalidPreKey
        }

        guard storedPreKey.id == preKeyMessage.prekeyID else {
            Logger.error("Received a PreKeyWhisperMessage (friend request accept) from an unknown source.")
            throw Errors.preKeyIdsDontMatch
        }
    }

    public func getSessionResetStatus(for recipientId: String, protocolContext: Any?) -> SessionResetStatus {
        guard let transaction = protocolContext as? YapDatabaseReadWriteTransaction else {
            Logger.warn("Could not get session reset status for \(recipientId) because invalid transaction was passed")
            return .none
        }
        guard let thread = TSContactThread.getWithContactId(recipientId, transaction: transaction) else { return .none }
        return thread.sessionResetStatus
    }
}
