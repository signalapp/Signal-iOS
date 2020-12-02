import SessionMessagingKit
import SessionProtocolKit
import SessionSnodeKit

extension OWSPrimaryStorage : OWSPrimaryStorageProtocol { }

@objc(SNConfiguration)
public final class Configuration : NSObject {

    @objc public static func performMainSetup() {
        SNMessagingKit.configure(
            storage: Storage.shared,
            signalStorage: OWSPrimaryStorage.shared(),
            identityKeyStore: OWSIdentityManager.shared(),
            sessionRestorationImplementation: SessionRestorationImplementation(),
            certificateValidator: SMKCertificateDefaultValidator(trustRoot: OWSUDManagerImpl.trustRoot())
        )
        SNProtocolKit.configure(storage: Storage.shared, sharedSenderKeysDelegate: MessageSender.shared)
        SNSnodeKit.configure(storage: Storage.shared)
        SNUtilitiesKit.configure(owsPrimaryStorage: OWSPrimaryStorage.shared(), maxFileSize: UInt(Double(FileServerAPI.maxFileSize) / FileServerAPI.fileSizeORMultiplier))
    }
}
