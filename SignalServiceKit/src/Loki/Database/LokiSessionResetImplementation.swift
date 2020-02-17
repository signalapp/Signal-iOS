import Foundation
import SignalMetadataKit

@objc(LKSessionResetImplementation)
public class LokiSessionResetImplementation : NSObject, SessionResetProtocol {
    private let storage: OWSPrimaryStorage

    @objc public init(storage: OWSPrimaryStorage) {
        self.storage = storage
    }

    enum Errors : Error {
        case invalidPreKey
        case preKeyIDsDontMatch
    }

    public func validatePreKeyForFriendRequestAcceptance(for recipientID: String, whisperMessage: CipherMessage, protocolContext: Any?) throws {
         guard let transaction = protocolContext as? YapDatabaseReadWriteTransaction else {
            print("[Loki] Could not verify friend request acceptance pre key because an invalid transaction was provided.")
            return
        }
        guard let preKeyMessage = whisperMessage as? PreKeyWhisperMessage else { return }
        guard let storedPreKey = storage.getPreKey(forContact: recipientID, transaction: transaction) else {
            print("[Loki] Received a friend request from a public key for which no pre key bundle was created.")
            throw Errors.invalidPreKey
        }
        guard storedPreKey.id == preKeyMessage.prekeyID else {
            print("[Loki] Received a `PreKeyWhisperMessage` (friend request acceptance) from an unknown source.")
            throw Errors.preKeyIDsDontMatch
        }
    }

    public func getSessionResetStatus(for recipientID: String, protocolContext: Any?) -> SessionResetStatus {
        guard let transaction = protocolContext as? YapDatabaseReadWriteTransaction else {
            print("[Loki] Could not get session reset status for \(recipientID) because an invalid transaction was provided.")
            return .none
        }
        guard let thread = TSContactThread.getWithContactId(recipientID, transaction: transaction) else { return .none }
        return thread.sessionResetStatus
    }

    public func onNewSessionAdopted(for recipientID: String, protocolContext: Any?) {
        guard let transaction = protocolContext as? YapDatabaseReadWriteTransaction else {
            Logger.warn("[Loki] Cannot handle new session adoption because an invalid transaction was provided.")
            return
        }
        guard !recipientID.isEmpty else { return }
        guard let thread = TSContactThread.getWithContactId(recipientID, transaction: transaction) else {
            Logger.debug("[Loki] A new session was adopted but the thread couldn't be found for: \(recipientID).")
            return
        }
        // If the current user initiated the reset then send back an empty message to acknowledge the completion of the session reset
        if thread.sessionResetStatus == .initiated {
            let emptyMessage = EphemeralMessage(in: thread)
            SSKEnvironment.shared.messageSender.sendPromise(message: emptyMessage).retainUntilComplete()
        }
        // Show session reset done message
        TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeLokiSessionResetDone).save(with: transaction)
        // Clear the session reset status
        thread.sessionResetStatus = .none
        thread.save(with: transaction)
    }
}
