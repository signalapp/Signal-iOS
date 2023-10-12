//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

// MARK: -

@objc
public class SignalServiceAddress: NSObject, NSCopying, NSSecureCoding, Codable {
    private let cachedAddress: CachedAddress

    @objc
    public var phoneNumber: String? {
        cachedAddress.identifiers.get().phoneNumber
    }

    public var e164: E164? { phoneNumber.flatMap { E164($0) } }

    @objc
    public var e164ObjC: E164ObjC? { phoneNumber.flatMap { E164ObjC($0) } }

    /// The "service id" (could be an ACI or PNI).
    ///
    /// This value is optional since it may not be present in all cases. Some
    /// examples:
    ///
    /// * A really old recipient, who you may have message history with, may not
    /// have re-registered since UUIDs were added.
    ///
    /// * When doing "find by phone number", there will be a window of time
    /// where all we know about a recipient is their e164.
    public var serviceId: ServiceId? {
        cachedAddress.identifiers.get().serviceId
    }

    @objc
    public var serviceIdObjC: ServiceIdObjC? { serviceId.map { ServiceIdObjC.wrapValue($0) } }

    /// Returns the `serviceId` if it's an ACI.
    ///
    /// - Note: Call this only if you **expect** an `Aci` (or nil). If the
    /// result could be a `Pni`, you shouldn't call this method.
    public var aci: Aci? {
        guard let result = serviceId as? Aci? else {
            owsFailDebug("Expected an ACI but found something else.")
            return nil
        }
        return result
    }

    @objc
    public var aciString: String? { aci?.serviceIdString }

    @objc
    public var aciUppercaseString: String? { aci?.serviceIdUppercaseString }

    @objc
    public var serviceIdString: String? { serviceId?.serviceIdString }

    @objc
    public var serviceIdUppercaseString: String? { serviceId?.serviceIdUppercaseString }

    /// Returns a canonical address from the cache.
    ///
    /// If you initialize an address with the wrong phone number, that address
    /// will keep that phone number. This method will update that phone number
    /// to match what's currently in the cache (ie what's on SignalRecipient).
    public func withNormalizedPhoneNumber(cache: SignalServiceAddressCache? = nil) -> SignalServiceAddress {
        let identifiers = cachedAddress.identifiers.get()
        return SignalServiceAddress(
            serviceId: identifiers.serviceId,
            // If there's no ServiceId, then we look up the phone number in the cache.
            phoneNumber: (identifiers.serviceId == nil) ? identifiers.phoneNumber : nil,
            cache: cache ?? Self.signalServiceAddressCache,
            cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
        )
    }

    /// Returns a source-of-truth canonicalized address.
    ///
    /// If an address is initialized with the wrong phone number, it'll keep it
    /// until the phone number for the ACI changes; this method will update it
    /// immediately. If you initialize an address with a PNI, it'll keep the PNI
    /// forever; this method will update it to the ACI (but only if the ACI,
    /// PNI, and phone number are all known and linked to one another).
    public func withNormalizedPhoneNumberAndServiceId(cache: SignalServiceAddressCache? = nil) -> SignalServiceAddress {
        return withNormalizedPhoneNumber(cache: cache).withNormalizedServiceId(cache: cache)
    }

    private func withNormalizedServiceId(cache: SignalServiceAddressCache?) -> SignalServiceAddress {
        let identifiers = cachedAddress.identifiers.get()
        guard let phoneNumber = identifiers.phoneNumber, identifiers.serviceId is Pni else {
            // This is a private method, and `self` is already built against `cache`.
            return self
        }
        return SignalServiceAddress(
            serviceId: nil,
            phoneNumber: phoneNumber,
            cache: cache ?? Self.signalServiceAddressCache,
            cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
        )
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
        self.init(serviceId: nil, phoneNumber: phoneNumber)
    }

    /// Initializes an address that should refer to an Aci.
    ///
    /// - Note: Call this only if you **expect** an `Aci` in all cases. If the
    /// value might be a Pni, you shouldn't call this method.
    @objc
    public convenience init(aciString: String) {
        self.init(aciString: aciString, phoneNumber: nil)
    }

    /// Initializes an address that should refer to an Aci.
    ///
    /// - Note: Call this only if you **expect** an `Aci` (or nil) in all cases.
    /// If the value might be a Pni, you shouldn't call this method.
    @objc
    public convenience init(aciString: String?, phoneNumber: String?) {
        self.init(serviceIdString: aciString, allowPni: false, phoneNumber: phoneNumber)
    }

