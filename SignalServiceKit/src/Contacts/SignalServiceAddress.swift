//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SignalServiceAddress: NSObject, NSCopying, NSCoding {
    private static var cache: SignalServiceAddressCache {
        return SSKEnvironment.shared.signalServiceAddressCache
    }

    fileprivate(set) var backingPhoneNumber: String?
    fileprivate(set) var backingUuid: UUID?

    @objc
    public var phoneNumber: String? {
        guard let phoneNumber = backingPhoneNumber else {
            // If we weren't initialized with a phone number, but the phone number exists in the cache, use it
            guard let uuid = backingUuid,
                let cachedPhoneNumber = SignalServiceAddress.cache.phoneNumber(forUuid: uuid)
            else {
                return nil
            }
            backingPhoneNumber = cachedPhoneNumber
            return cachedPhoneNumber
        }

        return phoneNumber
    }

    // TODO UUID: eventually this can be not optional
    @objc
    public var uuid: UUID? {
        guard let uuid = backingUuid else {
            // If we weren't initialized with a uuid, but the uuid exists in the cache, use it
            guard let phoneNumber = backingPhoneNumber,
                let cachedUuid = SignalServiceAddress.cache.uuid(forPhoneNumber: phoneNumber)
            else {
                return nil
            }
            backingUuid = cachedUuid
            return cachedUuid
        }

        return uuid
    }

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
        if phoneNumber == nil, let uuid = uuid,
            let cachedPhoneNumber = SignalServiceAddress.cache.phoneNumber(forUuid: uuid) {
            backingPhoneNumber = cachedPhoneNumber
        } else {
            if let phoneNumber = phoneNumber, phoneNumber.isEmpty {
                owsFailDebug("Unexpectedly initialized signal service address with invalid phone number")
            }

            backingPhoneNumber = phoneNumber
        }

        if uuid == nil, let phoneNumber = phoneNumber,
            let cachedUuid = SignalServiceAddress.cache.uuid(forPhoneNumber: phoneNumber) {
            backingUuid = cachedUuid
        } else {
            backingUuid = uuid
        }

        super.init()

        if !isValid {
            owsFailDebug("Unexpectedly initialized address with no identifier")
        }

        SignalServiceAddress.cache.add(address: self)
    }

    @objc
    public convenience init(uuidString: String?, phoneNumber: String?) {
        let uuid: UUID?

        if let uuidString = uuidString {
            uuid = UUID(uuidString: uuidString)
            if uuid == nil {
                owsFailDebug("Unexpectedly initialized signal service address with invalid uuid")
            }
        } else {
            uuid = nil
        }

        self.init(uuid: uuid, phoneNumber: phoneNumber)
    }

    // MARK: -

    public func encode(with aCoder: NSCoder) {
        aCoder.encode(backingUuid, forKey: "backingUuid")
        aCoder.encode(backingPhoneNumber, forKey: "backingPhoneNumber")
    }

    public required init?(coder aDecoder: NSCoder) {
        backingUuid = aDecoder.decodeObject(forKey: "backingUuid") as? UUID
        backingPhoneNumber = aDecoder.decodeObject(forKey: "backingPhoneNumber") as? String
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

        return isEqualToAddress(otherAddress)
    }

    @objc
    public func isEqualToAddress(_ otherAddress: SignalServiceAddress?) -> Bool {
        guard let otherAddress = otherAddress else {
            return false
        }

        return otherAddress.phoneNumber == phoneNumber && otherAddress.uuid == uuid
    }

    public override var hash: Int {
        return (phoneNumber?.hashValue ?? 0) ^ (uuid?.hashValue ?? 0)
    }

    @objc
    public func compare(_ otherAddress: SignalServiceAddress) -> ComparisonResult {
        return stringForDisplay.compare(otherAddress.stringForDisplay)
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
    public var isLocalAddress: Bool {
        return SSKEnvironment.shared.tsAccountManager.localAddress == self
    }

    @objc
    public var stringForDisplay: String {
        if let phoneNumber = phoneNumber {
            return phoneNumber
        } else if let uuid = uuid {
            return uuid.uuidString
        }

        owsFailDebug("unexpectedly have no backing value")

        return ""
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

@objc
class SignalServiceAddressCache: NSObject {
    private let serialQueue = DispatchQueue(label: "SignalServiceAddressCache")

    private var uuidToPhoneNumberCache = [UUID: String]()
    private var phoneNumberToUUIDCache = [String: UUID]()

    override init() {
        super.init()
        AppReadiness.runNowOrWhenAppWillBecomeReady { [weak self] in
            SDSDatabaseStorage.shared.asyncRead { transaction in
                SignalRecipient.anyEnumerate(transaction: transaction) { recipient, _ in
                    self?.add(address: recipient.address)
                }
            }
        }
    }

    func add(address: SignalServiceAddress) {
        serialQueue.async {
            if let uuid = address.backingUuid, let phoneNumber = address.backingPhoneNumber {
                self.uuidToPhoneNumberCache[uuid] = phoneNumber
                self.phoneNumberToUUIDCache[phoneNumber] = uuid
            }
        }
    }

    func uuid(forPhoneNumber phoneNumber: String) -> UUID? {
        return serialQueue.sync { phoneNumberToUUIDCache[phoneNumber] }
    }

    func phoneNumber(forUuid uuid: UUID) -> String? {
        return serialQueue.sync { uuidToPhoneNumberCache[uuid] }
    }
}
