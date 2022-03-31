import SessionMessagingKit
import SessionSnodeKit

extension OWSPrimaryStorage : OWSPrimaryStorageProtocol { }

var isSetup: Bool = false // TODO: Remove this

@objc(SNConfiguration)
public final class Configuration : NSObject {
    
    
    @objc public static func performMainSetup() {
        // Need to do this first to ensure the legacy database exists
        SNUtilitiesKit.configure(
            owsPrimaryStorage: OWSPrimaryStorage.shared(),
            maxFileSize: UInt(Double(FileServerAPIV2.maxFileSize) / FileServerAPIV2.fileSizeORMultiplier)
        )
        
        if !isSetup {
            isSetup = true

            // TODO: Need to store this result somewhere?
            // TODO: This function seems to get called multiple times
            //DispatchQueue.main.once
            let storage: GRDBStorage? = try? GRDBStorage(
                migrations: [
                    SNSnodeKit.migrations(),
                    SNMessagingKit.migrations()
                ]
            )
        }
        
        SNMessagingKit.configure(storage: Storage.shared)
        SNSnodeKit.configure(storage: Storage.shared)
    }
}
