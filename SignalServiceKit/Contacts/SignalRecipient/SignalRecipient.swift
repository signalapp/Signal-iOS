//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import GRDB
public import LibSignalClient

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
public struct SignalRecipient: FetchableRecord, MutablePersistableRecord, Codable {
    public static let databaseTableName = "model_SignalRecipient"

    public enum Constants {
        public static let distantPastUnregisteredTimestamp: UInt64 = 1
    }

    public struct PhoneNumber {
        public var stringValue: String

        /// Tracks whether or not this number is discoverable on CDS.
        /// 
        /// - Important: This property is usually stale on linked devices because
        /// they don't perform CDS syncs at regular intervals.
        public var isDiscoverable: Bool
    }

    public typealias RowId = Int64
    public private(set) var id: RowId?

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
    public var phoneNumber: PhoneNumber?
    fileprivate(set) public var deviceIds: [DeviceId]
    fileprivate(set) public var unregisteredAtTimestamp: UInt64?

    public var aci: Aci? {
        get { Aci.parseFrom(aciString: aciString) }
        set { aciString = newValue?.serviceIdUppercaseString }
    }

    public var isEmpty: Bool {
        return aciString == nil && phoneNumber == nil && pni == nil
    }

    public var address: SignalServiceAddress {
        // SignalRecipients store every identifier because they are the source of
        // truth. However, we still don't want to reveal redundant identifiers via
        // most accessor methods.
        let normalizedAddress = NormalizedDatabaseRecordAddress(
            aci: aci,
            phoneNumber: phoneNumber?.stringValue,
            pni: pni
        )
        return SignalServiceAddress(
            serviceId: normalizedAddress?.serviceId,
            phoneNumber: normalizedAddress?.phoneNumber
        )
    }

    public init(aci: Aci?, pni: Pni?, phoneNumber: E164?) {
        self.init(aci: aci, pni: pni, phoneNumber: phoneNumber, deviceIds: [])
    }

    public init(aci: Aci?, pni: Pni?, phoneNumber: E164?, deviceIds: [DeviceId]) {
        self.init(
            id: nil,
            uniqueId: UUID().uuidString,
            aciString: aci?.serviceIdUppercaseString,
            pni: pni,
            phoneNumber: phoneNumber.map { PhoneNumber(stringValue: $0.stringValue, isDiscoverable: false) },
            deviceIds: deviceIds,
            unregisteredAtTimestamp: deviceIds.isEmpty ? Constants.distantPastUnregisteredTimestamp : nil
        )
    }

    static func buildEmptyRecipient(unregisteredAt timestamp: UInt64) -> Self {
        var result = Self(aci: nil, pni: nil, phoneNumber: nil)
        result.unregisteredAtTimestamp = timestamp
        return result
    }

    public static func fromBackup(
        _ backupContact: BackupArchive.ContactAddress,
        isRegistered: Bool,
        unregisteredAtTimestamp: UInt64?
    ) -> Self {
        let deviceIds: [DeviceId]
        if isRegistered {
            // If we think they are registered, just add the primary device id.
            // When we try and send a message, the server will tell us about
            // any other device ids.
            // ...The server would tell us too if we sent an empty deviceIds array,
            // so there's not really a material difference.
            deviceIds = [.primary]
        } else {
            // Otherwise (including if we don't know if they're registered),
            // use an empty device IDs array. This doesn't make any difference,
            // the server will give us the deviceIds anyway and unregisteredAtTimestamp
            // is the thing that actually drives unregistered state, but
            // this is at least a better representation of what we know.
            deviceIds = []
        }
        return Self.init(
            id: nil,
            uniqueId: UUID().uuidString,
            aciString: backupContact.aci?.serviceIdUppercaseString,
            pni: backupContact.pni,
            phoneNumber: backupContact.e164.map {
                // Assume they're not discoverable. We'll learn the correct value for this
                // property during the first CDS sync.
                PhoneNumber(stringValue: $0.stringValue, isDiscoverable: false)
            },
            deviceIds: deviceIds,
            unregisteredAtTimestamp: unregisteredAtTimestamp
        )
    }

