import SessionMessagingKit
import SessionSnodeKit

extension OWSPrimaryStorage : OWSPrimaryStorageProtocol { }

@objc(SNConfiguration)
public final class Configuration : NSObject {
    
    
    @objc public static func performMainSetup() {
        // Need to do this first to ensure the legacy database exists
        SNUtilitiesKit.configure(
            owsPrimaryStorage: OWSPrimaryStorage.shared(),
            maxFileSize: UInt(Double(FileServerAPIV2.maxFileSize) / FileServerAPIV2.fileSizeORMultiplier)
        )
        
        SNMessagingKit.configure(storage: Storage.shared)
        SNSnodeKit.configure()
    }
}
