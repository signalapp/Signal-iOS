//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
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
    public var serviceIdString: String?
    public var phoneNumber: String?
    private(set) public var deviceIds: [UInt32]
    private(set) public var unregisteredAtTimestamp: UInt64?

    public var serviceId: ServiceId? {
        get { ServiceId(uuidString: serviceIdString) }
        set { serviceIdString = newValue?.uuidValue.uuidString }
    }

    public var address: SignalServiceAddress {
        SignalServiceAddress(uuidString: serviceIdString, phoneNumber: phoneNumber)
    }

    public convenience init(serviceId: ServiceId?, phoneNumber: E164?) {
        self.init(serviceId: serviceId, phoneNumber: phoneNumber, deviceIds: [])
    }

    public convenience init(serviceId: ServiceId?, phoneNumber: E164?, deviceIds: [UInt32]) {
        self.init(
            id: nil,
            uniqueId: UUID().uuidString,
            serviceIdString: serviceId?.uuidValue.uuidString,
            phoneNumber: phoneNumber?.stringValue,
            deviceIds: deviceIds,
            unregisteredAtTimestamp: deviceIds.isEmpty ? Constants.distantPastUnregisteredTimestamp : nil
        )
    }

    private init(
        id: RowId?,
        uniqueId: String,
        serviceIdString: String?,
        phoneNumber: String?,
        deviceIds: [UInt32],
        unregisteredAtTimestamp: UInt64?
    ) {
        self.id = id
        self.uniqueId = uniqueId
        self.serviceIdString = serviceIdString
        self.phoneNumber = phoneNumber
        self.deviceIds = deviceIds
        self.unregisteredAtTimestamp = unregisteredAtTimestamp
    }

    public func copy(with zone: NSZone? = nil) -> Any {
        return SignalRecipient(
            id: id,
            uniqueId: uniqueId,
            serviceIdString: serviceIdString,
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
        guard serviceIdString == otherRecipient.serviceIdString else { return false }
        guard phoneNumber == otherRecipient.phoneNumber else { return false }
        guard deviceIds == otherRecipient.deviceIds else { return false }
        guard unregisteredAtTimestamp == otherRecipient.unregisteredAtTimestamp else { return false }
        return true
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(uniqueId)
        hasher.combine(serviceIdString)
        hasher.combine(phoneNumber)
        hasher.combine(deviceIds)
        hasher.combine(unregisteredAtTimestamp)
        return hasher.finalize()
    }

    public enum CodingKeys: String, CodingKey, ColumnExpression, CaseIterable {
        case id
        case recordType
        case uniqueId
        case serviceIdString = "recipientUUID"
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
        serviceIdString = try container.decodeIfPresent(String.self, forKey: .serviceIdString)
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
        try container.encodeIfPresent(serviceIdString, forKey: .serviceIdString)
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
        let readCache = modelReadCaches.signalRecipientReadCache
        guard let signalRecipient = readCache.getSignalRecipient(address: address, transaction: tx) else {
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

    @objc
    public static func fetchAllRegisteredRecipients(tx: SDSAnyReadTransaction) -> [SignalRecipient] {
        var result = [SignalRecipient]()
        Self.anyEnumerate(transaction: tx) { signalRecipient, _ in
            guard signalRecipient.isRegistered else {
                return
            }
            result.append(signalRecipient)
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

    // MARK: - Callbacks

    public func anyDidInsert(transaction tx: SDSAnyWriteTransaction) {
        modelReadCaches.signalRecipientReadCache.didInsertOrUpdate(signalRecipient: self, transaction: tx)
    }

    public func anyDidUpdate(transaction tx: SDSAnyWriteTransaction) {
        modelReadCaches.signalRecipientReadCache.didInsertOrUpdate(signalRecipient: self, transaction: tx)
    }

    public func anyDidRemove(transaction tx: SDSAnyWriteTransaction) {
        modelReadCaches.signalRecipientReadCache.didRemove(signalRecipient: self, transaction: tx)
        storageServiceManager.recordPendingUpdates(updatedAccountIds: [uniqueId])
    }

    public func anyDidFetchOne(transaction tx: SDSAnyReadTransaction) {
        modelReadCaches.signalRecipientReadCache.didReadSignalRecipient(self, transaction: tx)
    }

    public func anyDidEnumerateOne(transaction tx: SDSAnyReadTransaction) {
        modelReadCaches.signalRecipientReadCache.didReadSignalRecipient(self, transaction: tx)
    }

    // MARK: - Contact Merging

    public static let phoneNumberDidChange = Notification.Name("phoneNumberDidChange")
    public static let notificationKeyPhoneNumber = "phoneNumber"
    public static let notificationKeyUUID = "UUID"

    fileprivate static func didUpdatePhoneNumber(
        oldServiceIdString: String?,
        oldPhoneNumber: String?,
        newServiceIdString: String?,
        newPhoneNumber: String?,
        transaction: SDSAnyWriteTransaction
    ) {
        let oldServiceId = ServiceId(uuidString: oldServiceIdString)
        let newServiceId = ServiceId(uuidString: newServiceIdString)

        let oldAddress = SignalServiceAddress(
            uuid: oldServiceId?.uuidValue,
            phoneNumber: oldPhoneNumber,
            ignoreCache: true
        )
        let newAddress = SignalServiceAddress(
            uuid: newServiceId?.uuidValue,
            phoneNumber: newPhoneNumber,
            ignoreCache: true
        )

        // The "obsolete" address is the address with *only* the just-removed phone
        // number. (We *just* removed it, so we don't know its serviceId.)
        let obsoleteAddress = oldPhoneNumber.map { SignalServiceAddress(uuid: nil, phoneNumber: $0, ignoreCache: true) }

        let isWhitelisted = profileManager.isUser(inProfileWhitelist: oldAddress, transaction: transaction)

        transaction.addAsyncCompletion(queue: .global()) {
            let phoneNumbers: [String] = [oldPhoneNumber, newPhoneNumber].compactMap { $0 }
            for phoneNumber in phoneNumbers {
                var userInfo: [AnyHashable: Any] = [
                    Self.notificationKeyPhoneNumber: phoneNumber
                ]
                if let newServiceIdString {
                    userInfo[Self.notificationKeyUUID] = newServiceIdString
                }
                NotificationCenter.default.postNotificationNameAsync(Self.phoneNumberDidChange,
                                                                     object: nil,
                                                                     userInfo: userInfo)
            }
        }

        Self.updateDBTableMappings(
            newPhoneNumber: newPhoneNumber,
            oldPhoneNumber: oldPhoneNumber,
            newUuid: newServiceIdString,
            transaction: transaction.unwrapGrdbWrite
        )

        if let oldPhoneNumber {
            // If we have an `oldPhoneNumber`, it means that value is now detached from
            // everything. If there is any profile that refers exclusively to that
            // phone number, we can delete it. (If there are profiles that refer to
            // some other ACI, we should keep those since they're for accounts that are
            // potentially still valid.)
            let sql = """
                DELETE FROM \(UserProfileRecord.databaseTableName)
                WHERE \(userProfileColumn: .recipientPhoneNumber) = ? AND \(userProfileColumn: .recipientUUID) IS NULL
            """
            transaction.unwrapGrdbWrite.execute(sql: sql, arguments: [oldPhoneNumber])
        }

        // TODO: we may need to do more here, this is just bear bones to make sure we
        // don't hold onto stale data with the old mapping.

        ModelReadCaches.shared.evacuateAllCaches()

        if let contactThread = AnyContactThreadFinder().contactThread(for: newAddress, transaction: transaction) {
            SDSDatabaseStorage.shared.touch(thread: contactThread, shouldReindex: true, transaction: transaction)
        }

        if let newServiceId {
            if !newAddress.isLocalAddress {
                self.versionedProfiles.clearProfileKeyCredential(
                    for: ServiceIdObjC(newServiceId),
                    transaction: transaction
                )

                if let obsoleteAddress {
                    // Remove old address from profile whitelist.
                    profileManager.removeUser(
                        fromProfileWhitelist: obsoleteAddress,
                        userProfileWriter: .changePhoneNumber,
                        transaction: transaction
                    )
                }

                // Ensure new address reflects old address' profile whitelist state.
                if isWhitelisted {
                    profileManager.addUser(
                        toProfileWhitelist: newAddress,
                        userProfileWriter: .changePhoneNumber,
                        transaction: transaction
                    )
                } else {
                    profileManager.removeUser(
                        fromProfileWhitelist: newAddress,
                        userProfileWriter: .changePhoneNumber,
                        transaction: transaction
                    )
                }
            }
        } else {
            owsFailDebug("Missing or invalid UUID")
        }

        if let obsoleteAddress {
            transaction.addAsyncCompletion(queue: .global()) {
                Self.udManager.setUnidentifiedAccessMode(.unknown, address: obsoleteAddress)
            }
        }

        if newServiceId != nil {
            transaction.addAsyncCompletion(queue: .global()) {
                Self.udManager.setUnidentifiedAccessMode(.unknown, address: newAddress)

                if !CurrentAppContext().isRunningTests {
                    ProfileFetcherJob.fetchProfile(address: newAddress, ignoreThrottling: true)
                }
            }
        }

        transaction.addAsyncCompletion(queue: .global()) {
            // Evacuate caches again once the transaction completes, in case
            // some kind of race occurred.
            ModelReadCaches.shared.evacuateAllCaches()
        }
    }

    private static func updateDBTableMappings(
        newPhoneNumber: String?,
        oldPhoneNumber: String?,
        newUuid: String?,
        transaction: GRDBWriteTransaction
    ) {
        guard newUuid != nil || newPhoneNumber != nil else {
            owsFailDebug("Missing newUuid and newPhoneNumber.")
            return
        }

        for dbTableMapping in DBTableMapping.all {
            let databaseTableName = dbTableMapping.databaseTableName
            let uuidColumn = dbTableMapping.uuidColumn
            let phoneNumberColumn = dbTableMapping.phoneNumberColumn
            let sql = """
                UPDATE \(databaseTableName)
                SET \(uuidColumn) = ?, \(phoneNumberColumn) = ?
                WHERE (\(uuidColumn) IS ? OR \(uuidColumn) IS NULL)
                AND (\(phoneNumberColumn) IS ? OR \(phoneNumberColumn) IS NULL)
                AND NOT (\(uuidColumn) IS NULL AND \(phoneNumberColumn) IS NULL)
                """

            let arguments: StatementArguments = [newUuid, newPhoneNumber, newUuid, oldPhoneNumber]
            transaction.execute(sql: sql, arguments: arguments)
        }
    }

    // There is no instance of SignalRecipient for the new uuid,
    // but other db tables might have mappings for the new uuid.
    // We need to clear that out.
    fileprivate static func clearDBMappings(forUuid uuid: UUID, transaction: SDSAnyWriteTransaction) {
        Logger.info("uuid: \(uuid)")

        let mockUuid = UUID().uuidString
        let transaction = transaction.unwrapGrdbWrite

        for dbTableMapping in DBTableMapping.all {
            let databaseTableName = dbTableMapping.databaseTableName
            let uuidColumn = dbTableMapping.uuidColumn
            let phoneNumberColumn = dbTableMapping.phoneNumberColumn

            // If a record has a valid phoneNumber, we can simply clear the uuid.
            do {
                let sql = """
                    UPDATE \(databaseTableName)
                    SET \(uuidColumn) = NULL
                    WHERE \(uuidColumn) = ?
                    AND \(phoneNumberColumn) IS NOT NULL
                    """
                let arguments: StatementArguments = [uuid.uuidString]
                transaction.execute(sql: sql, arguments: arguments)
            }

            // If a record does _NOT_ have a valid phoneNumber, we apply a mock uuid.
            let sql = """
                UPDATE \(databaseTableName)
                SET \(uuidColumn) = ?
                WHERE \(uuidColumn) = ?
                AND \(phoneNumberColumn) IS NULL
                """
            let arguments: StatementArguments = [mockUuid, uuid.uuidString]
            transaction.execute(sql: sql, arguments: arguments)
        }
    }

    // There is no instance of SignalRecipient for the new phone number,
    // but other db tables might have mappings for the new phone number.
    // We need to clear that out.
    fileprivate static func clearDBMappings(forPhoneNumber phoneNumber: String, transaction: SDSAnyWriteTransaction) {
        guard let phoneNumber = phoneNumber.nilIfEmpty else {
            owsFailDebug("Invalid phoneNumber.")
            return
        }

        Logger.info("phoneNumber: \(phoneNumber)")

        let mockUuid = UUID().uuidString
        let transaction = transaction.unwrapGrdbWrite

        for dbTableMapping in DBTableMapping.all {
            let databaseTableName = dbTableMapping.databaseTableName
            let uuidColumn = dbTableMapping.uuidColumn
            let phoneNumberColumn = dbTableMapping.phoneNumberColumn

            // If a record has a valid uuid, we can simply clear the phoneNumber.
            do {
                let sql = """
                    UPDATE \(databaseTableName)
                    SET \(phoneNumberColumn) = NULL
                    WHERE \(phoneNumberColumn) = ?
                    AND \(uuidColumn) IS NOT NULL
                    """
                let arguments: StatementArguments = [phoneNumber]
                transaction.execute(sql: sql, arguments: arguments)
            }

            // If a record does _NOT_ have a valid uuid, we clear the phoneNumber and apply a mock uuid.
            let sql = """
                UPDATE \(databaseTableName)
                SET \(uuidColumn) = ?, \(phoneNumberColumn) = NULL
                WHERE \(phoneNumberColumn) = ?
                AND \(uuidColumn) IS NULL
                """
            let arguments: StatementArguments = [mockUuid, phoneNumber]
            transaction.execute(sql: sql, arguments: arguments)
        }
    }

    private struct DBTableMapping {
        let databaseTableName: String
        let uuidColumn: String
        let phoneNumberColumn: String

        static var all: [DBTableMapping] {
            return [
                DBTableMapping(databaseTableName: "\(ThreadRecord.databaseTableName)",
                               uuidColumn: "\(threadColumn: .contactUUID)",
                               phoneNumberColumn: "\(threadColumn: .contactPhoneNumber)"),
                DBTableMapping(databaseTableName: "\(OWSReaction.databaseTableName)",
                               uuidColumn: "\(OWSReaction.columnName(.reactorUUID))",
                               phoneNumberColumn: "\(OWSReaction.columnName(.reactorE164))"),
                DBTableMapping(databaseTableName: "\(InteractionRecord.databaseTableName)",
                               uuidColumn: "\(interactionColumn: .authorUUID)",
                               phoneNumberColumn: "\(interactionColumn: .authorPhoneNumber)"),
                DBTableMapping(databaseTableName: "\(UserProfileRecord.databaseTableName)",
                               uuidColumn: "\(userProfileColumn: .recipientUUID)",
                               phoneNumberColumn: "\(userProfileColumn: .recipientPhoneNumber)"),
                DBTableMapping(databaseTableName: "pending_read_receipts",
                               uuidColumn: "authorUuid",
                               phoneNumberColumn: "authorPhoneNumber"),
                DBTableMapping(databaseTableName: "pending_viewed_receipts",
                               uuidColumn: "authorUuid",
                               phoneNumberColumn: "authorPhoneNumber")
            ]
        }
    }

    @objc
    public var addressComponentsDescription: String {
        SignalServiceAddress.addressComponentsDescription(uuidString: serviceIdString, phoneNumber: phoneNumber)
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

// MARK: -

class SignalRecipientMergerTemporaryShims: RecipientMergerTemporaryShims {
    private let sessionStore: SSKSessionStore

    init(sessionStore: SSKSessionStore) {
        self.sessionStore = sessionStore
    }

    func clearMappings(phoneNumber: E164, transaction: DBWriteTransaction) {
        SignalRecipient.clearDBMappings(forPhoneNumber: phoneNumber.stringValue, transaction: SDSDB.shimOnlyBridge(transaction))
    }

    func clearMappings(serviceId: ServiceId, transaction: DBWriteTransaction) {
        SignalRecipient.clearDBMappings(forUuid: serviceId.uuidValue, transaction: SDSDB.shimOnlyBridge(transaction))
    }

    func didUpdatePhoneNumber(
        oldServiceIdString: String?,
        oldPhoneNumber: String?,
        newServiceIdString: String?,
        newPhoneNumber: E164?,
        transaction: DBWriteTransaction
    ) {
        SignalRecipient.didUpdatePhoneNumber(
            oldServiceIdString: oldServiceIdString,
            oldPhoneNumber: oldPhoneNumber,
            newServiceIdString: newServiceIdString,
            newPhoneNumber: newPhoneNumber?.stringValue,
            transaction: SDSDB.shimOnlyBridge(transaction)
        )
    }

    func mergeUserProfilesIfNecessary(serviceId: ServiceId, phoneNumber: E164, transaction: DBWriteTransaction) {
        OWSUserProfile.mergeUserProfilesIfNecessary(
            for: SignalServiceAddress(uuid: serviceId.uuidValue, phoneNumber: phoneNumber.stringValue),
            authedAccount: .implicit(),
            transaction: SDSDB.shimOnlyBridge(transaction)
        )
    }

    func hasActiveSignalProtocolSession(recipientId: String, deviceId: Int32, transaction: DBWriteTransaction) -> Bool {
        sessionStore.containsActiveSession(
            forAccountId: recipientId,
            deviceId: deviceId,
            transaction: SDSDB.shimOnlyBridge(transaction)
        )
    }
}
