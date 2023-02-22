//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

@objc
public class SignalServiceAddress: NSObject, NSCopying, NSSecureCoding, Codable {
    public static let supportsSecureCoding: Bool = true

    private static var cache: SignalServiceAddressCache {
        return Self.signalServiceAddressCache
    }

    private static var propertyLock: UnfairLock = UnfairLock()

    private var backingPhoneNumberUnsynchronized: String?
    @objc
    public var phoneNumber: String? {
        guard let phoneNumber = Self.propertyLock.withLock({backingPhoneNumberUnsynchronized}) else {
            // If we weren't initialized with a phone number, but the phone number exists in the cache, use it
            guard let uuid = Self.propertyLock.withLock({backingUuidUnsynchronized}),
                let cachedPhoneNumber = SignalServiceAddress.cache.phoneNumber(forUuid: uuid)
            else {
                return nil
            }
            Self.propertyLock.withLock {
                backingPhoneNumberUnsynchronized = cachedPhoneNumber
            }
            return cachedPhoneNumber
        }

        return phoneNumber
    }

    public var e164: E164? { phoneNumber.flatMap { E164($0) } }

    @objc
    public var e164ObjC: E164ObjC? { phoneNumber.flatMap { E164ObjC($0) } }

    /// Optional, since while in *most* cases we can be sure this is present
    /// we cannot be positive. Some examples:
    ///
    /// * A really old recipient, who you may have message history with, may not have re-registered since UUIDs were added.
    /// * When doing "find by phone number", there will be a window of time where all we know about a recipient is their e164.
    /// * Syncing from another device via Storage Service could have an e164-only contact record.
    @objc
    public var uuid: UUID? {
        guard let uuid = Self.propertyLock.withLock({backingUuidUnsynchronized}) else {
            // If we weren't initialized with a uuid, but the uuid exists in the cache, use it
            guard let phoneNumber = Self.propertyLock.withLock({backingPhoneNumberUnsynchronized}),
                let cachedUuid = SignalServiceAddress.cache.uuid(forPhoneNumber: phoneNumber)
            else {
                return nil
            }
            Self.propertyLock.withLock {
                backingUuidUnsynchronized = cachedUuid
            }
            observeMappingChanges(forUuid: cachedUuid)
            return cachedUuid
        }

        return uuid
    }
    private var backingUuidUnsynchronized: UUID?

    public var serviceId: ServiceId? { uuid.map { ServiceId($0) } }

    @objc
    public var serviceIdObjC: ServiceIdObjC? { uuid.map { ServiceIdObjC(uuidValue: $0) } }

    @objc
    public var uuidString: String? {
        return uuid?.uuidString
    }

    // MARK: - Initializers

    @objc
    public convenience init(e164ObjC: E164ObjC) {
        self.init(e164ObjC.wrappedValue)
    }

    public convenience init(_ e164: E164) {
        self.init(phoneNumber: e164.stringValue)
    }

    @objc
    public convenience init(phoneNumber: String) {
        self.init(uuidString: nil, phoneNumber: phoneNumber)
    }

    @objc
    public convenience init(uuidString: String) {
        self.init(uuidString: uuidString, phoneNumber: nil)
    }

    @objc
    public convenience init(serviceIdObjC: ServiceIdObjC) {
        self.init(serviceIdObjC.wrappedValue)
    }

    public convenience init(_ serviceId: ServiceId) {
        self.init(uuid: serviceId.uuidValue)
    }

    @objc
    public convenience init(uuid: UUID) {
        self.init(uuid: uuid, phoneNumber: nil)
    }

    @objc
    public convenience init(uuidString: String?, phoneNumber: String?) {
        self.init(uuidString: uuidString, phoneNumber: phoneNumber, trustLevel: .low)
    }

    @objc
    public convenience init(uuidString: String?, phoneNumber: String?, trustLevel: SignalRecipientTrustLevel) {
        let uuid: UUID?

        if let uuidString = uuidString {
            uuid = UUID(uuidString: uuidString)
            if uuid == nil {
                owsFailDebug("Unexpectedly initialized signal service address with invalid uuid")
            }
        } else {
            uuid = nil
        }

        self.init(uuid: uuid, phoneNumber: phoneNumber, trustLevel: trustLevel)
    }

