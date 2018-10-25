//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalMetadataKit

@objc
public class SSKUnidentifiedAccess: NSObject {
    @objc
    let accessKey: SMKUDAccessKey

    @objc
    let senderCertificate: SMKSenderCertificate

    init(accessKey: SMKUDAccessKey, senderCertificate: SMKSenderCertificate) {
        self.accessKey = accessKey
        self.senderCertificate = senderCertificate
    }
}
