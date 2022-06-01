import SessionMessagingKit
import SessionSnodeKit

public enum Configuration {
    public static func performMainSetup() {
        // Need to do this first to ensure the legacy database exists
        SNUtilitiesKit.configure(
            maxFileSize: UInt(Double(FileServerAPIV2.maxFileSize) / FileServerAPIV2.fileSizeORMultiplier)
        )
        
        SNMessagingKit.configure()
        SNSnodeKit.configure()
    }
}