    @objc
    public convenience init(uuid: UUID?, phoneNumber: String?) {
        self.init(uuid: uuid, phoneNumber: phoneNumber, trustLevel: .low)
    }

    internal convenience init(from address: ProtocolAddress) {
        if let uuid = UUID(uuidString: address.name) {
            self.init(uuid: uuid)
        } else {
            // FIXME: What happens if this is *not* a valid phone number?
            self.init(phoneNumber: address.name)
        }
    }

    @objc
    public init(uuid: UUID?, phoneNumber: String?, trustLevel: SignalRecipientTrustLevel) {
        if let phoneNumber {
            if phoneNumber.isEmpty {
                owsFailDebug("Unexpectedly initialized signal service address with invalid phone number")
            }
            backingPhoneNumberUnsynchronized = phoneNumber
        } else if let uuid, let cachedPhoneNumber = SignalServiceAddress.cache.phoneNumber(forUuid: uuid) {
            backingPhoneNumberUnsynchronized = cachedPhoneNumber
        }

        if let uuid {
            backingUuidUnsynchronized = uuid
        } else if let phoneNumber, let cachedUuid = SignalServiceAddress.cache.uuid(forPhoneNumber: phoneNumber) {
            backingUuidUnsynchronized = cachedUuid
        }

        backingHashValue = SignalServiceAddress.cache.hashAndCache(
            uuid: backingUuidUnsynchronized,
            phoneNumber: backingPhoneNumberUnsynchronized,
            trustLevel: trustLevel
        )

        super.init()

        if !isValid {
            owsFailDebug("Unexpectedly initialized address with no identifier")
        }

        if let backingUuid = backingUuidUnsynchronized {
            observeMappingChanges(forUuid: backingUuid)
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case backingUuid, backingPhoneNumber
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let (backingUuid, backingPhoneNumber) = Self.propertyLock.withLock {
            (backingUuidUnsynchronized, backingPhoneNumberUnsynchronized)
        }
        try container.encode(backingUuid, forKey: .backingUuid)
        // Only encode the backingPhoneNumber if we don't know the UUID
        try container.encode(backingUuid == nil ? backingPhoneNumber : nil, forKey: .backingPhoneNumber)
    }

    public required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let uuid: UUID? = try container.decodeIfPresent(UUID.self, forKey: .backingUuid)

        let phoneNumber: String?
        if let decodedPhoneNumber = try container.decodeIfPresent(String.self, forKey: .backingPhoneNumber) {
            // If we know the uuid, always rely on the cached phone number
            // and discard any decoded phone number that may relate to a
            // stale mapping.
            if let uuid = uuid, let cachedPhoneNumber = SignalServiceAddress.cache.phoneNumber(forUuid: uuid) {
                phoneNumber = cachedPhoneNumber
            } else {
                phoneNumber = decodedPhoneNumber
            }
        } else {
            phoneNumber = nil
        }

        self.init(uuid: uuid, phoneNumber: phoneNumber, trustLevel: .low)
    }

    // MARK: - NSSecureCoding

    public func encode(with aCoder: NSCoder) {
        let (backingUuid, backingPhoneNumber) = Self.propertyLock.withLock {
            (backingUuidUnsynchronized, backingPhoneNumberUnsynchronized)
        }
        aCoder.encode(backingUuid, forKey: "backingUuid")

        // Only encode the backingPhoneNumber if we don't know the UUID
        aCoder.encode(backingUuid == nil ? backingPhoneNumber : nil, forKey: "backingPhoneNumber")
    }

