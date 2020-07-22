//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc
public class SignalServiceAddress: NSObject, NSCopying, NSSecureCoding, Codable {
    public static let supportsSecureCoding: Bool = true

    private static var cache: SignalServiceAddressCache {
        return SSKEnvironment.shared.signalServiceAddressCache
    }

    private let backingPhoneNumber: AtomicValue<String?>
    @objc public var phoneNumber: String? {
        guard let phoneNumber = backingPhoneNumber.get() else {
            // If we weren't initialized with a phone number, but the phone number exists in the cache, use it
            guard let uuid = backingUuid.get(),
                let cachedPhoneNumber = SignalServiceAddress.cache.phoneNumber(forUuid: uuid)
            else {
                return nil
            }
            backingPhoneNumber.set(cachedPhoneNumber)
            return cachedPhoneNumber
        }

        return phoneNumber
    }

    // TODO UUID: eventually this can be not optional
    private let backingUuid: AtomicValue<UUID?>
    @objc public var uuid: UUID? {
        guard let uuid = backingUuid.get() else {
            // If we weren't initialized with a uuid, but the uuid exists in the cache, use it
            guard let phoneNumber = backingPhoneNumber.get(),
                let cachedUuid = SignalServiceAddress.cache.uuid(forPhoneNumber: phoneNumber)
            else {
                return nil
            }
            backingUuid.set(cachedUuid)
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
    public convenience init(uuid: UUID) {
        self.init(uuid: uuid, phoneNumber: nil)
    }

    @objc
    public init(uuid: UUID?, phoneNumber: String?) {
        if phoneNumber == nil, let uuid = uuid,
            let cachedPhoneNumber = SignalServiceAddress.cache.phoneNumber(forUuid: uuid) {
            backingPhoneNumber = AtomicValue(cachedPhoneNumber)
        } else {
            if let phoneNumber = phoneNumber, phoneNumber.isEmpty {
                owsFailDebug("Unexpectedly initialized signal service address with invalid phone number")
            }

            backingPhoneNumber = AtomicValue(phoneNumber)
        }

        if uuid == nil, let phoneNumber = phoneNumber,
            let cachedUuid = SignalServiceAddress.cache.uuid(forPhoneNumber: phoneNumber) {
            backingUuid = AtomicValue(cachedUuid)
        } else {
            backingUuid = AtomicValue(uuid)
        }

        // If we have a backing UUID, we don't want to cache its mapping to the phone number.
        // Instead, just lookup the hash based on the UUID alone.
        // Only SignalRecipient ever updates the UUID <-> phone number mapping.
        if let backingUuid = backingUuid.get() {
            backingHashValue = SignalServiceAddress.cache.hashAndCache(uuid: backingUuid)
        } else {
            backingHashValue = SignalServiceAddress.cache.hashAndCache(phoneNumber: backingPhoneNumber.get())
        }

        super.init()

        if !isValid {
            owsFailDebug("Unexpectedly initialized address with no identifier")
        }

        registerForMappingChangeNotification()
    }

    private func registerForMappingChangeNotification() {
        NotificationCenter.default.addObserver(
            self, selector:
            #selector(mappingDidChange),
            name: SignalServiceAddressCache.mappingDidChangeNotification,
            object: nil
        )
    }

    @objc
    func mappingDidChange(notification: Notification) {
        guard let backingUuid = backingUuid.get(),
            let updatedUuid = notification.userInfo?[SignalServiceAddressCache.mappingDidChangeNotificationUUIDKey] as? UUID,
            backingUuid == updatedUuid
            else { return }

        backingPhoneNumber.set(SignalServiceAddress.cache.phoneNumber(forUuid: backingUuid))
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
        aCoder.encode(backingUuid.get(), forKey: "backingUuid")

        // Only encode the backingPhoneNumber if we don't know the UUID
        aCoder.encode(backingUuid.get() == nil ? backingPhoneNumber.get() : nil, forKey: "backingPhoneNumber")
    }

    public required init?(coder aDecoder: NSCoder) {
        backingUuid = AtomicValue(aDecoder.decodeObject(of: NSUUID.self, forKey: "backingUuid") as UUID?)

        // Only decode the backingPhoneNumber if we don't know the UUID, otherwise
        // pull the phone number from the cache.
        if let backingUuid = backingUuid.get() {
            backingPhoneNumber = AtomicValue(SignalServiceAddress.cache.phoneNumber(forUuid: backingUuid))
        } else {
            backingPhoneNumber = AtomicValue(aDecoder.decodeObject(of: NSString.self, forKey: "backingPhoneNumber") as String?)
        }

        backingHashValue = SignalServiceAddress.cache.hashAndCache(uuid: backingUuid.get(), phoneNumber: backingPhoneNumber.get())
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
        if FeatureFlags.allowUUIDOnlyContacts,
            uuid != nil {
            guard let uuidString = uuidString else {
                owsFailDebug("uuidString was unexpectedly nil")
                return phoneNumber
            }

            return uuidString
        } else {
            guard let phoneNumber = phoneNumber else {
                if !CurrentAppContext().isRunningTests {
                    owsFailDebug("phoneNumber was unexpectedly nil")
                }
                return uuidString
            }

            return phoneNumber
        }
    }

    @objc
    override public var description: String {
        return "<SignalServiceAddress phoneNumber: \(phoneNumber ?? "nil"), uuid: \(uuid?.uuidString ?? "nil")>"
    }
}

@objc
public class SignalServiceAddressCache: NSObject {
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
    func hashAndCache(uuid: UUID? = nil, phoneNumber: String? = nil) -> Int {
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

    static let mappingDidChangeNotification = Notification.Name("SignalServiceAddressCacheMappingDidChange")
    static let mappingDidChangeNotificationUUIDKey = "mappingDidChangeNotificationUUIDKey"

    @objc
    func updateMapping(uuid: UUID, phoneNumber: String?) {
        serialQueue.sync {
            // Maintain the existing hash value for the given UUID, or create
            // a new hash if one is yet to exist.
            let hashValue: Int = {
                if let oldUUIDHashValue = uuidToHashValueCache[uuid] {
                    return oldUUIDHashValue
                } else if let oldPhoneNumber = uuidToPhoneNumberCache[uuid],
                    phoneNumberToUUIDCache[oldPhoneNumber] == nil,
                    let oldPhoneNumberHashValue = phoneNumberToHashValueCache[oldPhoneNumber] {
                    return oldPhoneNumberHashValue
                } else {
                    return UUID().hashValue
                }
            }()

            // If we previously had a phone number, disassociate it from the UUID
            if let oldPhoneNumber = uuidToPhoneNumberCache[uuid] {
                phoneNumberToHashValueCache[oldPhoneNumber] = nil
                phoneNumberToUUIDCache[oldPhoneNumber] = nil
            }

            // Map the uuid to the new phone number
            uuidToPhoneNumberCache[uuid] = phoneNumber
            uuidToHashValueCache[uuid] = hashValue

            if let phoneNumber = phoneNumber {
                // Unmap the previous UUID from this phone number
                if let oldUuid = phoneNumberToUUIDCache[phoneNumber] {
                    uuidToPhoneNumberCache[oldUuid] = nil
                }

                // Map the phone number to the new UUID
                phoneNumberToUUIDCache[phoneNumber] = uuid
                phoneNumberToHashValueCache[phoneNumber] = hashValue
            }
        }

        // Notify any existing address objects to update their backing phone number
        NotificationCenter.default.post(
            name: SignalServiceAddressCache.mappingDidChangeNotification,
            object: nil,
            userInfo: [SignalServiceAddressCache.mappingDidChangeNotificationUUIDKey: uuid]
        )
    }
}
