//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SignalServiceAddress: NSObject, NSCopying, NSCoding {
    private static var cache: SignalServiceAddressCache {
        return SSKEnvironment.shared.signalServiceAddressCache
    }

    private(set) var backingPhoneNumber: String?
    @objc public var phoneNumber: String? {
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
    private(set) var backingUuid: UUID?
    @objc public var uuid: UUID? {
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

        backingHashValue = SignalServiceAddress.cache.hashAndCache(uuid: backingUuid, phoneNumber: backingPhoneNumber)

        super.init()

        if !isValid {
            owsFailDebug("Unexpectedly initialized address with no identifier")
        }
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
        backingHashValue = SignalServiceAddress.cache.hashAndCache(uuid: backingUuid, phoneNumber: backingPhoneNumber)
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

    // In order to maintain a consistent hash, we use a constant value generated
    // by the cache that can be mapped back to the phone number OR the UUID.
    //
    // This allows us to dynamically update the backing values to maintain
    // the most complete address object as we learn phone <-> UUID mapping,
    // while also allowing addresses to live in hash tables.
    private let backingHashValue: Int
    public override var hash: Int { return backingHashValue }

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
        return TSAccountManager.localAddress == self
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
    public var serviceIdentifier: String? {
        if FeatureFlags.allowUUIDOnlyContacts {
            guard let uuidString = uuidString else {
                owsFailDebug("uuidString was unexpectedly nil")
                return phoneNumber
            }

            return uuidString
        } else {
            guard let phoneNumber = phoneNumber else {
                owsFailDebug("phoneNumber was unexpectedly nil")
                return uuidString
            }

            return phoneNumber
        }
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

    private var uuidToHashValueCache = [UUID: Int]()
    private var phoneNumberToHashValueCache = [String: Int]()

    override init() {
        super.init()
        AppReadiness.runNowOrWhenAppWillBecomeReady { [weak self] in
            SDSDatabaseStorage.shared.asyncRead { transaction in
                SignalRecipient.anyEnumerate(transaction: transaction) { recipient, _ in
                    let recipientUuid: UUID?
                    if let uuidString = recipient.recipientUUID {
                        recipientUuid = UUID(uuidString: uuidString)
                    } else {
                        recipientUuid = nil
                    }
                    self?.hashAndCache(uuid: recipientUuid, phoneNumber: recipient.recipientPhoneNumber)
                }
            }
        }
    }

    /// Adds a uuid <-> phone number mapping to the cache (if necessary)
    /// and returns a constant hash value that can be used to represent
    /// either of these values going forward for the lifetime of the cache.
    @discardableResult
    func hashAndCache(uuid: UUID?, phoneNumber: String?) -> Int {
        return serialQueue.sync {
            // If we have a UUID and a phone number, cache the mapping.
            if let uuid = uuid, let phoneNumber = phoneNumber {
                uuidToPhoneNumberCache[uuid] = phoneNumber
                phoneNumberToUUIDCache[phoneNumber] = uuid
            }

            // Generate or fetch the unique hash value for this address.

            let hash: Int

            // If we already have a hash for the UUID, use it.
            if let uuid = uuid, let uuidHash = uuidToHashValueCache[uuid] {
                hash = uuidHash

            // Otherwise, if we already have a hash for the phone number, use it.
            } else if let phoneNumber = phoneNumber, let phoneNumberHash = phoneNumberToHashValueCache[phoneNumber] {
                hash = phoneNumberHash

            // Else, create a fresh hash that will be used going forward.
            } else {
                hash = UUID().hashValue
            }

            // Cache the hash we're using to ensure it remains constant across future addresses.

            if let phoneNumber = phoneNumber {
                phoneNumberToHashValueCache[phoneNumber] = hash
            }

            if let uuid = uuid {
                uuidToHashValueCache[uuid] = hash
            }

            return hash
        }
    }

    func uuid(forPhoneNumber phoneNumber: String) -> UUID? {
        return serialQueue.sync { phoneNumberToUUIDCache[phoneNumber] }
    }

    func phoneNumber(forUuid uuid: UUID) -> String? {
        return serialQueue.sync { uuidToPhoneNumberCache[uuid] }
    }
}