    public convenience required init?(coder aDecoder: NSCoder) {
        let uuid = aDecoder.decodeObject(of: NSUUID.self, forKey: "backingUuid") as UUID?

        let phoneNumber: String?
        if let decodedPhoneNumber = aDecoder.decodeObject(of: NSString.self, forKey: "backingPhoneNumber") as String? {
            // If we know the uuid, always rely on the cached phone number
            // and discard any decoded phone number that may relate to a
            // stale mapping.
            if let uuid = uuid, let cachedPhoneNumber = SignalServiceAddress.cache.phoneNumber(forUuid: uuid) {
                phoneNumber = cachedPhoneNumber
            } else {
                phoneNumber = decodedPhoneNumber
            }
        } else {
            phoneNumber = nil
        }

        self.init(uuid: uuid, phoneNumber: phoneNumber, trustLevel: .low)
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

        if let thisUuid = uuid,
            let otherUuid = otherAddress.uuid {
            let isEqual = thisUuid == otherUuid
            if isEqual, self.hash != otherAddress.hash {
                Logger.warn("Equal addresses have different hashes: \(self), other: \(otherAddress).")
            }
            return isEqual
        }
        if phoneNumber != nil ||
            otherAddress.phoneNumber != nil {
            let isEqual = otherAddress.phoneNumber == phoneNumber
            if isEqual, self.hash != otherAddress.hash {
                Logger.warn("Equal addresses have different hashes: \(self), other: \(otherAddress).")
            }
            return isEqual
        }
        return false
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
        if let uuid = uuid {
            return uuid.uuidString
        }
        if let phoneNumber = phoneNumber {
            return phoneNumber
        }
        if !CurrentAppContext().isRunningTests {
            owsFailDebug("phoneNumber was unexpectedly nil")
        }
        return nil
    }

    @objc
    public var sortKey: String {
        guard let serviceIdentifier = serviceIdentifier else {
            owsFailDebug("Invalid address.")
            return "Invalid"
        }
        return serviceIdentifier
    }

    @objc
    override public var description: String {
        return "<SignalServiceAddress phoneNumber: \(phoneNumber ?? "nil"), uuid: \(uuid?.uuidString ?? "nil")>"
    }

    // MARK: - Mapping Changes

    // The "observer" is a weak array of addresses with the
    // same UUID observing changes to that UUID.
    private typealias AddressMappingObserver = NSHashTable<SignalServiceAddress>

    // Every address retains a strong reference to its observer.
    private var mappingObserverUnsynchronized: AddressMappingObserver?

    private static let observerLock = UnfairLock()
    private static let mappingObserverCache = NSMapTable<NSUUID, AddressMappingObserver>(keyOptions: .strongMemory,
                                                                                         valueOptions: .weakMemory)

    private func observeMappingChanges(forUuid uuid: UUID) {
        let needsObserver: Bool = Self.propertyLock.withLock {
            owsAssertDebug(backingUuidUnsynchronized == uuid)

            guard mappingObserverUnsynchronized == nil else {
                owsFailDebug("There's shouldn't be an existing observer.")
                return false
            }
            return true
        }
        guard needsObserver else {
            return
        }

        let observer = Self.observerLock.withLock { () -> AddressMappingObserver in
            let observer = { () -> AddressMappingObserver in
                if let observer = Self.mappingObserverCache.object(forKey: uuid as NSUUID) {
                    return observer
                } else {
                    // * Use weak references to addresses.
                    // * Use .objectPointerPersonality; this NSHashTable will contain
                    //   a list of addresses that are all "equal".
                    let observer = NSHashTable<SignalServiceAddress>(options: [
                        .weakMemory,
                        .objectPointerPersonality
                    ])
                    Self.mappingObserverCache.setObject(observer, forKey: uuid as NSUUID)
                    return observer
                }
            }()
            observer.add(self)
            return observer
        }
        // We could race in this method, but in practice it should never happen.
        // If it did, it wouldn't have any adverse side effects.
        Self.propertyLock.withLock {
            owsAssertDebug(mappingObserverUnsynchronized == nil)
            mappingObserverUnsynchronized = observer
        }
    }

    fileprivate static func notifyMappingDidChange(forUuid uuid: UUID, toPhoneNumber phoneNumber: String?) {
        guard let addresses = (Self.observerLock.withLock { () -> [SignalServiceAddress]? in
            guard let observer = Self.mappingObserverCache.object(forKey: uuid as NSUUID) else {
                return nil
            }
            return observer.allObjects
        }) else {
            return
        }
        for address in addresses {
            address.mappingDidChange(forUuid: uuid, toPhoneNumber: phoneNumber)
        }
    }

