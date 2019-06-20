//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SignalServiceAddress: NSObject {
    private enum BackingStorage {
        case phoneNumber(_ number: String)
        case uuid(_ uuid: UUID)
    }

    private let backingAddress: BackingStorage

    @objc
    public init(phoneNumber: String) {
        self.backingAddress = .phoneNumber(phoneNumber)
    }

    @objc
    public init(uuid: UUID) {
        self.backingAddress = .uuid(uuid)
    }

    @objc
    public var transitional_phoneNumber: String! {
        switch backingAddress {
        case .phoneNumber(let phoneNumber):
            return phoneNumber
        case .uuid:
            owsFailDebug("transitional_phoneNumber was unexpectedly nil")
            return nil
        }
    }
}
