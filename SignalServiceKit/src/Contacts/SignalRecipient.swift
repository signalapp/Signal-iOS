//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient
import SignalCoreKit

/// We create SignalRecipient records for accounts we know about.
///
/// A SignalRecipient's stable identifier is an ACI. Once a SignalRecipient
/// has an ACI, it can't change. However, the other identifiers (phone
/// number & PNI) can freely change when users change the phone number
/// associated with their account.
///
/// We also store the set of device IDs for each account on this record. If
/// an account has at least one device, it's registered. If an account
/// doesn't have any devices, then that user isn't registered.
public final class SignalRecipient: NSObject, NSCopying, SDSCodableModel, Decodable {
    public static let databaseTableName = "model_SignalRecipient"
    public static var recordType: UInt { SDSRecordType.signalRecipient.rawValue }
    public static var ftsIndexMode: TSFTSIndexMode { .always }

    public enum Constants {
        public static let distantPastUnregisteredTimestamp: UInt64 = 1
    }

    public enum ModifySource: Int {
        case local
        case storageService
    }

    public var id: RowId?
    public let uniqueId: String
    /// Represents the ACI for this SignalRecipient.
    ///
    /// This value has historically been represented as a String (from the ObjC
    /// days). If we change its type to Aci, then we may fail to fetch database
    /// rows. To avoid introducing new failure points, it should remain a String
    /// whose contents we validate at time-of-use rather than time-of-fetch.
    public var aciString: String?
    /// Represents the PNI for this SignalRecipient.
    ///
    /// These have always been strongly typed for their entire existence, so
    /// it's safe to check it at time-of-fetch and throw an error.
    public var pni: Pni?
    public var phoneNumber: String?
    private(set) public var deviceIds: [UInt32]
    private(set) public var unregisteredAtTimestamp: UInt64?

    public var aci: Aci? {
        get { Aci.parseFrom(aciString: aciString) }
        set { aciString = newValue?.serviceIdUppercaseString }
    }

    public var isEmpty: Bool {
        return aciString == nil && phoneNumber == nil && pni == nil
    }

    public var address: SignalServiceAddress {
        SignalServiceAddress(serviceId: aci ?? pni, phoneNumber: phoneNumber)
    }

    public convenience init(aci: Aci?, pni: Pni?, phoneNumber: E164?) {
        self.init(aci: aci, pni: pni, phoneNumber: phoneNumber, deviceIds: [])
    }

    public convenience init(aci: Aci?, pni: Pni?, phoneNumber: E164?, deviceIds: [UInt32]) {
        self.init(
            id: nil,
            uniqueId: UUID().uuidString,
            aciString: aci?.serviceIdUppercaseString,
            pni: pni,
            phoneNumber: phoneNumber?.stringValue,
            deviceIds: deviceIds,
            unregisteredAtTimestamp: deviceIds.isEmpty ? Constants.distantPastUnregisteredTimestamp : nil
        )
    }

    private init(
        id: RowId?,
        uniqueId: String,
        aciString: String?,
        pni: Pni?,
        phoneNumber: String?,
        deviceIds: [UInt32],
        unregisteredAtTimestamp: UInt64?
    ) {
        self.id = id
        self.uniqueId = uniqueId
        self.aciString = aciString
        self.pni = pni
        self.phoneNumber = phoneNumber
        self.deviceIds = deviceIds
        self.unregisteredAtTimestamp = unregisteredAtTimestamp
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return copyRecipient()
    }

