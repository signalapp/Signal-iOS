//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

#if DEBUG

@objc
public class OWSMockSyncManager: NSObject, OWSSyncManagerProtocol {

    @objc public func sendConfigurationSyncMessage() {
        Logger.info("")
    }
}

#endif