    fileprivate func mappingDidChange(forUuid uuid: UUID, toPhoneNumber phoneNumber: String?) {
        Self.propertyLock.withLock {
            owsAssertDebug(uuid == backingUuidUnsynchronized)
            backingPhoneNumberUnsynchronized = phoneNumber
        }
    }

    public static func addressComponentsDescription(uuidString: String?,
                                                    phoneNumber: String?) -> String {
        var splits = [String]()
        if let uuid = uuidString?.nilIfEmpty {
            splits.append("uuid: " + uuid)
        }
        if let phoneNumber = phoneNumber?.nilIfEmpty {
            splits.append("phoneNumber: " + phoneNumber)
        }
        if let uuid = uuidString?.nilIfEmpty,
           tsAccountManager.localUuid?.uuidString == uuid {
            splits.append("*local address")
        }
        return "[" + splits.joined(separator: ", ") + "]"
    }
}

// MARK: -

#if TESTABLE_BUILD

extension SignalServiceAddress {
    var unresolvedUuid: UUID? {
        Self.propertyLock.withLock({backingUuidUnsynchronized})
    }

    var unresolvedPhoneNumber: String? {
        Self.propertyLock.withLock({backingPhoneNumberUnsynchronized})
    }
}

#endif

// MARK: -

public extension Array where Element == SignalServiceAddress {
    func stableSort() -> [SignalServiceAddress] {
        // Use an arbitrary sort but ensure the ordering is stable.
        self.sorted { (left, right) in
            left.sortKey < right.sortKey
        }
    }
}

// MARK: -

@objc
public class SignalServiceAddressCache: NSObject {
    private static let unfairLock = UnfairLock()

    private var uuidToPhoneNumberCache = [UUID: String]()
    private var phoneNumberToUUIDCache = [String: UUID]()

    private var uuidToHashValueCache = [UUID: Int]()
    private var phoneNumberToHashValueCache = [String: Int]()

    @objc
    func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        let localNumber = TSAccountManager.shared.localNumber
        let localUuid = TSAccountManager.shared.localUuid

        if localNumber != nil || localUuid != nil {
            hashAndCache(uuid: localUuid, phoneNumber: localNumber, trustLevel: .high)
        }

        SDSDatabaseStorage.shared.read { transaction in
            SignalRecipient.anyEnumerate(transaction: transaction) { recipient, _ in
                let recipientUuid: UUID?
                if let uuidString = recipient.recipientUUID {
                    recipientUuid = UUID(uuidString: uuidString)
                } else {
                    recipientUuid = nil
                }
                self.hashAndCache(uuid: recipientUuid, phoneNumber: recipient.recipientPhoneNumber, trustLevel: .high)
            }
        }

