import SessionMessagingKit
import SessionProtocolKit
import SessionSnodeKit

@objc(SNConfiguration)
final class Configuration : NSObject {

    private static let pnServerURL = "https://live.apns.getsession.org"
    private static let pnServerPublicKey = "642a6585919742e5a2d4dc51244964fbcd8bcab2b75612407de58b810740d049"

    @objc static func performMainSetup() {
        SNMessagingKit.configure(
            storage: Storage.shared,
            signalStorage: OWSPrimaryStorage.shared(),
            identityKeyStore: OWSIdentityManager.shared(),
            sessionRestorationImplementation: SessionRestorationImplementation(),
            certificateValidator: SMKCertificateDefaultValidator(trustRoot: OWSUDManagerImpl.trustRoot()),
            openGroupAPIDelegate: UIApplication.shared.delegate as! AppDelegate,
            pnServerURL: pnServerURL,
            pnServerPublicKey: pnServerURL
        )
        SessionProtocolKit.configure(storage: Storage.shared, sharedSenderKeysDelegate: UIApplication.shared.delegate as! AppDelegate)
        SessionSnodeKit.configure(storage: Storage.shared)
    }
}
