//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SSKProtos: NSObject {

    private override init() {}

    @objc
    public class var currentProtocolVersion: Int {
        // If we don't want clients to receive reactions yet, our current
        // protocol version should not be the "current" version in the proto
        guard FeatureFlags.reactionReceive else {
            return SignalServiceProtos_DataMessage.ProtocolVersion.viewOnceVideo.rawValue
        }

        // Our proto wrappers don't handle enum aliases, so we have one non-generated
        // wrapper for the "current" protocol version.
        return SignalServiceProtos_DataMessage.ProtocolVersion.current.rawValue
    }
}
