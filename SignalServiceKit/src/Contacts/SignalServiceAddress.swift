//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SignalServiceAddress: NSObject, NSCopying, NSCoding {
    @objc
    public let phoneNumber: String?

    @objc
    public let uuid: UUID? // TODO UUID: eventually this can be not optional

    @objc
    public var uuidString: String? {
        return uuid?.uuidString
    }

    // MARK: - Initializers

    @objc
    public convenience init(uuidString: String) {
        self.init(uuidString: uuidString, phoneNumber: nil)
    }

    @objc
    public convenience init(phoneNumber: String) {
        self.init(uuidString: nil, phoneNumber: phoneNumber)
    }

    @objc
    public init(uuid: UUID?, phoneNumber: String?) {
        self.uuid = uuid
        self.phoneNumber = phoneNumber

        super.init()
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

        if !isValid {
            owsFailDebug("Unexpectedly initialized address with no identifier")
        }
    }

    // MARK: -

    public func encode(with aCoder: NSCoder) {
        aCoder.encode(uuid, forKey: "uuid")
        aCoder.encode(phoneNumber, forKey: "phoneNumber")
    }

    public required init?(coder aDecoder: NSCoder) {
        uuid = aDecoder.decodeObject(forKey: "uuid") as? UUID
        phoneNumber = aDecoder.decodeObject(forKey: "phoneNumber") as? String
    }

    // MARK: -

    @objc
    public func copy(with zone: NSZone? = nil) -> Any {
        return SignalServiceAddress(uuid: uuid, phoneNumber: phoneNumber)
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let otherAddress = object as? SignalServiceAddress else {
            return false
        }

        return otherAddress.phoneNumber == phoneNumber && otherAddress.uuid == uuid
    }

    public override var hash: Int {
        return (phoneNumber?.hashValue ?? 0) ^ (uuid?.hashValue ?? 0)
    }

    // MARK: -

    @objc
    public var isValid: Bool {
        if uuid != nil {
            return true
        }

        if let phoneNumber = phoneNumber {
            return !phoneNumber.isEmpty
        }

        return false
    }

    @objc
    public func matchesAddress(_ otherAddress: SignalServiceAddress?) -> Bool {
        guard let otherAddress = otherAddress else {
            return false
        }

        if let otherUuid = otherAddress.uuid, let thisUuid = uuid {
            return otherUuid == thisUuid
        }

        if let otherPhone = otherAddress.phoneNumber, let thisPhone = phoneNumber {
            return otherPhone == thisPhone
        }

        owsFailDebug("otherAddress had neither uuid nor phone")
        return false
    }

    @objc
    public var isLocalAddress: Bool {
        return matchesAddress(SSKEnvironment.shared.tsAccountManager.localAddress)
    }

    @objc
    public var stringForDisplay: String? {
        if let phoneNumber = phoneNumber {
            return phoneNumber
        } else if let uuid = uuid {
            return uuid.uuidString
        }

        return nil
    }

    @objc
    override public var description: String {
        let redactedUUID: String?
        if let uuid = uuid {
            redactedUUID = "[REDACTED_UUID:xxx\(uuid.uuidString.suffix(2))]"
        } else {
            redactedUUID = nil
        }

        return "<SignalServiceAddress phoneNumber: \(phoneNumber ?? "nil"), uuid: \(redactedUUID ?? "nil")>"
    }

    // MARK: - Transitional Methods

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
