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

    private static let storageServiceUnregisteredThreshold = kMonthInterval

    @objc
    public var shouldBeRepresentedInStorageService: Bool {
        guard !isRegistered else { return true }

        guard let unregisteredAtTimestamp = unregisteredAtTimestamp?.uint64Value else {
            return false
        }

        return Date().timeIntervalSince(Date(millisecondsSince1970: unregisteredAtTimestamp)) <= Self.storageServiceUnregisteredThreshold
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

    @objc
    public func markAsRegisteredWithLocalSource(transaction: SDSAnyWriteTransaction) {
        markAsRegistered(transaction: transaction)
    }

    public func markAsRegistered(
        source: SignalRecipientSource = .local,
        deviceId: UInt32 = OWSDevicePrimaryDeviceId,
        transaction: SDSAnyWriteTransaction
    ) {
        // Always add the primary device ID if we're adding any other.
        let deviceIds: Set<UInt32> = [deviceId, OWSDevicePrimaryDeviceId]

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

    @objc
    @discardableResult
    public class func fetchOrCreate(
        for address: SignalServiceAddress,
        trustLevel: SignalRecipientTrustLevel,
        transaction: SDSAnyWriteTransaction
    ) -> SignalRecipient {
        owsAssertDebug(address.isValid)

        switch trustLevel {
        case .low:
            return lowTrustRecipient(for: address, transaction: transaction)
        case .high:
            return highTrustRecipient(for: address, transaction: transaction)
        }
    }

    /// Fetches (or creates) a low-trust recipient.
    ///
    /// Low trust fetches don't indicate any relation between the UUID and phone
    /// number that are part of the address. They might be the same account, but
    /// they also may refer to different accounts.
    ///
    /// In this method, we first try to fetch based on the UUID. If there's a
    /// recipient for the UUID, we return it as-is, even if it has a different
    /// phone number than `address`. If there's no recipient for the UUID (but
    /// there is a UUID), we'll create a UUID-only recipient (i.e., we ignore
    /// the phone number on `address`).
    ///
    /// Otherwise, we try to fetch based on the phone number. If there's a
    /// recipient for the phone number, we return it as-is (even if it already
    /// has a UUID specified). If there's not a recipient, we'll create a phone
    /// number-only recipient (b/c the address has no UUID).
    private static func lowTrustRecipient(
        for address: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) -> SignalRecipient {
        owsAssertDebug(address.isValid)

        let finder = AnySignalRecipientFinder()

        if let uuidInstance = finder.signalRecipientForUUID(address.uuid, transaction: transaction) {
            return uuidInstance
        }
        if let uuidString = address.uuidString {
            Logger.debug("creating new low trust recipient with UUID: \(uuidString)")

            let newInstance = SignalRecipient(uuidString: uuidString)
            newInstance.anyInsert(transaction: transaction)

            return newInstance
        }
        if let phoneNumberInstance = finder.signalRecipientForPhoneNumber(address.phoneNumber, transaction: transaction) {
            return phoneNumberInstance
        }
        owsAssertDebug(address.phoneNumber != nil)
        Logger.debug("creating new low trust recipient with phoneNumber: \(String(describing: address.phoneNumber))")

        let newInstance = SignalRecipient(address: address)
        newInstance.anyInsert(transaction: transaction)

        return newInstance
    }

    /// Fetches (or creates) a high-trust recipient.
    ///
    /// High trust fetches indicate that the uuid & phone number represented by
    /// `address` refer to the same account. As part of the fetch, the database
    /// will be updated to reflect that relationship.
    ///
    /// In general, the rules we follow when applying changes are:
    ///
    /// * ACIs are immutable and representative of an account. We never change
    ///   the ACI of a SignalRecipient from one ACI to another; instead we
    ///   create a new SignalRecipient. (However, the ACI *may* change from a
    ///   nil value to a nonnil value.)
    ///
    /// * Phone numbers are transient and can move freely between UUIDs. When
    ///   they do, we must backfill the database to reflect the change.
    private static func highTrustRecipient(
        for address: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) -> SignalRecipient {
        owsAssertDebug(address.isValid)

        let phoneNumberInstance = AnySignalRecipientFinder()
            .signalRecipientForPhoneNumber(address.phoneNumber, transaction: transaction)
        let uuidInstance = AnySignalRecipientFinder()
            .signalRecipientForUUID(address.uuid, transaction: transaction)

        var shouldUpdate = false
        let existingInstance: SignalRecipient?

        if let uuidInstance, let phoneNumberInstance {
            if uuidInstance.uniqueId == phoneNumberInstance.uniqueId {
                // These are the same and both fully complete; we have no extra work to do.
                existingInstance = phoneNumberInstance

            } else if phoneNumberInstance.recipientUUID == nil && uuidInstance.recipientPhoneNumber == nil {
                // These are the same, but not fully complete; we need to merge them.
                existingInstance = merge(
                    uuidInstance: uuidInstance,
                    phoneNumberInstance: phoneNumberInstance,
                    transaction: transaction
                )
                shouldUpdate = true

                // Since uuidInstance is nonnil, we must have fetched it with a nonnil
                // uuid, but the type system doesn't (currently) know this.
                guard let addressUuid = address.uuid else {
                    owsFail("Missing uuid with non-nil result")
                }

                // Update the SignalServiceAddressCache mappings with the now fully-qualified recipient.
                signalServiceAddressCache.updateMapping(uuid: addressUuid, phoneNumber: address.phoneNumber, transaction: transaction)

            } else {
                // The UUID differs between the two records; we need to migrate the phone
                // number to the UUID instance.
                Logger.warn("Learned phoneNumber (\(String(describing: address.phoneNumber))) now belongs to uuid (\(String(describing: address.uuid)).")

                // Ordering is critical here. We must remove the phone number from the old
                // recipient *before* we assign the phone number to the new recipient in
                // case there are any legacy phone number-only records in the database.

                shouldUpdate = true

                phoneNumberInstance.changePhoneNumber(nil, transaction: transaction.unwrapGrdbWrite)
                phoneNumberInstance.anyOverwritingUpdate(transaction: transaction)

                // We've already used phoneNumberInstance.changePhoneNumber() above to
                // ensure that phoneNumberInstance does not use address.phoneNumber.
                //
                // However, phoneNumberInstance.changePhoneNumber() will only update
                // mappings in other database tables that exactly match the address
                // components of phoneNumberInstance.
                //
                // The mappings in other tables might not exactly match the mappings in the
                // SignalRecipient table. Therefore, to avoid crashes and other mapping
                // problems, we need to ensure that no other db tables have a mapping that
                // uses address.phoneNumber _before_ we use
                // uuidInstance.changePhoneNumber() with address.phoneNumber.

                // Since phoneNumberInstance is nonnil, we must have fetched it with a
                // nonnil phone number, but the type system doesn't (currently) know this.
                guard let addressPhoneNumber = address.phoneNumber else {
                    owsFail("Missing phone number with non-nil result")
                }

                Self.clearDBMappings(forPhoneNumber: addressPhoneNumber, transaction: transaction)

                uuidInstance.changePhoneNumber(address.phoneNumber, transaction: transaction.unwrapGrdbWrite)

                existingInstance = uuidInstance
            }
        } else if let phoneNumberInstance {
            if let uuid = address.uuid {
                // There is no instance of SignalRecipient for the new uuid, but other db
                // tables might have mappings for the new uuid. We need to clear that out.
                Self.clearDBMappings(forUuid: uuid, transaction: transaction)
            }

            if address.uuidString != nil, phoneNumberInstance.recipientUUID != nil {
                Logger.warn("Learned phoneNumber (\(String(describing: address.phoneNumber))) now belongs to uuid (\(String(describing: address.uuid)).")

                // The UUID associated with this phone number has changed, we must clear
                // the phone number from this instance and create a new instance.
                phoneNumberInstance.changePhoneNumber(nil, transaction: transaction.unwrapGrdbWrite)
                phoneNumberInstance.anyOverwritingUpdate(transaction: transaction)
                // phoneNumberInstance is no longer associated with the phone number. We
                // will create a "newInstance" for the new (uuid, phone number) below.
                existingInstance = nil
            } else {
                if let uuid = address.uuid {
                    Logger.warn("Learned uuid (\(uuid.uuidString)) is associated with phoneNumber (\(String(describing: address.phoneNumber)).")

                    shouldUpdate = true
                    phoneNumberInstance.recipientUUID = uuid.uuidString

                    // Update the SignalServiceAddressCache mappings with the now fully-qualified recipient.
                    signalServiceAddressCache.updateMapping(uuid: uuid, phoneNumber: address.phoneNumber, transaction: transaction)
                }

                existingInstance = phoneNumberInstance
            }
        } else if let uuidInstance {
            if let phoneNumber = address.phoneNumber {
                // We need to update the phone number on uuidInstance.

                // There is no instance of SignalRecipient for the new phone number, but
                // other db tables might have mappings for the new phone number. We need to
                // clear that out.
                Self.clearDBMappings(forPhoneNumber: phoneNumber, transaction: transaction)

                if let oldPhoneNumber = uuidInstance.recipientPhoneNumber {
                    Logger.warn("Learned uuid (\(String(describing: address.uuidString)) changed from old phoneNumber (\(oldPhoneNumber)) to new phoneNumber (\(phoneNumber))")
                } else {
                    Logger.warn("Learned uuid (\(String(describing: address.uuidString)) is associated with phoneNumber (\(phoneNumber)).")
                }

                shouldUpdate = true
                uuidInstance.changePhoneNumber(address.phoneNumber, transaction: transaction.unwrapGrdbWrite)
            } else {
                // No work is necessary.
            }

            existingInstance = uuidInstance
        } else {
            existingInstance = nil
        }

        guard let existingInstance else {
            Logger.debug("creating new high trust recipient with address: \(address)")

            let newInstance = SignalRecipient(address: address)
            newInstance.anyInsert(transaction: transaction)

            if let uuid = address.uuid {
                signalServiceAddressCache.updateMapping(uuid: uuid, phoneNumber: address.phoneNumber, transaction: transaction)
            }

            return newInstance
        }

        // Record the updated contact in the social graph
        if shouldUpdate {
            existingInstance.anyOverwritingUpdate(transaction: transaction)
            storageServiceManager.recordPendingUpdates(updatedAccountIds: [existingInstance.accountId])
        }

        return existingInstance
    }

    private static func merge(
        uuidInstance: SignalRecipient,
        phoneNumberInstance: SignalRecipient,
        transaction: SDSAnyWriteTransaction
    ) -> SignalRecipient {
        owsAssertDebug(uuidInstance.recipientPhoneNumber == nil || uuidInstance.recipientPhoneNumber == phoneNumberInstance.recipientPhoneNumber)
        owsAssertDebug(phoneNumberInstance.recipientUUID == nil || phoneNumberInstance.recipientUUID == uuidInstance.recipientUUID)

        // We have separate recipients in the db for the uuid and phone number.
        // There isn't an ideal way to do this, but we need to converge on one
        // recipient and discard the other.
        //
        // TODO: Should we clean up any state related to the discarded recipient?

        // We try to preserve the recipient that has a session.
        // (Note that we don't check for PNI sessions; we always prefer the ACI session there.)
        let sessionStore = signalProtocolStore(for: .aci).sessionStore
        let hasSessionForUuid = sessionStore.containsActiveSession(
            forAccountId: uuidInstance.accountId,
            deviceId: Int32(OWSDevicePrimaryDeviceId),
            transaction: transaction
        )
        let hasSessionForPhoneNumber = sessionStore.containsActiveSession(
            forAccountId: phoneNumberInstance.accountId,
            deviceId: Int32(OWSDevicePrimaryDeviceId),
            transaction: transaction
        )

        if DebugFlags.verboseSignalRecipientLogging {
            Logger.info("phoneNumberInstance: \(phoneNumberInstance)")
            Logger.info("uuidInstance: \(uuidInstance)")
            Logger.info("hasSessionForUuid: \(hasSessionForUuid)")
            Logger.info("hasSessionForPhoneNumber: \(hasSessionForPhoneNumber)")
        }

        let winningInstance: SignalRecipient

        // We want to retain the phone number recipient only if it has a session
        // and the UUID recipient doesn't. Historically, we tried to be clever and
        // pick the session that had seen more use, but merging sessions should
        // only happen in exceptional circumstances these days.
        if hasSessionForUuid {
            Logger.warn("Discarding phone number recipient in favor of uuid recipient.")
            winningInstance = uuidInstance
            phoneNumberInstance.anyRemove(transaction: transaction)
        } else {
            Logger.warn("Discarding uuid recipient in favor of phone number recipient.")
            winningInstance = phoneNumberInstance
            uuidInstance.anyRemove(transaction: transaction)
        }

        // Make sure the winning instance is fully qualified.
        winningInstance.recipientPhoneNumber = phoneNumberInstance.recipientPhoneNumber
        winningInstance.recipientUUID = uuidInstance.recipientUUID

        OWSUserProfile.mergeUserProfilesIfNecessary(for: winningInstance.address, transaction: transaction)

        return winningInstance
    }

    // MARK: -

    public static let phoneNumberDidChange = Notification.Name("phoneNumberDidChange")
    public static let notificationKeyPhoneNumber = "phoneNumber"
    public static let notificationKeyUUID = "UUID"

    private func changePhoneNumber(_ newPhoneNumber: String?, transaction: GRDBWriteTransaction) {
        let oldPhoneNumber = recipientPhoneNumber?.nilIfEmpty
        let oldUuidString = recipientUUID
        let oldUuid: UUID? = oldUuidString.flatMap { UUID(uuidString: $0) }
        let oldAddress = address

        let isWhitelisted = profileManager.isUser(inProfileWhitelist: oldAddress, transaction: transaction.asAnyRead)

        let newPhoneNumber = newPhoneNumber?.nilIfEmpty

        if newPhoneNumber == nil && oldUuidString == nil {
            Logger.warn("Clearing out the phone number on a recipient with no UUID. uuid: \(String(describing: oldUuidString)), phoneNumber: \(String(describing: oldPhoneNumber)) -> \(String(describing: newPhoneNumber)) ")
            // Fill in a random UUID, so we can complete the change and maintain a common
            // association for all the records and not leave them dangling. This should
            // in general never happen.
            recipientUUID = UUID().uuidString
        } else {
            Logger.info("uuid: \(String(describing: oldUuidString)), phoneNumber: \(String(describing: oldPhoneNumber)) -> \(String(describing: newPhoneNumber))")
        }

        recipientPhoneNumber = newPhoneNumber

        let newUuidString = recipientUUID
        let newUuid: UUID? = newUuidString.flatMap { UUID(uuidString: $0) }
        let newAddress = address

        Logger.info("uuid: \(String(describing: oldUuidString)) ->  \(String(describing: newUuidString)), phoneNumber: \(String(describing: oldPhoneNumber)) -> \(String(describing: newPhoneNumber))")

        transaction.addAsyncCompletion(queue: .global()) {
            let phoneNumbers: [String] = [oldPhoneNumber, newPhoneNumber].compactMap { $0 }
            for phoneNumber in phoneNumbers {
                var userInfo: [AnyHashable: Any] = [
                    Self.notificationKeyPhoneNumber: phoneNumber
                ]
                if let newUuidString {
                    userInfo[Self.notificationKeyUUID] = newUuidString
                }
                NotificationCenter.default.postNotificationNameAsync(Self.phoneNumberDidChange,
                                                                     object: nil,
                                                                     userInfo: userInfo)
            }
        }

        Self.updateDBTableMappings(newPhoneNumber: newPhoneNumber,
                                   oldPhoneNumber: oldPhoneNumber,
                                   newUuid: newUuidString,
                                   transaction: transaction)

        if let newUuid,
           let localUuid = tsAccountManager.localUuid,
           localUuid != newUuid,
           let oldPhoneNumber,
           let newPhoneNumber {
            let infoMessageUserInfo: [InfoMessageUserInfoKey: Any] = [
                .changePhoneNumberUuid: newUuid.uuidString,
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

        if let contactThread = AnyContactThreadFinder().contactThread(for: newAddress, transaction: transaction.asAnyRead) {
            SDSDatabaseStorage.shared.touch(thread: contactThread, shouldReindex: true, transaction: transaction.asAnyWrite)
        }
        TSGroupMember.enumerateGroupMembers(for: newAddress, transaction: transaction.asAnyRead) { member, _ in
            GRDBFullTextSearchFinder.modelWasUpdated(model: member, transaction: transaction)
        }

        if let newUuid {

            // If we're removing the phone number from a phone-number-only
            // recipient (e.g. assigning a mock uuid), remove any old mapping
            // from the SignalServiceAddressCache.
            if newPhoneNumber == nil, let oldPhoneNumber, oldUuid == nil {
                Self.signalServiceAddressCache.removeMapping(phoneNumber: oldPhoneNumber)
            }

            Self.signalServiceAddressCache.updateMapping(uuid: newUuid, phoneNumber: newPhoneNumber, transaction: transaction.asAnyWrite)

            // Verify the mapping change worked as expected.
            owsAssertDebug(SignalServiceAddress(uuid: newUuid).phoneNumber == newPhoneNumber)
            if let newPhoneNumber {
                owsAssertDebug(SignalServiceAddress(phoneNumber: newPhoneNumber).uuid == newUuid)
            }
            if let oldPhoneNumber {
                // SignalServiceAddressCache's mapping may have already been updated,
                // So the uuid for the oldPhoneNumber may already be associated with
                // a new uuid.
                owsAssertDebug(SignalServiceAddress(phoneNumber: oldPhoneNumber).uuid != newUuid)
            }

            if !newAddress.isLocalAddress {
                self.versionedProfiles.clearProfileKeyCredential(for: newAddress, transaction: transaction.asAnyWrite)

                if let oldPhoneNumber {
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

        if let oldPhoneNumber {
            // The "obsolete" address is the address the old phone number.
            // It is _NOT_ the old (uuid, phone number) pair for this uuid.
            let obsoleteAddress = SignalServiceAddress(uuidString: nil, phoneNumber: oldPhoneNumber)
            if newUuid != nil {
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

        if newUuid != nil {
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
            transaction.execute(sql: sql, arguments: arguments)
        }
    }

    // There is no instance of SignalRecipient for the new uuid,
    // but other db tables might have mappings for the new uuid.
    // We need to clear that out.
    private static func clearDBMappings(forUuid uuid: UUID, transaction: SDSAnyWriteTransaction) {
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
    private static func clearDBMappings(forPhoneNumber phoneNumber: String, transaction: SDSAnyWriteTransaction) {
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