    /// Initializes an address for an Aci or Pni.
    ///
    /// - Warning: This method will only parse Pnis if
    /// `FeatureFlags.phoneNumberIdentifiers` is true.
    @objc
    public convenience init(serviceIdString: String) {
        self.init(serviceIdString: serviceIdString, allowPni: FeatureFlags.phoneNumberIdentifiers)
    }

    /// Initializes an address for an Aci or Pni.
    ///
    /// - Parameter allowPni: If false, PNIs will be treated as invalid.
    @objc
    public convenience init(serviceIdString: String, allowPni: Bool) {
        self.init(serviceIdString: serviceIdString, allowPni: allowPni, phoneNumber: nil)
    }

    /// Initializes an address for an Aci or Pni.
    ///
    /// - Warning: This method will only parse Pnis if
    /// `FeatureFlags.phoneNumberIdentifiers` is true.
    @objc
    public convenience init(serviceIdString: String?, phoneNumber: String?) {
        self.init(serviceIdString: serviceIdString, allowPni: FeatureFlags.phoneNumberIdentifiers, phoneNumber: phoneNumber)
    }

    /// Initializes an address for an Aci or Pni.
    ///
    /// - Parameter allowPni: If false, PNIs will be treated as invalid.
    @objc
    public convenience init(serviceIdString: String?, allowPni: Bool, phoneNumber: String?) {
        self.init(
            serviceId: serviceIdString.flatMap {
                let serviceId = try? ServiceId.parseFrom(serviceIdString: $0)
                if serviceId is Aci {
                    return serviceId
                }
                if serviceId is Pni, allowPni {
                    return serviceId
                }
                owsFailDebug("Unexpectedly initialized SignalServiceAddress with invalid serviceIdString.")
                return nil
            },
            phoneNumber: phoneNumber
        )
    }

    @objc
    public convenience init(serviceIdObjC: ServiceIdObjC) {
        self.init(serviceIdObjC.wrappedValue)
    }

    public convenience init(_ serviceId: ServiceId) {
        self.init(serviceId: serviceId, phoneNumber: nil)
    }

    public convenience init(serviceId: ServiceId?, e164: E164?) {
        self.init(serviceId: serviceId, phoneNumber: e164?.stringValue)
    }

    public convenience init(serviceId: ServiceId?, phoneNumber: String?) {
        self.init(serviceId: serviceId, phoneNumber: phoneNumber, ignoreCache: false)
    }

    internal convenience init(from address: ProtocolAddress) {
        self.init(address.serviceId)
    }

    private convenience init(decodedServiceId: ServiceId?, decodedPhoneNumber: String?) {
        self.init(
            serviceId: decodedServiceId,
            phoneNumber: decodedPhoneNumber,
            cache: Self.signalServiceAddressCache,
            // If we know the UUID, let the cache fill in the phone number when
            // possible. (This avoids decoding stale mappings that may exist.)
            cachePolicy: .preferCachedPhoneNumberAndListenForUpdates
        )
    }

    public convenience init(serviceId: ServiceId?, phoneNumber: String?, ignoreCache: Bool) {
        self.init(
            serviceId: serviceId,
            phoneNumber: phoneNumber,
            cache: Self.signalServiceAddressCache,
            cachePolicy: ignoreCache ? .ignoreCache : .preferInitialPhoneNumberAndListenForUpdates
        )
    }

    public init(
        serviceId: ServiceId?,
        phoneNumber: String?,
        cache: SignalServiceAddressCache,
        cachePolicy: SignalServiceAddressCache.CachePolicy
    ) {
        if let phoneNumber, phoneNumber.isEmpty {
            owsFailDebug("Unexpectedly initialized signal service address with invalid phone number")
        }

        self.cachedAddress = cache.registerAddress(
            proposedIdentifiers: CachedAddress.Identifiers(
                serviceId: serviceId,
                phoneNumber: phoneNumber
            ),
            cachePolicy: cachePolicy
        )

        super.init()

        if !isValid {
            owsFailDebug("Unexpectedly initialized address with no identifier")
        }
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case backingUuid, backingPhoneNumber
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let identifiers = cachedAddress.identifiers.get()
        try container.encode(identifiers.serviceId?.serviceIdUppercaseString, forKey: .backingUuid)
        // Only encode the backingPhoneNumber if we don't know the UUID
        try container.encode(identifiers.serviceId != nil ? nil : identifiers.phoneNumber, forKey: .backingPhoneNumber)
    }

