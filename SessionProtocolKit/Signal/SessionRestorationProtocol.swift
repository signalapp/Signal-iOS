
@objc(LKSessionRestorationProtocol)
public protocol SessionRestorationProtocol {

    func validatePreKeyWhisperMessage(for recipientPublicKey: String, whisperMessage: CipherMessage, using transaction: Any) throws
    func getSessionRestorationStatus(for recipientPublicKey: String) -> SessionRestorationStatus
    func handleNewSessionAdopted(for recipientPublicKey: String, using transaction: Any)
}
