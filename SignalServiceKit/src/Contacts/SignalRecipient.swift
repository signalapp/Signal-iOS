//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import SignalCoreKit

extension SignalRecipient {

    @objc
    public var isRegistered: Bool { !devices.set.isEmpty }

    private static let storageServiceUnregisteredThreshold = kMonthInterval

    @objc
    public var shouldBeRepresentedInStorageService: Bool {
        guard !isRegistered else { return true }

        guard let unregisteredAtTimestamp = unregisteredAtTimestamp?.uint64Value else {
            return false
        }

        return Date().timeIntervalSince(Date(millisecondsSince1970: unregisteredAtTimestamp)) <= Self.storageServiceUnregisteredThreshold
    }

    @objc
    public static let phoneNumberDidChange = Notification.Name("phoneNumberDidChange")
    @objc
    public static let notificationKeyPhoneNumber = "phoneNumber"
    @objc
    public static let notificationKeyUUID = "UUID"

    @objc
    func changePhoneNumber(_ newPhoneNumber: String?, transaction: GRDBWriteTransaction) {

        let newPhoneNumber = newPhoneNumber?.nilIfEmpty
        let oldPhoneNumber = recipientPhoneNumber?.nilIfEmpty
        let oldUuid: UUID? = UUID(uuidString: recipientUUID?.nilIfEmpty ?? "")

        let isWhitelisted = profileManager.isUser(inProfileWhitelist: self.address,
                                                  transaction: transaction.asAnyRead)

        if newPhoneNumber == nil && recipientUUID == nil {
            Logger.warn("Clearing out the phone number on a recipient with no UUID. uuid: \(String(describing: self.recipientUUID)), phoneNumber: \(String(describing: oldPhoneNumber)) -> \(String(describing: newPhoneNumber)) ")
            // Fill in a random UUID, so we can complete the change and maintain a common
            // association for all the records and not leave them dangling. This should
            // in general never happen.
            recipientUUID = UUID().uuidString
        } else {
            Logger.info("uuid: \(String(describing: self.recipientUUID)), phoneNumber: \(String(describing: oldPhoneNumber)) -> \(String(describing: newPhoneNumber))")
        }

        recipientPhoneNumber = newPhoneNumber

        let newUuid = self.recipientUUID
        Logger.info("uuid: \(String(describing: oldUuid?.uuidString)) ->  \(String(describing: newUuid)), phoneNumber: \(String(describing: oldPhoneNumber)) -> \(String(describing: newPhoneNumber))")

        transaction.addAsyncCompletion(queue: .global()) {
            let phoneNumbers: [String] = [oldPhoneNumber, newPhoneNumber].compactMap { $0 }
            for phoneNumber in phoneNumbers {
                var userInfo: [AnyHashable: Any] = [
                    Self.notificationKeyPhoneNumber: phoneNumber
                ]
                if let newUuid = newUuid {
                    userInfo[Self.notificationKeyUUID] = newUuid
                }
                NotificationCenter.default.postNotificationNameAsync(Self.phoneNumberDidChange,
                                                                     object: nil,
                                                                     userInfo: userInfo)
            }
        }

        Self.updateDBTableMappings(newPhoneNumber: newPhoneNumber,
                                   oldPhoneNumber: oldPhoneNumber,
                                   newUuid: newUuid,
                                   transaction: transaction)

        if let newUuidString = newUuid?.nilIfEmpty,
           let newUuid = UUID(uuidString: newUuidString),
           let localUuid = tsAccountManager.localUuid,
           localUuid != newUuid,
           let oldPhoneNumber = oldPhoneNumber?.nilIfEmpty,
           let newPhoneNumber = newPhoneNumber?.nilIfEmpty {
            let infoMessageUserInfo: [InfoMessageUserInfoKey: Any] = [
                .changePhoneNumberUuid: newUuidString,
                .changePhoneNumberOld: oldPhoneNumber,
                .changePhoneNumberNew: newPhoneNumber
            ]

            func insertPhoneNumberChangeInteraction(_ thread: TSThread) {
                guard thread.shouldThreadBeVisible else {
                    // Skip if thread is soft deleted or otherwise not user visible.
                    return
                }
                let threadAssociatedData = ThreadAssociatedData.fetchOrDefault(for: thread,
                                                                                  transaction: transaction.asAnyRead)
                guard !threadAssociatedData.isArchived else {
                    // Skip if thread is archived.
                    return
                }
                let infoMessage = TSInfoMessage(thread: thread,
                                                messageType: .phoneNumberChange,
                                                infoMessageUserInfo: infoMessageUserInfo)
                infoMessage.wasRead = true
                infoMessage.anyInsert(transaction: transaction.asAnyWrite)
            }

            // We need to use the newPhoneNumber; we've just updated TSThread and TSGroupMember.
            let newAddress = SignalServiceAddress(uuid: newUuid, phoneNumber: newPhoneNumber)

            TSGroupThread.enumerateGroupThreads(
                with: newAddress,
                transaction: transaction.asAnyRead
            ) { thread, _ in
                guard thread.groupMembership.isFullMember(newUuid) else {
                    // Only insert "change phone number" interactions for
                    // full members.
                    return
                }
                insertPhoneNumberChangeInteraction(thread)
            }

            // Only insert "change phone number" interaction in 1:1 thread if it already exists.
            if let thread = TSContactThread.getWithContactAddress(newAddress,
                                                                  transaction: transaction.asAnyRead) {
                insertPhoneNumberChangeInteraction(thread)
            }
        }

        // TODO: we may need to do more here, this is just bear bones to make sure we
        // don't hold onto stale data with the old mapping.

        ModelReadCaches.shared.evacuateAllCaches()

        if let contactThread = AnyContactThreadFinder().contactThread(for: address, transaction: transaction.asAnyRead) {
            SDSDatabaseStorage.shared.touch(thread: contactThread, shouldReindex: true, transaction: transaction.asAnyWrite)
        }
        TSGroupMember.enumerateGroupMembers(for: address, transaction: transaction.asAnyRead) { member, _ in
            GRDBFullTextSearchFinder.modelWasUpdated(model: member, transaction: transaction)
        }

        // Update SignalServiceAddressCache with the new uuid <-> phone number mapping
        let recipientUUID = self.recipientUUID

        if let newUuidString = recipientUUID,
           let newUuid = UUID(uuidString: newUuidString) {

            // If we're removing the phone number from a phone-number-only
            // recipient (e.g. assigning a mock uuid), remove any old mapping
            // from the SignalServiceAddressCache.
            if newPhoneNumber == nil,
               let oldPhoneNumber = oldPhoneNumber,
               oldUuid == nil {
                Self.signalServiceAddressCache.removeMapping(phoneNumber: oldPhoneNumber)
            }

            Self.signalServiceAddressCache.updateMapping(uuid: newUuid, phoneNumber: newPhoneNumber)

            // Verify the mapping change worked as expected.
            owsAssertDebug(SignalServiceAddress(uuid: newUuid).phoneNumber == newPhoneNumber)
            if let newPhoneNumber = newPhoneNumber {
                owsAssertDebug(SignalServiceAddress(phoneNumber: newPhoneNumber).uuid == newUuid)
            }
            if let oldPhoneNumber = oldPhoneNumber {
                // SignalServiceAddressCache's mapping may have already been updated,
                // So the uuid for the oldPhoneNumber may already be associated with
                // a new uuid.
                owsAssertDebug(SignalServiceAddress(phoneNumber: oldPhoneNumber).uuid != newUuid)
            }

            let newAddress = SignalServiceAddress(uuid: newUuid, phoneNumber: newPhoneNumber)

            if !newAddress.isLocalAddress {
                self.versionedProfiles.clearProfileKeyCredential(for: newAddress,
                                                                    transaction: transaction.asAnyWrite)

                if let oldPhoneNumber = oldPhoneNumber?.nilIfEmpty {
                    // The "obsolete" address is the address the old phone number.
                    // It is _NOT_ the old (uuid, phone number) pair for this uuid.
                    let obsoleteAddress = SignalServiceAddress(uuidString: nil, phoneNumber: oldPhoneNumber)
                    owsAssertDebug(newAddress.uuid != obsoleteAddress.uuid)
                    owsAssertDebug(newAddress.phoneNumber != obsoleteAddress.phoneNumber)

                    // Remove old address from profile whitelist.
                    profileManager.removeUser(fromProfileWhitelist: obsoleteAddress,
                                              userProfileWriter: .changePhoneNumber,
                                              transaction: transaction.asAnyWrite)
                }

                // Ensure new address reflect's old address' profile whitelist state.
                if isWhitelisted {
                    profileManager.addUser(toProfileWhitelist: newAddress,
                                           userProfileWriter: .changePhoneNumber,
                                           transaction: transaction.asAnyWrite)
                } else {
                    profileManager.removeUser(fromProfileWhitelist: newAddress,
                                              userProfileWriter: .changePhoneNumber,
                                              transaction: transaction.asAnyWrite)
                }
            }
        } else {
            owsFailDebug("Missing or invalid UUID")
        }

        if let oldPhoneNumber = oldPhoneNumber?.nilIfEmpty {
            // The "obsolete" address is the address the old phone number.
            // It is _NOT_ the old (uuid, phone number) pair for this uuid.
            let obsoleteAddress = SignalServiceAddress(uuidString: nil, phoneNumber: oldPhoneNumber)
            if let newUuidString = recipientUUID,
               let newUuid = UUID(uuidString: newUuidString) {
                let newAddress = SignalServiceAddress(uuid: newUuid, phoneNumber: newPhoneNumber)
                owsAssertDebug(newAddress.uuid != obsoleteAddress.uuid)
                owsAssertDebug(newAddress.phoneNumber != obsoleteAddress.phoneNumber)
            }

            ProfileFetcherJob.clearProfileState(address: obsoleteAddress, transaction: transaction.asAnyWrite)

            transaction.addAsyncCompletion(queue: .global()) {
                Self.udManager.setUnidentifiedAccessMode(.unknown, address: obsoleteAddress)

                if !CurrentAppContext().isRunningTests {
                    ProfileFetcherJob.fetchProfile(address: obsoleteAddress, ignoreThrottling: true)
                }
            }
        }

        if let newUuidString = recipientUUID,
           let newUuid = UUID(uuidString: newUuidString) {
            let newAddress = SignalServiceAddress(uuid: newUuid, phoneNumber: newPhoneNumber)

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

    private static func updateDBTableMappings(newPhoneNumber: String?,
                                              oldPhoneNumber: String?,
                                              newUuid: String?,
                                              transaction: GRDBWriteTransaction) {

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
            transaction.executeUpdate(sql: sql, arguments: arguments)
        }
    }

    // There is no instance of SignalRecipient for the new uuid,
    // but other db tables might have mappings for the new uuid.
    // We need to clear that out.
    @objc
    public static func clearDBMappings(forUuid uuidString: String,
                                       transaction: SDSAnyWriteTransaction) {
        guard let uuidString = uuidString.nilIfEmpty else {
            owsFailDebug("Invalid phoneNumber.")
            return
        }

        Logger.info("uuidString: \(uuidString)")

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
                let arguments: StatementArguments = [uuidString]
                transaction.executeUpdate(sql: sql, arguments: arguments)
            }

            // If a record does _NOT_ have a valid phoneNumber, we apply a mock uuid.
            let sql = """
                UPDATE \(databaseTableName)
                SET \(uuidColumn) = ?
                WHERE \(uuidColumn) = ?
                AND \(phoneNumberColumn) IS NULL
                """
            let arguments: StatementArguments = [mockUuid, uuidString]
            transaction.executeUpdate(sql: sql, arguments: arguments)
        }
    }

    // There is no instance of SignalRecipient for the new phone number,
    // but other db tables might have mappings for the new phone number.
    // We need to clear that out.
    @objc
    public static func clearDBMappings(forPhoneNumber phoneNumber: String,
                                       transaction: SDSAnyWriteTransaction) {
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
                transaction.executeUpdate(sql: sql, arguments: arguments)
            }

            // If a record does _NOT_ have a valid uuid, we clear the phoneNumber and apply a mock uuid.
            let sql = """
                UPDATE \(databaseTableName)
                SET \(uuidColumn) = ?, \(phoneNumberColumn) = NULL
                WHERE \(phoneNumberColumn) = ?
                AND \(uuidColumn) IS NULL
                """
            let arguments: StatementArguments = [mockUuid, phoneNumber]
            transaction.executeUpdate(sql: sql, arguments: arguments)
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
                DBTableMapping(databaseTableName: "\(TSGroupMember.databaseTableName)",
                               uuidColumn: "\(TSGroupMember.columnName(.uuidString))",
                               phoneNumberColumn: "\(TSGroupMember.columnName(.phoneNumber))"),
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
