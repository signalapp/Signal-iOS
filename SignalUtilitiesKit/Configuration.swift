// Copyright © 2022 Rangeproof Pty Ltd. All rights reserved.

import Foundation
import SessionUIKit
import SessionSnodeKit
import SessionMessagingKit

public enum Configuration {
    public static func performMainSetup() {
        // Need to do this first to ensure the legacy database exists
        SNUtilitiesKit.configure(
            maxFileSize: UInt(Double(FileServerAPI.maxFileSize) / FileServerAPI.fileSizeORMultiplier)
        )
        
        SNMessagingKit.configure()
        SNSnodeKit.configure()
        SNUIKit.configure()
    }
}
