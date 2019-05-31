//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SSKProtos: NSObject {

    private override init() {}
    
    @objc
    public class var initialProtocolVersion: Int {
        return SignalServiceProtos_DataMessage.ProtocolVersion.initial.rawValue
    }
    
    @objc
    public class var perMessageExpirationProtocolVersion: Int {
        return SignalServiceProtos_DataMessage.ProtocolVersion.messageTimers.rawValue
    }

    @objc
    public class var currentProtocolVersion: Int {
        return SignalServiceProtos_DataMessage.ProtocolVersion.current.rawValue
    }
}
