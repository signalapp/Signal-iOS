//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

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
            cache: cache ?? SSKEnvironment.shared.signalServiceAddressCacheRef
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
            cache: cache ?? SSKEnvironment.shared.signalServiceAddressCacheRef
        )
    }

    // MARK: - Initializers

    /// Initializes a "legacy" address.
    ///
    /// Legacy addresses were saved by prior versions of the application before
    /// ACIs were known, so they generally contain only a phone number. They are
    /// sent through a migration path that allows them to be resolved to ACIs in
    /// cases where other SignalServiceAddresses can't be resolved to ACIs.
    ///
    /// "Modern legacy addresses" (ie modern builds writing to places that may
    /// also contain legacy addresses) will encode the ACI instead of the phone
    /// number, thus skipping the migration path in this initializer (good!).
    public convenience init(
        serviceId: ServiceId?,
        legacyPhoneNumber phoneNumber: String?,
        cache: SignalServiceAddressCache
    ) {
        let normalizedAddress = NormalizedDatabaseRecordAddress(
            serviceId: serviceId,
            phoneNumber: phoneNumber
        )
        self.init(
            serviceId: normalizedAddress?.serviceId,
            phoneNumber: normalizedAddress?.phoneNumber,
            isLegacyPhoneNumber: true,
            cache: cache
        )
    }

    public static func legacyAddress(serviceId: ServiceId?, phoneNumber: String?) -> SignalServiceAddress {
        return SignalServiceAddress(
            serviceId: serviceId,
            legacyPhoneNumber: phoneNumber,
            cache: SSKEnvironment.shared.signalServiceAddressCacheRef
        )
    }

    public static func legacyAddress(aciString: String?, phoneNumber: String?) -> SignalServiceAddress {
        return SignalServiceAddress(
            serviceId: Aci.parseFrom(aciString: aciString),
            legacyPhoneNumber: phoneNumber,
            cache: SSKEnvironment.shared.signalServiceAddressCacheRef
        )
    }

    @objc
    public static func legacyAddress(serviceIdString: String?, phoneNumber: String?) -> SignalServiceAddress {
        return SignalServiceAddress(
            serviceId: serviceIdString.flatMap { try? ServiceId.parseFrom(serviceIdString: $0) },
            legacyPhoneNumber: phoneNumber,
            cache: SSKEnvironment.shared.signalServiceAddressCacheRef
        )
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
    @objc
    public convenience init(serviceIdString: String) {
        self.init(serviceIdString: serviceIdString, phoneNumber: nil)
    }

    /// Initializes an address for an Aci or Pni.
    @objc
    public convenience init(serviceIdString: String?, phoneNumber: String?) {
        self.init(serviceIdString: serviceIdString, allowPni: true, phoneNumber: phoneNumber)
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
        self.init(
            serviceId: serviceId,
            phoneNumber: phoneNumber,
            isLegacyPhoneNumber: false,
            cache: SSKEnvironment.shared.signalServiceAddressCacheRef
        )
    }

    internal convenience init(from address: ProtocolAddress) {
        self.init(address.serviceId)
    }

    public convenience init(
        serviceId: ServiceId?,
        phoneNumber: String?,
        cache: SignalServiceAddressCache
    ) {
        self.init(
            serviceId: serviceId,
            phoneNumber: phoneNumber,
            isLegacyPhoneNumber: false,
            cache: cache
        )
    }

    private init(
        serviceId: ServiceId?,
        phoneNumber: String?,
        isLegacyPhoneNumber: Bool,
        cache: SignalServiceAddressCache
    ) {
        if let phoneNumber, phoneNumber.isEmpty {
            owsFailDebug("Unexpectedly initialized signal service address with invalid phone number")
        }

        self.cachedAddress = cache.registerAddress(
            proposedIdentifiers: CachedAddress.Identifiers(
                serviceId: serviceId,
                phoneNumber: phoneNumber
            ),
            isLegacyPhoneNumber: isLegacyPhoneNumber
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
        self.init(
            serviceId: decodedServiceId,
            legacyPhoneNumber: decodedPhoneNumber,
            cache: SSKEnvironment.shared.signalServiceAddressCacheRef
        )
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
        self.init(
            serviceId: decodedServiceId,
            legacyPhoneNumber: decodedPhoneNumber,
            cache: SSKEnvironment.shared.signalServiceAddressCacheRef
        )
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
        } else if let phoneNumber = phoneNumber?.nilIfEmpty {
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
        self.identifiers = AtomicValue(identifiers, lock: .init())
    }
}

public class SignalServiceAddressCache: NSObject {
    private let state = AtomicValue(CacheState(), lock: .init())

    private let _phoneNumberVisibilityFetcher: PhoneNumberVisibilityFetcher?
    private var phoneNumberVisibilityFetcher: PhoneNumberVisibilityFetcher {
        return _phoneNumberVisibilityFetcher ?? DependenciesBridge.shared.phoneNumberVisibilityFetcher
    }

    private struct CacheState {
        var serviceIdHashValues = [ServiceId: Int]()
        var phoneNumberHashValues = [String: Int]()

        var serviceIdToPhoneNumber = [ServiceId: PotentiallyVisible<String>]()
        var phoneNumberToServiceIds = [String: [PotentiallyVisible<ServiceId>]]()

        var serviceIdCachedAddresses = [ServiceId: [CachedAddress]]()
        var phoneNumberOnlyCachedAddresses = [String: [CachedAddress]]()
        var phoneNumberOnlyLegacyCachedAddresses = [String: [CachedAddress]]()
    }

    /// Tracks a relationship that may or may not be visible.
    ///
    /// Hidden relationships are used to handle "legacy" address migrations.
    private struct PotentiallyVisible<T: Equatable>: Equatable {
        var wrappedValue: T
        var isVisible: Bool
    }

    // TODO: Remove this initializer after fixing DependenciesBridge setup.
    public override init() {
        self._phoneNumberVisibilityFetcher = nil
    }

    public init(phoneNumberVisibilityFetcher: any PhoneNumberVisibilityFetcher) {
        self._phoneNumberVisibilityFetcher = phoneNumberVisibilityFetcher
    }

    func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        SSKEnvironment.shared.databaseStorageRef.read { tx in
            let bulkFetcher: BulkPhoneNumberVisibilityFetcher?
            do {
                bulkFetcher = try phoneNumberVisibilityFetcher.fetchAll(tx: tx.asV2Read)
            } catch {
                Logger.warn("Couldn't fetch visible phone numbers. Hiding all of them…")
                bulkFetcher = nil
            }
            SignalRecipient.anyEnumerate(transaction: tx) { recipient, _ in
                updateRecipient(
                    recipient,
                    isPhoneNumberVisible: (
                        bulkFetcher?.isPhoneNumberVisible(for: recipient) ?? false
                    )
                )
            }
        }
    }

    /// Updates the cache to reflect `signalRecipient`.
    ///
    /// This method doesn't require a write transaction to function, but there's
    /// an assumption throughout the application that SignalServiceAddresses
    /// won't change outside of a write transaction. Therefore, this method
    /// requires one to allow the compiler to help enforce this invariant.
    public func updateRecipient(_ signalRecipient: SignalRecipient, tx: DBWriteTransaction) {
        updateRecipient(
            signalRecipient,
            isPhoneNumberVisible: phoneNumberVisibilityFetcher.isPhoneNumberVisible(for: signalRecipient, tx: tx)
        )
    }

    internal func updateRecipient(_ signalRecipient: SignalRecipient, isPhoneNumberVisible: Bool) {
        updateRecipient(
            aci: signalRecipient.aci,
            pni: signalRecipient.pni,
            phoneNumber: signalRecipient.phoneNumber?.stringValue,
            isPhoneNumberVisible: isPhoneNumberVisible
        )
    }

    private func updateRecipient(aci: Aci?, pni: Pni?, phoneNumber: String?, isPhoneNumberVisible: Bool) {
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

            let oldPotentiallyVisibleServiceIds: [PotentiallyVisible<ServiceId>] = (
                cacheState.phoneNumberToServiceIds[phoneNumber] ?? []
            )
            let newPotentiallyVisibleServiceIds: [PotentiallyVisible<ServiceId>] = [
                aci.map { PotentiallyVisible(wrappedValue: $0, isVisible: isPhoneNumberVisible) },
                pni.map { PotentiallyVisible(wrappedValue: $0, isVisible: true) },
            ].compacted()

            // If this phone number still points at the same ServiceIds in the same
            // way, there's nothing to change.
            if newPotentiallyVisibleServiceIds == oldPotentiallyVisibleServiceIds {
                return
            }

            // Update the "phone number -> service ids" lookup table.
            cacheState.phoneNumberToServiceIds[phoneNumber] = newPotentiallyVisibleServiceIds

            // Update the "service id -> phone number" lookup table by clearing the
            // entries for any values that were removed and updating the entries for
            // any values that were added or changed.
            for oldServiceId in oldPotentiallyVisibleServiceIds {
                if newPotentiallyVisibleServiceIds.contains(where: { $0.wrappedValue == oldServiceId.wrappedValue }) {
                    continue
                }
                cacheState.serviceIdToPhoneNumber[oldServiceId.wrappedValue] = nil
            }
            for newOrUpdatedServiceId in newPotentiallyVisibleServiceIds {
                let oldPhoneNumber = cacheState.serviceIdToPhoneNumber.updateValue(
                    PotentiallyVisible(wrappedValue: phoneNumber, isVisible: newOrUpdatedServiceId.isVisible),
                    forKey: newOrUpdatedServiceId.wrappedValue
                )
                // If this ServiceId was associated with some other phone number, we need
                // to break that association.
                if let oldPhoneNumber, oldPhoneNumber.wrappedValue != phoneNumber {
                    cacheState.phoneNumberToServiceIds[oldPhoneNumber.wrappedValue]?.removeAll(where: {
                        return $0.wrappedValue == newOrUpdatedServiceId.wrappedValue
                    })
                }
                // This might be the first time we're learning about this ServiceId or
                // phone number. If a preferred hash value is available, make sure all
                // future SignalServiceAddress instances will be able to find it.
                _ = hashValue(cacheState: &cacheState, serviceId: newOrUpdatedServiceId.wrappedValue, phoneNumber: phoneNumber)
            }

            let oldVisibleServiceIds: [ServiceId] = oldPotentiallyVisibleServiceIds.compactMap {
                return $0.isVisible ? $0.wrappedValue : nil
            }
            let newVisibleServiceIds: [ServiceId] = newPotentiallyVisibleServiceIds.compactMap {
                return $0.isVisible ? $0.wrappedValue : nil
            }

            // These ServiceIds are no longer visibly associated with `phoneNumber`.
            for serviceId in Set(oldVisibleServiceIds).subtracting(newVisibleServiceIds) {
                cacheState.serviceIdCachedAddresses[serviceId]?.forEach { cachedAddress in
                    cachedAddress.identifiers.update { $0.phoneNumber = nil }
                }
            }

            // These ServiceIds are now visibly associated with `phoneNumber`.
            for serviceId in Set(newVisibleServiceIds).subtracting(oldVisibleServiceIds) {
                cacheState.serviceIdCachedAddresses[serviceId]?.forEach { cachedAddress in
                    cachedAddress.identifiers.update { $0.phoneNumber = phoneNumber }
                }
            }

            // "Legacy" addresses can be resolved using any ServiceId.
            updatePhoneNumberOnlyAddresses(
                phoneNumberOnlyCachedAddresses: &cacheState.phoneNumberOnlyLegacyCachedAddresses,
                serviceIdCachedAddresses: &cacheState.serviceIdCachedAddresses,
                phoneNumber: phoneNumber,
                serviceId: newPotentiallyVisibleServiceIds.first
            )
            // Other addresses can only be resolved with a visible ServiceId.
            updatePhoneNumberOnlyAddresses(
                phoneNumberOnlyCachedAddresses: &cacheState.phoneNumberOnlyCachedAddresses,
                serviceIdCachedAddresses: &cacheState.serviceIdCachedAddresses,
                phoneNumber: phoneNumber,
                serviceId: newPotentiallyVisibleServiceIds.first(where: { $0.isVisible })
            )
        }
    }

    /// If we're adding a ServiceId to this recipient for the first time, we may
    /// have some addresses with only a phone number. We should add the "best"
    /// ServiceId available to those addresses. Once we add a ServiceId, that
    /// value is "sticky" and won't be changed if we get an even better
    /// identifier in the future. This maintains the existing (very useful)
    /// invariant that a ServiceId for a SignalServiceAddress remains stable.
    private func updatePhoneNumberOnlyAddresses(
        phoneNumberOnlyCachedAddresses: inout [String: [CachedAddress]],
        serviceIdCachedAddresses: inout [ServiceId: [CachedAddress]],
        phoneNumber: String,
        serviceId: PotentiallyVisible<ServiceId>?
    ) {
        guard let serviceId else {
            return
        }
        phoneNumberOnlyCachedAddresses.removeValue(forKey: phoneNumber)?.forEach { cachedAddress in
            cachedAddress.identifiers.update {
                $0.serviceId = serviceId.wrappedValue
                if !serviceId.isVisible { $0.phoneNumber = nil }
            }
            // This address has a serviceId now -- track that serviceId for future updates.
            serviceIdCachedAddresses[serviceId.wrappedValue, default: []].append(cachedAddress)
        }
    }

    fileprivate func registerAddress(proposedIdentifiers: CachedAddress.Identifiers, isLegacyPhoneNumber: Bool) -> CachedAddress {
        state.update { cacheState in
            let resolvedIdentifiers = resolveIdentifiers(
                proposedIdentifiers,
                isLegacyPhoneNumber: isLegacyPhoneNumber,
                cacheState: cacheState
            )

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

            if let serviceId = resolvedIdentifiers.serviceId {
                return getOrCreateCachedAddress(key: serviceId, in: &cacheState.serviceIdCachedAddresses)
            }
            if let phoneNumber = resolvedIdentifiers.phoneNumber {
                if isLegacyPhoneNumber {
                    return getOrCreateCachedAddress(key: phoneNumber, in: &cacheState.phoneNumberOnlyLegacyCachedAddresses)
                } else {
                    return getOrCreateCachedAddress(key: phoneNumber, in: &cacheState.phoneNumberOnlyCachedAddresses)
                }
            }
            return CachedAddress(hashValue: hashValue, identifiers: resolvedIdentifiers)
        }
    }

    /// Populates missing/stale identifiers populated from the cache.
    ///
    /// - Parameter isLegacyPhoneNumber: If true, phone numbers can be resolved
    /// to hidden ACIs. This ensures legacy values (eg, receipts for old
    /// messages) will continue to associate with the correct account. In these
    /// cases, the returned identifiers won't contain the proposed phone number.
    /// If false, phone numbers can't be resolved to hidden ACIs (but they can
    /// be resolved to PNIs which are always visible to phone numbers).
    private func resolveIdentifiers(
        _ proposedIdentifiers: CachedAddress.Identifiers,
        isLegacyPhoneNumber: Bool,
        cacheState: CacheState
    ) -> CachedAddress.Identifiers {
        var resolvedIdentifiers = proposedIdentifiers
        resolveServiceId(
            in: &resolvedIdentifiers,
            isLegacyPhoneNumber: isLegacyPhoneNumber,
            cacheState: cacheState
        )
        resolvePhoneNumber(in: &resolvedIdentifiers, cacheState: cacheState)
        return resolvedIdentifiers
    }

    private func resolveServiceId(
        in identifiers: inout CachedAddress.Identifiers,
        isLegacyPhoneNumber: Bool,
        cacheState: CacheState
    ) {
        guard identifiers.serviceId == nil, let phoneNumber = identifiers.phoneNumber else {
            return
        }
        for serviceId in (cacheState.phoneNumberToServiceIds[phoneNumber] ?? []) {
            if serviceId.isVisible {
                identifiers.serviceId = serviceId.wrappedValue
                return
            }
            // A "legacy" value can be resolved, but we know it's hidden (because the
            // prior check didn't pass), so clear the phone number.
            if isLegacyPhoneNumber {
                identifiers.serviceId = serviceId.wrappedValue
                identifiers.phoneNumber = nil
                return
            }
        }
    }

    private func resolvePhoneNumber(
        in identifiers: inout CachedAddress.Identifiers,
        cacheState: CacheState
    ) {
        guard identifiers.phoneNumber == nil, let serviceId = identifiers.serviceId else {
            return
        }
        if let phoneNumber = cacheState.serviceIdToPhoneNumber[serviceId] {
            if phoneNumber.isVisible {
                identifiers.phoneNumber = phoneNumber.wrappedValue
                return
            }
            // Unlike the prior method, we don't need special handling for
            // isLegacyPhoneNumber in this case. The goal for "legacy" values is to
            // resolve to an ACI, but if we reach this point, `identifier.serviceId` is
            // an ACI (because PNIs don't set isVisible to false) and
            // `identifier.phoneNumber` is nil.
        }
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
            cache: SignalServiceAddressCache()
        )
    }
}

extension SignalServiceAddressCache {
    func makeAddress(serviceId: ServiceId?, phoneNumber: E164?) -> SignalServiceAddress {
        SignalServiceAddress(
            serviceId: serviceId,
            phoneNumber: phoneNumber?.stringValue,
            cache: self
        )
    }
}

#endif
