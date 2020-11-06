import SessionProtocolKit

public protocol SessionMessagingKitStorageProtocol {

    func with(_ work: (Any) -> Void)

    func getOrGenerateRegistrationID(using transaction: Any) -> UInt32
}
