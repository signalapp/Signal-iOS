import SessionProtocolKit

@objc(SNSessionRestorationImplementation)
public final class SessionRestorationImplementation : NSObject, SessionRestorationProtocol {

    private var storage: OWSPrimaryStorage {
        return OWSPrimaryStorage.shared()
    }

    enum Error : LocalizedError {
        case missingPreKey
        case invalidPreKeyID
    }

    public func validatePreKeyWhisperMessage(for publicKey: String, preKeyWhisperMessage: PreKeyWhisperMessage, using transaction: Any) throws {
        guard let transaction = transaction as? YapDatabaseReadTransaction else { return }
        guard let storedPreKey = storage.getPreKeyRecord(forContact: publicKey, transaction: transaction) else {
            SNLog("Missing pre key bundle.")
            throw Error.missingPreKey
        }
        guard storedPreKey.id == preKeyWhisperMessage.prekeyID else {
            SNLog("Received a PreKeyWhisperMessage from an unknown source.")
            throw Error.invalidPreKeyID
        }
    }

    public func getSessionRestorationStatus(for publicKey: String) -> SessionRestorationStatus {
        var thread: TSContactThread?
        Storage.read { transaction in
            thread = TSContactThread.getWithContactId(publicKey, transaction: transaction)
        }
        return .none
    }

    public func handleNewSessionAdopted(for publicKey: String, using transaction: Any) {
        guard let transaction = transaction as? YapDatabaseReadWriteTransaction else { return }
        guard !publicKey.isEmpty else { return }
        guard let thread = TSContactThread.getWithContactId(publicKey, transaction: transaction) else {
            return SNLog("A new session was adopted but the thread couldn't be found for: \(publicKey).")
        }
        // Notify the user
        let infoMessage = TSInfoMessage(timestamp: NSDate.ows_millisecondTimeStamp(), in: thread, messageType: .typeLokiSessionResetDone)
        infoMessage.save(with: transaction)
        // Update the session reset status
        thread.save(with: transaction)
    }
}
