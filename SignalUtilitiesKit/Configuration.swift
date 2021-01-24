import SessionMessagingKit
import SessionSnodeKit

extension OWSPrimaryStorage : OWSPrimaryStorageProtocol { }

@objc(SNConfiguration)
public final class Configuration : NSObject {
    private static let sharedSenderKeysDelegate = SharedSenderKeysImpl()
    
    private final class SharedSenderKeysImpl : SharedSenderKeysDelegate {
        
        func requestSenderKey(for groupPublicKey: String, senderPublicKey: String, using transaction: Any) {
            // Do nothing
        }
    }
    
    @objc public static func performMainSetup() {
        SNMessagingKit.configure(storage: Storage.shared)
        SNSnodeKit.configure(storage: Storage.shared)
        SNProtocolKit.configure(storage: Storage.shared, sharedSenderKeysDelegate: sharedSenderKeysDelegate)
        SNUtilitiesKit.configure(owsPrimaryStorage: OWSPrimaryStorage.shared(), maxFileSize: UInt(Double(FileServerAPI.maxFileSize) / FileServerAPI.fileSizeORMultiplier))
    }
}