    public required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedServiceId = try container.decodeIfPresent(String.self, forKey: .backingUuid).map {
            return try ServiceId.parseFrom(serviceIdString: $0)
        }
        let decodedPhoneNumber = try container.decodeIfPresent(String.self, forKey: .backingPhoneNumber)
        self.init(decodedServiceId: decodedServiceId, decodedPhoneNumber: decodedPhoneNumber)
    }

    // MARK: - NSSecureCoding

    public static let supportsSecureCoding: Bool = true

    public func encode(with aCoder: NSCoder) {
        let identifiers = cachedAddress.identifiers.get()
        aCoder.encode(identifiers.serviceId.map { serviceId -> Any in
            // For now, encode Acis in a backwards-compatible manner. This can be
            // changed in the future, but it will prevent downgrades.
            switch serviceId {
            case is Aci:
                return serviceId.rawUUID
            default:
                return Data(serviceId.serviceIdBinary)
            }
        }, forKey: "backingUuid")
        // Only encode the backingPhoneNumber if we don't know the UUID
        aCoder.encode(identifiers.serviceId != nil ? nil : identifiers.phoneNumber, forKey: "backingPhoneNumber")
    }

    public convenience required init?(coder aDecoder: NSCoder) {
        let decodedServiceId: ServiceId?
        switch aDecoder.decodeObject(of: [NSUUID.self, NSData.self], forKey: "backingUuid") {
        case nil:
            decodedServiceId = nil
        case let serviceIdBinary as Data:
            do {
                decodedServiceId = try ServiceId.parseFrom(serviceIdBinary: serviceIdBinary)
            } catch {
                owsFailDebug("Couldn't parse serviceIdBinary.")
                return nil
            }
        case let deprecatedUuid as NSUUID:
            decodedServiceId = Aci(fromUUID: deprecatedUuid as UUID)
        default:
            return nil
        }
        let decodedPhoneNumber = aDecoder.decodeObject(of: NSString.self, forKey: "backingPhoneNumber") as String?
        self.init(decodedServiceId: decodedServiceId, decodedPhoneNumber: decodedPhoneNumber)
    }

    // MARK: -

    @objc
    public func copy(with zone: NSZone? = nil) -> Any { return self }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let otherAddress = object as? SignalServiceAddress else {
            return false
        }

        let result = isEqualToAddress(otherAddress)
        if result, cachedAddress.hashValue != otherAddress.cachedAddress.hashValue {
            Logger.warn("Equal addresses have different hashes: \(self), other: \(otherAddress).")
        }
        return result
    }

    @objc
    public func isEqualToAddress(_ otherAddress: SignalServiceAddress?) -> Bool {
        guard let otherAddress else {
            return false
        }

        let this = cachedAddress.identifiers.get()
        let other = otherAddress.cachedAddress.identifiers.get()

        if let thisServiceId = this.serviceId, let otherServiceId = other.serviceId {
            return thisServiceId == otherServiceId
        }
        if let thisPhoneNumber = this.phoneNumber, let otherPhoneNumber = other.phoneNumber {
            return thisPhoneNumber == otherPhoneNumber
        }
        return false
    }

    // In order to maintain a consistent hash, we use a constant value generated
    // by the cache that can be mapped back to the phone number OR the UUID.
    //
    // This allows us to dynamically update the backing values to maintain
    // the most complete address object as we learn phone <-> UUID mapping,
    // while also allowing addresses to live in hash tables.
    public override var hash: Int { return cachedAddress.hashValue }

    @objc
    public func compare(_ otherAddress: SignalServiceAddress) -> ComparisonResult {
        return stringForDisplay.compare(otherAddress.stringForDisplay)
    }

    // MARK: -

    @objc
    public var isValid: Bool {
        let identifiers = cachedAddress.identifiers.get()

        if identifiers.serviceId != nil {
            return true
        }

        if let phoneNumber = identifiers.phoneNumber {
            return !phoneNumber.isEmpty
        }

        return false
    }

    @objc
    public var isLocalAddress: Bool {
        return DependenciesBridge.shared.tsAccountManager.localIdentifiersWithMaybeSneakyTransaction?.aciAddress == self
    }

    @objc
    public var stringForDisplay: String {
        let identifiers = cachedAddress.identifiers.get()

        if let phoneNumber = identifiers.phoneNumber {
            return phoneNumber
        } else if let serviceId = identifiers.serviceId {
            return serviceId.serviceIdUppercaseString
        }

        owsFailDebug("unexpectedly have no backing value")

        return ""
    }

    @objc
    public var serviceIdentifier: String? {
        let identifiers = cachedAddress.identifiers.get()

        if let serviceId = identifiers.serviceId {
            return serviceId.serviceIdUppercaseString
        }
        if let phoneNumber = identifiers.phoneNumber {
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
        let identifiers = cachedAddress.identifiers.get()
        return Self.addressComponentsDescription(
            uuidString: identifiers.serviceId?.logString,
            phoneNumber: identifiers.phoneNumber
        )
    }

    public static func addressComponentsDescription(uuidString: String?, phoneNumber: String?) -> String {
        var splits = [String]()
        if let uuid = uuidString?.nilIfEmpty {
            splits.append("serviceId: " + uuid)
        }
        if let phoneNumber = phoneNumber?.nilIfEmpty {
            splits.append("phoneNumber: " + phoneNumber)
        }
        return "<" + splits.joined(separator: ", ") + ">"
    }
}