    private init(
        id: RowId?,
        uniqueId: String,
        aciString: String?,
        pni: Pni?,
        phoneNumber: PhoneNumber?,
        deviceIds: [DeviceId],
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

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case aciString = "recipientUUID"
        case pni
        case phoneNumber = "recipientPhoneNumber"
        case deviceIds = "devices"
        case unregisteredAtTimestamp
        case isPhoneNumberDiscoverable
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let decodedRecordType = try container.decode(UInt.self, forKey: .recordType)
        guard decodedRecordType == SDSRecordType.signalRecipient.rawValue else {
            owsFailDebug("Unexpected record type: \(decodedRecordType)")
            throw SDSError.invalidValue()
        }

        id = try container.decodeIfPresent(RowId.self, forKey: .id)
        uniqueId = try container.decode(String.self, forKey: .uniqueId)
        aciString = try container.decodeIfPresent(String.self, forKey: .aciString)
        pni = try container.decodeIfPresent(String.self, forKey: .pni).map { try Pni.parseFrom(serviceIdString: $0) }
        if let phoneNumberStringValue = try container.decodeIfPresent(String.self, forKey: .phoneNumber) {
            phoneNumber = PhoneNumber(
                stringValue: phoneNumberStringValue,
                isDiscoverable: try container.decodeIfPresent(Bool.self, forKey: .isPhoneNumberDiscoverable) ?? false
            )
        } else {
            phoneNumber = nil
        }
        let encodedDeviceIds = try container.decode(Data.self, forKey: .deviceIds)
        deviceIds = encodedDeviceIds.compactMap(DeviceId.init(validating:))
        unregisteredAtTimestamp = try container.decodeIfPresent(UInt64.self, forKey: .unregisteredAtTimestamp)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(SDSRecordType.signalRecipient.rawValue, forKey: .recordType)
        try container.encode(uniqueId, forKey: .uniqueId)
        try container.encodeIfPresent(aciString, forKey: .aciString)
        try container.encodeIfPresent(pni?.serviceIdUppercaseString, forKey: .pni)
        try container.encodeIfPresent(phoneNumber?.stringValue, forKey: .phoneNumber)
        try container.encodeIfPresent(phoneNumber?.isDiscoverable, forKey: .isPhoneNumberDiscoverable)
        try container.encode(Data(deviceIds.map(\.uint8Value)), forKey: .deviceIds)
        try container.encodeIfPresent(unregisteredAtTimestamp, forKey: .unregisteredAtTimestamp)
    }

    // MARK: - Fetching

    public var isRegistered: Bool { !deviceIds.isEmpty }

    public var addressComponentsDescription: String {
        SignalServiceAddress.addressComponentsDescription(uuidString: aciString, phoneNumber: phoneNumber?.stringValue)
    }

    // MARK: - System Contacts

    /// Whether or not this recipient can be discovered by their phone number.
    ///
    /// In order to be considered discoverable, we must have... discovered
    /// them... in the most recent CDS sync (which in turn implies they have a
    /// phone number and are registered).
    ///
    /// - Important: This property is usually stale on linked devices because
    /// they don't perform CDS syncs at regular intervals.
    public var isPhoneNumberDiscoverable: Bool {
        return isRegistered && phoneNumber?.isDiscoverable == true
    }

    // MARK: - Database Hooks

    public mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }
}

// MARK: - SignalRecipientManagerImpl

extension SignalRecipientManagerImpl {
    func setDeviceIds(
        _ deviceIds: Set<DeviceId>,
        for recipient: inout SignalRecipient,
        shouldUpdateStorageService: Bool
    ) {
        recipient.deviceIds = deviceIds.sorted()
        // Clear the timestamp if we're registered. If we're unregistered, set it if we don't already have one.
        // TODO: Should we deleteAllSessionsForContact here?
        setUnregisteredAtTimestamp(
            recipient.isRegistered ? nil : (recipient.unregisteredAtTimestamp ?? NSDate.ows_millisecondTimeStamp()),
            for: &recipient,
            shouldUpdateStorageService: shouldUpdateStorageService
        )
    }

    func setUnregisteredAtTimestamp(
        _ unregisteredAtTimestamp: UInt64?,
        for recipient: inout SignalRecipient,
        shouldUpdateStorageService: Bool
    ) {
        if recipient.unregisteredAtTimestamp == unregisteredAtTimestamp {
            return
        }
        recipient.unregisteredAtTimestamp = unregisteredAtTimestamp

        if shouldUpdateStorageService {
            storageServiceManager.recordPendingUpdates(updatedRecipientUniqueIds: [recipient.uniqueId])
        }
    }
}

// MARK: - StringInterpolation

public extension String.StringInterpolation {
    mutating func appendInterpolation(signalRecipientColumn column: SignalRecipient.CodingKeys) {
        appendLiteral(column.rawValue)
    }
    mutating func appendInterpolation(signalRecipientColumnFullyQualified column: SignalRecipient.CodingKeys) {
        appendLiteral("\(SignalRecipient.databaseTableName).\(column.rawValue)")
    }
}