    public func copyRecipient() -> SignalRecipient {
        return SignalRecipient(
            id: id,
            uniqueId: uniqueId,
            aciString: aciString,
            pni: pni,
            phoneNumber: phoneNumber,
            deviceIds: deviceIds,
            unregisteredAtTimestamp: unregisteredAtTimestamp
        )
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let otherRecipient = object as? SignalRecipient else {
            return false
        }
        guard id == otherRecipient.id else { return false }
        guard uniqueId == otherRecipient.uniqueId else { return false }
        guard aciString == otherRecipient.aciString else { return false }
        guard pni == otherRecipient.pni else { return false }
        guard phoneNumber == otherRecipient.phoneNumber else { return false }
        guard deviceIds == otherRecipient.deviceIds else { return false }
        guard unregisteredAtTimestamp == otherRecipient.unregisteredAtTimestamp else { return false }
        return true
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(uniqueId)
        hasher.combine(aciString)
        hasher.combine(pni)
        hasher.combine(phoneNumber)
        hasher.combine(deviceIds)
        hasher.combine(unregisteredAtTimestamp)
        return hasher.finalize()
    }

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case aciString = "recipientUUID"
        case pni
        case phoneNumber = "recipientPhoneNumber"
        case deviceIds = "devices"
        case unregisteredAtTimestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(UInt.self, forKey: .recordType)
        guard decodedRecordType == Self.recordType else {
            owsFailDebug("Unexpected record type: \(decodedRecordType)")
            throw SDSError.invalidValue
        }

        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)
        aciString = try container.decodeIfPresent(String.self, forKey: .aciString)
        pni = try container.decodeIfPresent(String.self, forKey: .pni).map { try Pni.parseFrom(serviceIdString: $0) }
        phoneNumber = try container.decodeIfPresent(String.self, forKey: .phoneNumber)
        let encodedDeviceIds = try container.decode(Data.self, forKey: .deviceIds)
        let deviceSetObjC: NSOrderedSet = try LegacySDSSerializer().deserializeLegacySDSData(encodedDeviceIds, propertyName: "devices")
        let deviceArray = (deviceSetObjC.array as? [NSNumber])?.map { $0.uint32Value }
        // If we can't parse the values in the NSOrderedSet, assume the user isn't
        // registered. If they are registered, we'll correct the data store the
        // next time we try to send them a message.
        deviceIds = deviceArray ?? []
        unregisteredAtTimestamp = try container.decodeIfPresent(UInt64.self, forKey: .unregisteredAtTimestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(Self.recordType, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)
        try container.encodeIfPresent(aciString, forKey: .aciString)
        try container.encodeIfPresent(pni?.serviceIdUppercaseString, forKey: .pni)
        try container.encodeIfPresent(phoneNumber, forKey: .phoneNumber)
        let deviceSetObjC = NSOrderedSet(array: deviceIds.map { NSNumber(value: $0) })
        let encodedDevices = LegacySDSSerializer().serializeAsLegacySDSData(property: deviceSetObjC)
        try container.encode(encodedDevices, forKey: .deviceIds)
        try container.encodeIfPresent(unregisteredAtTimestamp, forKey: .unregisteredAtTimestamp)
    }

    // MARK: - Fetching

    public static func fetchRecipient(
        for address: SignalServiceAddress,
        onlyIfRegistered: Bool,
        tx: SDSAnyReadTransaction
    ) -> SignalRecipient? {
        owsAssertDebug(address.isValid)
        guard let signalRecipient = SignalRecipientFinder().signalRecipient(for: address, tx: tx) else {
            return nil
        }
        if onlyIfRegistered {
            guard signalRecipient.isRegistered else {
                return nil
            }
        }
        return signalRecipient
    }

    public static func isRegistered(address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> Bool {
        return fetchRecipient(for: address, onlyIfRegistered: true, tx: tx) != nil
    }

    public static func fetchAllPhoneNumbers(tx: SDSAnyReadTransaction) -> [String: Bool] {
        var result = [String: Bool]()
        Self.anyEnumerate(transaction: tx) { signalRecipient, _ in
            guard let phoneNumber = signalRecipient.phoneNumber else {
                return
            }
            result[phoneNumber] = signalRecipient.isRegistered
        }
        return result
    }

    // MARK: - Registered & Device IDs

    public var isRegistered: Bool { !deviceIds.isEmpty }

    public func markAsUnregisteredAndSave(
        at timestamp: UInt64? = nil,
        source: ModifySource = .local,
        tx: SDSAnyWriteTransaction
    ) {
        guard isRegistered else {
            return
        }

        removeAllDevices(unregisteredAtTimestamp: timestamp ?? Date.ows_millisecondTimestamp(), source: source)
        anyOverwritingUpdate(transaction: tx)
    }

    public func markAsRegisteredAndSave(
        source: ModifySource = .local,
        deviceId: UInt32 = OWSDevice.primaryDeviceId,
        tx: SDSAnyWriteTransaction
    ) {
        // Always add the primary device ID if we're adding any other.
        let deviceIdsToAdd: Set<UInt32> = [deviceId, OWSDevice.primaryDeviceId]

        let missingDeviceIds = deviceIdsToAdd.filter { !deviceIds.contains($0) }

        guard !missingDeviceIds.isEmpty else {
            return
        }

        addDevices(missingDeviceIds, source: source)
        anyOverwritingUpdate(transaction: tx)
    }

    public func markAsRegisteredAndSave(
        source: ModifySource = .local,
        deviceId: UInt32,
        tx: DBWriteTransaction
    ) {
        self.markAsRegisteredAndSave(source: source, deviceId: deviceId, tx: SDSDB.shimOnlyBridge(tx))
    }

    public func modifyAndSave(deviceIdsToAdd: [UInt32], deviceIdsToRemove: [UInt32], tx: SDSAnyWriteTransaction) {
        if deviceIdsToAdd.isEmpty, deviceIdsToRemove.isEmpty {
            return
        }

        // Add new devices first to avoid an intermediate "empty" state.
        Logger.info("Adding \(deviceIdsToAdd) to \(address).")
        addDevices(deviceIdsToAdd, source: .local)

        Logger.info("Removing \(deviceIdsToRemove) from \(address).")
        removeDevices(deviceIdsToRemove, source: .local)

        anyOverwritingUpdate(transaction: tx)

        tx.addAsyncCompletionOnMain {
            // Device changes can affect the UD access mode for a recipient,
            // so we need to fetch the profile for this user to update UD access mode.
            self.profileManager.fetchProfile(for: self.address, authedAccount: .implicit())

            if self.address.isLocalAddress {
                self.socketManager.cycleSocket()
            }
        }
    }

    private func addDevices(_ deviceIdsToAdd: some Sequence<UInt32>, source: ModifySource) {
        deviceIds = Set(deviceIds).union(deviceIdsToAdd).sorted()

        if !deviceIds.isEmpty, unregisteredAtTimestamp != nil {
            setUnregisteredAtTimestamp(nil, source: source)
        }
    }

    private func removeDevices(_ deviceIdsToRemove: some Sequence<UInt32>, source: ModifySource) {
        deviceIds = Set(deviceIds).subtracting(deviceIdsToRemove).sorted()

        if deviceIds.isEmpty, unregisteredAtTimestamp == nil {
            setUnregisteredAtTimestamp(Date.ows_millisecondTimestamp(), source: source)
        }
    }

    private func removeAllDevices(unregisteredAtTimestamp: UInt64, source: ModifySource) {
        deviceIds = []
        setUnregisteredAtTimestamp(unregisteredAtTimestamp, source: source)
    }

    private func setUnregisteredAtTimestamp(_ unregisteredAtTimestamp: UInt64?, source: ModifySource) {
        if self.unregisteredAtTimestamp == unregisteredAtTimestamp {
            return
        }
        self.unregisteredAtTimestamp = unregisteredAtTimestamp

        switch source {
        case .storageService:
            // Don't need to tell storage service what they just told us.
            break
        case .local:
            storageServiceManager.recordPendingUpdates(updatedAccountIds: [uniqueId])
        }
    }

    @objc
    public var addressComponentsDescription: String {
        SignalServiceAddress.addressComponentsDescription(uuidString: aciString, phoneNumber: phoneNumber)
    }
}

// MARK: - StringInterpolation

public extension String.StringInterpolation {
    mutating func appendInterpolation(signalRecipientColumn column: SignalRecipient.CodingKeys) {
        appendLiteral(SignalRecipient.columnName(column))
    }
    mutating func appendInterpolation(signalRecipientColumnFullyQualified column: SignalRecipient.CodingKeys) {
        appendLiteral(SignalRecipient.columnName(column, fullyQualified: true))
    }
}
