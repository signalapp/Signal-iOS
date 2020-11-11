import SessionProtocolKit
import SessionSnodeKit

@objc(SNConfiguration)
final class Configuration : NSObject {

    @objc func performMainSetup() {
        SessionProtocolKit.configure(storage: Storage.shared, sharedSenderKeysDelegate: UIApplication.shared.delegate as! AppDelegate)
        SessionSnodeKit.configure(storage: Storage.shared)
    }
}
