//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SSKProtos: NSObject {

    private override init() {}

    @objc
    public class var currentProtocolVersion: Int {
        return SignalServiceProtos_DataMessage.ProtocolVersion.current.rawValue
    }
}
