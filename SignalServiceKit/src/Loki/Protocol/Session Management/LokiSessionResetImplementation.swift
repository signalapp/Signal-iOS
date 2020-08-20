import SessionMetadataKit

@objc(LKSessionResetImplementation)
public class LokiSessionResetImplementation : NSObject, SessionResetProtocol {

    private var storage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }

    enum Error : Swift.Error {
        case invalidPreKey
        case preKeyIDsDontMatch
    }

    public func validatePreKeyWhisperMessage(for recipientID: String, whisperMessage: CipherMessage, protocolContext: Any?) throws {
         guard let transaction = protocolContext as? YapDatabaseReadTransaction else {
            print("[Loki] Invalid transaction.")
            return
        }
        guard let preKeyMessage = whisperMessage as? PreKeyWhisperMessage else { return }
        guard let storedPreKey = storage.getPreKeyRecord(forContact: recipientID, transaction: transaction) else {
            print("[Loki] Missing pre key bundle.")
            throw Error.invalidPreKey
        }
        guard storedPreKey.id == preKeyMessage.prekeyID else {
            print("[Loki] Received a `PreKeyWhisperMessage` from an unknown source.")
            throw Error.preKeyIDsDontMatch
        }
    }

    public func getSessionResetStatus(for recipientID: String, protocolContext: Any?) -> SessionResetStatus {
        guard let transaction = protocolContext as? YapDatabaseReadTransaction else {
            print("[Loki] Couldn't get session reset status for \(recipientID) because an invalid transaction was provided.")
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
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeLokiSessionResetDone)
        infoMessage.save(with: transaction)
        // Update the session reset status
        thread.sessionResetStatus = .none
        thread.save(with: transaction)
    }
}
