//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import SignalCoreKit

extension SignalRecipient {

    @objc
    public var isRegistered: Bool { !devices.set.isEmpty }

    public var deviceIds: [UInt32]? {
        (devices.array as? [NSNumber])?.map { $0.uint32Value }
    }

    // MARK: -

    public func markAsUnregistered(at timestamp: UInt64? = nil, source: SignalRecipientSource = .local, transaction: SDSAnyWriteTransaction) {
        guard devices.count != 0 else {
            return
        }

        let timestamp = timestamp ?? Date.ows_millisecondTimestamp()
        anyUpdate(transaction: transaction) {
            $0.removeAllDevicesWithUnregistered(atTimestamp: timestamp, source: source)
        }
    }

    public func markAsRegistered(
        source: SignalRecipientSource = .local,
        deviceId: UInt32 = OWSDevice.primaryDeviceId,
        transaction: SDSAnyWriteTransaction
    ) {
        // Always add the primary device ID if we're adding any other.
        let deviceIds: Set<UInt32> = [deviceId, OWSDevice.primaryDeviceId]

        let missingDeviceIds = deviceIds.filter { !devices.contains(NSNumber(value: $0)) }
        guard !missingDeviceIds.isEmpty else {
            return
        }

        Logger.debug("Adding devices \(missingDeviceIds) to existing recipient.")

        anyUpdate(transaction: transaction) {
            $0.addDevices(Set(missingDeviceIds.map { NSNumber(value: $0) }), source: source)
        }
    }

    // MARK: -

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
                DBTableMapping(databaseTableName: "\(SignalAccountRecord.databaseTableName)",
                               uuidColumn: "\(signalAccountColumn: .recipientUUID)",
                               phoneNumberColumn: "\(signalAccountColumn: .recipientPhoneNumber)"),
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
        SignalServiceAddress.addressComponentsDescription(uuidString: recipientUUID,
                                                          phoneNumber: recipientPhoneNumber)
    }
}

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
