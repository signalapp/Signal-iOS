import SessionMessagingKit
import SessionSnodeKit

extension OWSPrimaryStorage : OWSPrimaryStorageProtocol { }

@objc(SNConfiguration)
public final class Configuration : NSObject {
    
    @objc public static func performMainSetup() {
        SNMessagingKit.configure(storage: Storage.shared)
        SNSnodeKit.configure(storage: Storage.shared)
        SNUtilitiesKit.configure(
            owsPrimaryStorage: OWSPrimaryStorage.shared(),
            maxFileSize: UInt(Double(FileServerAPI.maxFileSize) / FileServerAPI.fileSizeORMultiplier)
        )
    }
}
