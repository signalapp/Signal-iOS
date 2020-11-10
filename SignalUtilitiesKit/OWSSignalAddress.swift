//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

public enum OWSSignalAddressError: Error {
    case assertionError(description: String)
}

@objc
public class OWSSignalAddress: NSObject {
    @objc
    public let recipientId: String

    @objc
    public let deviceId: UInt

    // MARK: Initializers

    @objc public init(recipientId: String, deviceId: UInt) throws {
        guard recipientId.count > 0 else {
            throw OWSSignalAddressError.assertionError(description: "Invalid recipient id: \(deviceId)")
        }

        guard deviceId > 0 else {
            throw OWSSignalAddressError.assertionError(description: "Invalid device id: \(deviceId)")
        }

        self.recipientId = recipientId
        self.deviceId = deviceId
    }
}