        if DebugFlags.internalLogging {
            Logger.info("uuidToPhoneNumberCache: \(uuidToPhoneNumberCache.count), phoneNumberToUUIDCache: \(phoneNumberToUUIDCache.count), uuidToHashValueCache: \(uuidToHashValueCache.count), phoneNumberToHashValueCache: \(phoneNumberToHashValueCache.count), ")
        }
    }

    /// Adds a uuid <-> phone number mapping to the cache (if necessary)
    /// and returns a constant hash value that can be used to represent
    /// either of these values going forward for the lifetime of the cache.
    @discardableResult
    func hashAndCache(uuid: UUID? = nil, phoneNumber: String? = nil, trustLevel: SignalRecipientTrustLevel) -> Int {
        var phoneNumber = phoneNumber

        // If we have a UUID, don't trust the phone number for mapping
        // in low trust scenarios.
        if trustLevel == .low, uuid != nil { phoneNumber = nil }

        return Self.unfairLock.withLock {

            // Generate or fetch the unique hash value for this address.

            let hash: Int = {
                // If we already have a hash for the UUID, use it.
                if let uuid = uuid, let uuidHash = uuidToHashValueCache[uuid] {
                    return uuidHash
                // Otherwise, if we already have a hash for the phone number, use it
                // unless we are moving a phone number from one uuid to another.
                } else if let phoneNumber = phoneNumber,
                          (phoneNumberToUUIDCache[phoneNumber] == nil ||
                           phoneNumberToUUIDCache[phoneNumber] == uuid),
                            let phoneNumberHash = phoneNumberToHashValueCache[phoneNumber] {
                    return phoneNumberHash

                // Else, create a fresh hash that will be used going forward.
                } else {
                    return UUID().hashValue
                }
            }()

            // If we have a UUID and a phone number, cache the mapping.
            if let uuid = uuid, let phoneNumber = phoneNumber {

                // If we previously had a phone number, disassociate it from the UUID.
                if let oldPhoneNumber = uuidToPhoneNumberCache[uuid],
                   oldPhoneNumber != phoneNumber {
                    phoneNumberToUUIDCache[oldPhoneNumber] = nil
                }

                // If we previously had a UUID, disassociate it from the phone number.
                if let oldUuid = phoneNumberToUUIDCache[phoneNumber],
                   oldUuid != uuid {
                    uuidToPhoneNumberCache[oldUuid] = nil
                }

                uuidToPhoneNumberCache[uuid] = phoneNumber
                phoneNumberToUUIDCache[phoneNumber] = uuid
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
        Self.unfairLock.withLock { phoneNumberToUUIDCache[phoneNumber] }
    }

    func phoneNumber(forUuid uuid: UUID) -> String? {
        Self.unfairLock.withLock { uuidToPhoneNumberCache[uuid] }
    }

    @objc
    func removeMapping(phoneNumber: String) {

        Logger.info("phoneNumber: \(phoneNumber)")

        Self.unfairLock.withLock {
            // If we previously had a UUID, disassociate it from the phone number.
            if let oldUuid = phoneNumberToUUIDCache[phoneNumber] {
                uuidToPhoneNumberCache[oldUuid] = nil
            }

            phoneNumberToUUIDCache[phoneNumber] = nil
        }
    }

    @objc
    @discardableResult
    func updateMapping(uuid: UUID, phoneNumber: String?, transaction: SDSAnyWriteTransaction) -> SignalServiceAddress {

        Logger.info("phoneNumber: \(String(describing: phoneNumber)), uuid: \(uuid)")

        Self.unfairLock.withLock {
            // Maintain the existing hash value for the given UUID, or create
            // a new hash if one is yet to exist.
            let hashValue: Int = {
                // If we already have a hash for the UUID, use it.
                if let oldUUIDHashValue = uuidToHashValueCache[uuid] {
                    return oldUUIDHashValue
                } else if let oldPhoneNumber = uuidToPhoneNumberCache[uuid],
                    phoneNumberToUUIDCache[oldPhoneNumber] == nil,
                    let oldPhoneNumberHashValue = phoneNumberToHashValueCache[oldPhoneNumber] {
                    owsFailDebug("Unexpected mapping.")
                    return oldPhoneNumberHashValue
                } else {
                    return UUID().hashValue
                }
            }()

            // If we previously had a phone number, disassociate it from the UUID
            if let oldPhoneNumber = uuidToPhoneNumberCache[uuid] {
                phoneNumberToUUIDCache[oldPhoneNumber] = nil
            }

            // If we previously had a UUID, disassociate it from the phone number.
            if let phoneNumber, let oldUuid = phoneNumberToUUIDCache[phoneNumber], oldUuid != uuid {
                if uuidToHashValueCache[oldUuid] == hashValue {
                    owsFailDebug("Unexpectedly using hash for old uuid.")
                }
            }

            // Map the uuid to the new phone number
            uuidToPhoneNumberCache[uuid] = phoneNumber
            uuidToHashValueCache[uuid] = hashValue

            if let phoneNumber {
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
        SignalServiceAddress.notifyMappingDidChange(forUuid: uuid, toPhoneNumber: phoneNumber)

        transaction.addSyncCompletion {
            if AppReadiness.isAppReady {
                Self.bulkProfileFetch.fetchProfile(uuid: uuid)
            }
        }

        return SignalServiceAddress(uuid: uuid, phoneNumber: phoneNumber)
    }
}

public extension UUID {

    func asSignalServiceAddress() -> SignalServiceAddress {
        return SignalServiceAddress(uuid: self)
    }
}
