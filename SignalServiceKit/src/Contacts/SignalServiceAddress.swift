//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SignalServiceAddress: NSObject {
    @objc
    let phoneNumber: String?

    @objc
    let uuid: UUID? // TODO UUID: eventually this can be not optional

    @objc
    var uuidString: String? {
        return uuid?.uuidString
    }

    @objc
    convenience init(uuidString: String) {
        self.init(uuidString: uuidString, phoneNumber: nil)
    }

    @objc
    convenience init(phoneNumber: String) {
        self.init(uuidString: nil, phoneNumber: phoneNumber)
    }

    @objc
    public init(uuidString: String?, phoneNumber: String?) {
        if let uuidString = uuidString, let uuid = UUID(uuidString: uuidString) {
            self.uuid = uuid
        } else {
            if uuidString != nil {
                owsFailDebug("Unexpectedly initialized signal service address with invalid uuid")
            }
            self.uuid = nil
        }

        if let phoneNumber = phoneNumber, !phoneNumber.isEmpty {
            self.phoneNumber = phoneNumber
        } else {
            if phoneNumber != nil {
                owsFailDebug("Unexpectedly initialized signal service address with invalid phone number")
            }
            self.phoneNumber = nil
        }

        super.init()

        if self.uuid == nil && self.phoneNumber == nil {
            owsFailDebug("Unexpectedly initialized address with no identifier")
        }
    }

    @objc
    public var stringIdentifier: String? {
        if let uuid = uuid {
            return uuid.uuidString
        } else if let phoneNumber = phoneNumber {
            return phoneNumber
        }

        return nil
    }

    @objc
    public var transitional_phoneNumber: String! {
        guard let phoneNumber = phoneNumber else {
            owsFailDebug("transitional_phoneNumber was unexpectedly nil")
            return nil
        }
        return phoneNumber
    }
}

@objc
public extension NSString {
    var transitional_signalServiceAddress: SignalServiceAddress {
        return SignalServiceAddress(phoneNumber: self as String)
    }
}

extension String {
    var transitional_signalServiceAddress: SignalServiceAddress {
        return SignalServiceAddress(phoneNumber: self)
    }
}
