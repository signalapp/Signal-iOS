//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SSKProtos: NSObject {

    private override init() {}

    @objc
    public class var currentProtocolVersion: Int {
        guard FeatureFlags.mentionsReceive else {
            return SignalServiceProtos_DataMessage.ProtocolVersion.cdnSelectorAttachments.rawValue
        }

        // Our proto wrappers don't handle enum aliases, so we have one non-generated
        // wrapper for the "current" protocol version.
        return SignalServiceProtos_DataMessage.ProtocolVersion.current.rawValue
    }
}
