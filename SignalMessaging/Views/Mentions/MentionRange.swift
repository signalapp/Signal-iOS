//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objcMembers
public class MentionRange: NSObject, NSSecureCoding {
    public static var supportsSecureCoding = true

    public let location: Int
    public let length: Int
    public let address: SignalServiceAddress

    public var nsRange: NSRange { .init(location: location, length: length) }

    public convenience init(nsRange: NSRange, address: SignalServiceAddress) {
        self.init(location: nsRange.location, length: nsRange.length, address: address)
    }

    public init(location: Int, length: Int, address: SignalServiceAddress) {
        self.location = location
        self.length = length
        self.address = address

        super.init()
    }

    public required init?(coder: NSCoder) {
        guard let address = coder.decodeObject(of: SignalServiceAddress.self, forKey: "address") else {
            owsFailDebug("Failed to decode MentionRange")
            return nil
        }

        self.location = coder.decodeInteger(forKey: "location")
        self.length = coder.decodeInteger(forKey: "length")
        self.address = address
    }

    public func encode(with coder: NSCoder) {
        coder.encode(address, forKey: "address")
        coder.encode(location, forKey: "location")
        coder.encode(length, forKey: "length")
    }
}
