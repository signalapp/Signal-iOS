import SessionMessagingKit
import SessionProtocolKit
import SessionSnodeKit

extension OWSPrimaryStorage : OWSPrimaryStorageProtocol { }

@objc(SNConfiguration)
final class Configuration : NSObject {

    @objc static func performMainSetup() {
        SNMessagingKit.configure(
            storage: Storage.shared,
            messageSenderDelegate: MessageSenderDelegate.shared,
            messageReceiverDelegate: MessageReceiverDelegate.shared,
            signalStorage: OWSPrimaryStorage.shared(),
            identityKeyStore: OWSIdentityManager.shared(),
            sessionRestorationImplementation: SessionRestorationImplementation(),
            certificateValidator: SMKCertificateDefaultValidator(trustRoot: OWSUDManagerImpl.trustRoot()),
            openGroupAPIDelegate: OpenGroupAPIDelegate.shared,
            pnServerURL: PushNotificationAPI.server,
            pnServerPublicKey: PushNotificationAPI.serverPublicKey
        )
        SessionProtocolKit.configure(storage: Storage.shared, sharedSenderKeysDelegate: MessageSenderDelegate.shared)
        SessionSnodeKit.configure(storage: Storage.shared)
        SessionUtilitiesKit.configure(owsPrimaryStorage: OWSPrimaryStorage.shared(), maxFileSize: UInt(Double(FileServerAPI.maxFileSize) / FileServerAPI.fileSizeORMultiplier))
    }
}
