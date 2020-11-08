
@objc(LKSessionRestorationProtocol)
public protocol SessionRestorationProtocol {

    func validatePreKeyWhisperMessage(for publicKey: String, preKeyWhisperMessage: PreKeyWhisperMessage, using transaction: Any) throws
    func getSessionRestorationStatus(for publicKey: String) -> SessionRestorationStatus
    func handleNewSessionAdopted(for publicKey: String, using transaction: Any)
}