// MARK: -

public extension Array where Element == SignalServiceAddress {
    func stableSort() -> [SignalServiceAddress] {
        // Use an arbitrary sort but ensure the ordering is stable.
        self.sorted { $0.sortKey < $1.sortKey }
    }
}

// MARK: -

private class CachedAddress {
    struct Identifiers: Equatable {
        var serviceId: ServiceId?
        var phoneNumber: String?
    }

    let hashValue: Int

    let identifiers: AtomicValue<Identifiers>

    init(hashValue: Int, identifiers: Identifiers) {
        self.hashValue = hashValue
        self.identifiers = AtomicValue(identifiers, lock: AtomicLock())
    }
}

@objc
public class SignalServiceAddressCache: NSObject {
    private let state = AtomicValue(CacheState(), lock: AtomicLock())

    private struct CacheState {
        var serviceIdHashValues = [ServiceId: Int]()
        var phoneNumberHashValues = [String: Int]()

        var serviceIdToPhoneNumber = [ServiceId: String]()
        var phoneNumberToServiceIds = [String: [ServiceId]]()

        var serviceIdCachedAddresses = [ServiceId: [CachedAddress]]()
        var phoneNumberOnlyCachedAddresses = [String: [CachedAddress]]()
    }

    @objc
    func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        databaseStorage.read { transaction in
            SignalRecipient.anyEnumerate(transaction: transaction) { recipient, _ in
                self.updateRecipient(recipient)
            }
        }
    }

    func updateRecipient(_ signalRecipient: SignalRecipient) {
        updateRecipient(
            aci: signalRecipient.aci,
            pni: signalRecipient.pni,
            phoneNumber: signalRecipient.phoneNumber
        )
    }

    private func updateRecipient(aci: Aci?, pni: Pni?, phoneNumber: String?) {
        state.update { cacheState in
            // This cache associates phone numbers to the other identifiers. If we
            // don't have a phone number, there's nothing to associate.
            //
            // We never remove a phone number from one recipient without *also* adding
            // it to some other recipient; therefore, we handle the transfer when that
            // recipient is passed to this method. (This avoids a potential problem
            // that could occur if we learn about the "delete" after the "update".)
            guard let phoneNumber else {
                return
            }

            let oldServiceIds: [ServiceId] = cacheState.phoneNumberToServiceIds[phoneNumber] ?? []
            let newServiceIds: [ServiceId] = [aci, pni].compacted()

            // If this phone number still points at the same ServiceIds, there's
            // nothing to change.
            guard newServiceIds != oldServiceIds else {
                return
            }

            cacheState.phoneNumberToServiceIds[phoneNumber] = newServiceIds

            // These ServiceIds are no longer associated with `phoneNumber`.
            for serviceId in Set(oldServiceIds).subtracting(newServiceIds) {
                cacheState.serviceIdToPhoneNumber[serviceId] = nil
                cacheState.serviceIdCachedAddresses[serviceId]?.forEach { cachedAddress in
                    cachedAddress.identifiers.update { $0.phoneNumber = nil }
                }
            }

            // These ServiceIds are now associated with `phoneNumber`.
            for serviceId in Set(newServiceIds).subtracting(oldServiceIds) {
                let oldPhoneNumber = cacheState.serviceIdToPhoneNumber.updateValue(phoneNumber, forKey: serviceId)
                cacheState.serviceIdCachedAddresses[serviceId]?.forEach { cachedAddress in
                    cachedAddress.identifiers.update { $0.phoneNumber = phoneNumber }
                }

                // If this ServiceId was associated with some other phone number, we need
                // to break that association.
                if let oldPhoneNumber {
                    owsAssertDebug(oldPhoneNumber != phoneNumber)
                    cacheState.phoneNumberToServiceIds[oldPhoneNumber]?.removeAll(where: { $0 == serviceId })
                }

                // This might be the first time we're learning about this ServiceId or
                // phone number. If a preferred hash value is available, make sure all
                // future SignalServiceAddress instances will be able to find it.
                _ = hashValue(cacheState: &cacheState, serviceId: serviceId, phoneNumber: phoneNumber)
            }

            // If we're adding a ServiceId to this recipient for the first time, we may
            // have some addresses with only a phone number. We should add the "best"
            // ServiceId available to those addresses. Once we add a ServiceId, though,
            // that value is "sticky" and won't be changed if we get an even better
            // identifier in the future. This maintains the existing (very useful)
            // invariant that a nonnil UUID for a SignalServiceAddress remains stable.
            if let preferredServiceId = newServiceIds.first {
                cacheState.phoneNumberOnlyCachedAddresses.removeValue(forKey: phoneNumber)?.forEach { cachedAddress in
                    cachedAddress.identifiers.update { $0.serviceId = preferredServiceId }
                    // This address has a serviceId now -- track that serviceId for future updates.
                    cacheState.serviceIdCachedAddresses[preferredServiceId, default: []].append(cachedAddress)
                }
            }
        }
    }

    public enum CachePolicy {
        /// Prefers a nonnil phone number from the initializer. This is useful in
        /// cases where the initializer has more recent mappings than what's
        /// available in the cache. If the phone number changes in the future, the
        /// address will be dynamically updated.
        case preferInitialPhoneNumberAndListenForUpdates

        /// Prefers a nonnil phone number from the cache. This handles cases where
        /// "stale" data may be provided in the initializer. If the phone number
        /// changes in the future, the address will be dynamically updated.
        case preferCachedPhoneNumberAndListenForUpdates

        /// Never retrieves either value from the cache. Never updated when a new
        /// mapping is learned. The hash value *is* retrieved from the "cache".
        /// These addresses shouldn't be put in a Set or used as Dictionary keys.
        case ignoreCache
    }

    fileprivate func registerAddress(proposedIdentifiers: CachedAddress.Identifiers, cachePolicy: CachePolicy) -> CachedAddress {
        state.update { cacheState in
            let resolvedIdentifiers: CachedAddress.Identifiers
            switch cachePolicy {
            case .ignoreCache:
                resolvedIdentifiers = proposedIdentifiers
            case .preferInitialPhoneNumberAndListenForUpdates:
                resolvedIdentifiers = resolveIdentifiers(proposedIdentifiers, preferInitialPhoneNumber: true, cacheState: cacheState)
            case .preferCachedPhoneNumberAndListenForUpdates:
                resolvedIdentifiers = resolveIdentifiers(proposedIdentifiers, preferInitialPhoneNumber: false, cacheState: cacheState)
            }

            // We try our best to share hash values for ServiceIds and phone numbers
            // that might be associated with one another.
            let hashValue = hashValue(
                cacheState: &cacheState,
                serviceId: resolvedIdentifiers.serviceId,
                phoneNumber: resolvedIdentifiers.phoneNumber
            )

            func getOrCreateCachedAddress<T>(key: T, in cachedAddresses: inout [T: [CachedAddress]]) -> CachedAddress {
                for cachedAddress in cachedAddresses[key, default: []] {
                    if cachedAddress.hashValue == hashValue && cachedAddress.identifiers.get() == resolvedIdentifiers {
                        return cachedAddress
                    }
                }
                let result = CachedAddress(hashValue: hashValue, identifiers: resolvedIdentifiers)
                cachedAddresses[key, default: []].append(result)
                return result
            }

            switch cachePolicy {
            case .preferInitialPhoneNumberAndListenForUpdates, .preferCachedPhoneNumberAndListenForUpdates:
                if let serviceId = resolvedIdentifiers.serviceId {
                    return getOrCreateCachedAddress(key: serviceId, in: &cacheState.serviceIdCachedAddresses)
                }
                if let phoneNumber = resolvedIdentifiers.phoneNumber {
                    return getOrCreateCachedAddress(key: phoneNumber, in: &cacheState.phoneNumberOnlyCachedAddresses)
                }
                fallthrough
            case .ignoreCache:
                return CachedAddress(hashValue: hashValue, identifiers: resolvedIdentifiers)
            }
        }
    }

    /// Populates missing/stale identifiers populated from the cache.
    ///
    /// - Parameter preferInitialPhoneNumber: If true, the phone number value
    /// from `proposedIdentifiers` will be used if it's nonnil; if it's nil, the
    /// value from the cache will be used. If false, the phone number value from
    /// the cache will be used if it's nonnil; if it's nil, the value from
    /// `proposedIdentifiers` will be used.
    private func resolveIdentifiers(
        _ proposedIdentifiers: CachedAddress.Identifiers,
        preferInitialPhoneNumber: Bool,
        cacheState: CacheState
    ) -> CachedAddress.Identifiers {
        CachedAddress.Identifiers(
            serviceId: (
                // We *always* prefer the provided serviceId.
                proposedIdentifiers.serviceId
                ?? proposedIdentifiers.phoneNumber.flatMap { cacheState.phoneNumberToServiceIds[$0]?.first }
            ),
            phoneNumber: preferInitialPhoneNumber ? (
                proposedIdentifiers.phoneNumber
                ?? proposedIdentifiers.serviceId.flatMap { cacheState.serviceIdToPhoneNumber[$0] }
            ) : (
                proposedIdentifiers.serviceId.flatMap { cacheState.serviceIdToPhoneNumber[$0] }
                ?? proposedIdentifiers.phoneNumber
            )
        )
    }

    /// Finds the best hash value for (serviceId, phoneNumber).
    ///
    /// In general, we'll return an existing hash value if one exists, and we'll
    /// generate a new random hash value if one doesn't exist. If we generate a
    /// random hash value, we associate it with the provided identifier(s) for
    /// future calls to this method.
    ///
    /// Some edge cases worth documenting explicitly:
    ///
    /// - If both identifiers are nonnil and have different hash values, the
    /// hash value for `serviceId` will be returned. The hash value for
    /// `phoneNumber` won't be updated for future calls to this method.
    ///
    /// - If both identifiers are nonnil and only one of them has a hash value,
    /// that value will be returned. The returned hash value will also be
    /// associated with the other identifier for future calls to this method.
    ///
    /// - If both identifiers are nil, this method is equivalent to
    /// `Int.random(in: Int.min...Int.max)`. An address must have at least one
    /// identifier to be considered valid, and addresses without identifiers
    /// always return `false` from `isEqual:`, so it's perfectly acceptable for
    /// each of these addresses to have its own hash value.
    private func hashValue(cacheState: inout CacheState, serviceId: ServiceId?, phoneNumber: String?) -> Int {
        let hashValue = (
            serviceId.flatMap { cacheState.serviceIdHashValues[$0] }
            ?? phoneNumber.flatMap { cacheState.phoneNumberHashValues[$0] }
            ?? Int.random(in: Int.min...Int.max)
        )
        // We *never* change a hash value once it's been generated.
        if let serviceId, cacheState.serviceIdHashValues[serviceId] == nil {
            cacheState.serviceIdHashValues[serviceId] = hashValue
        }
        if let phoneNumber, cacheState.phoneNumberHashValues[phoneNumber] == nil {
            cacheState.phoneNumberHashValues[phoneNumber] = hashValue
        }
        return hashValue
    }
}

// MARK: - Unit Tests

#if TESTABLE_BUILD

extension SignalServiceAddress {
    static func randomForTesting() -> SignalServiceAddress { SignalServiceAddress(Aci.randomForTesting()) }

    static func isolatedRandomForTesting() -> SignalServiceAddress {
        SignalServiceAddress(
            serviceId: Aci.randomForTesting(),
            phoneNumber: nil,
            cache: SignalServiceAddressCache(),
            cachePolicy: .ignoreCache
        )
    }
}

extension SignalServiceAddressCache {
    func makeAddress(serviceId: ServiceId?, phoneNumber: E164?) -> SignalServiceAddress {
        SignalServiceAddress(
            serviceId: serviceId,
            phoneNumber: phoneNumber?.stringValue,
            cache: self,
            cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
        )
    }
}

#endif
