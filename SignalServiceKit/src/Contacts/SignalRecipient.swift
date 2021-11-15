//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB
import SignalCoreKit

extension SignalRecipient {

    @objc
    public static let phoneNumberDidChange = Notification.Name("phoneNumberDidChange")
    @objc
    public static let notificationKeyPhoneNumber = "phoneNumber"
    @objc
    public static let notificationKeyUUID = "UUID"

    @objc
    func changePhoneNumber(_ newPhoneNumber: String?, transaction: GRDBWriteTransaction) {

        let oldPhoneNumber = recipientPhoneNumber
        let oldUuid = recipientUUID
        Logger.info("uuid: \(String(describing: self.recipientUUID)), phoneNumber: \(String(describing: oldPhoneNumber)) -> \(String(describing: newPhoneNumber)) ")

        let isWhitelisted = profileManager.isUser(inProfileWhitelist: self.address,
                                                  transaction: transaction.asAnyRead)

        if newPhoneNumber == nil && recipientUUID == nil {
            owsFailDebug("Unexpectedly tried to clear out the phone number on a recipient with no UUID")
            // Fill in a random UUID, so we can complete the change and maintain a common
            // association for all the records and not leave them dangling. This should
            // in general never happen.
            recipientUUID = UUID().uuidString
            Logger.info("uuid: \(String(describing: self.recipientUUID)), phoneNumber: \(String(describing: oldPhoneNumber)) -> \(String(describing: newPhoneNumber)) ")
        }

        recipientPhoneNumber = newPhoneNumber

        let newUuid = self.recipientUUID
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

        let arguments: StatementArguments = [recipientUUID, recipientPhoneNumber, recipientUUID, oldPhoneNumber]

        if let newUuid = newUuid?.nilIfEmpty,
           let localUuid = tsAccountManager.localUuid,
           localUuid.uuidString != newUuid,
           let oldPhoneNumber = oldPhoneNumber?.nilIfEmpty,
           let newPhoneNumber = newPhoneNumber?.nilIfEmpty {
            let infoMessageUserInfo: [InfoMessageUserInfoKey: Any] = [
                .changePhoneNumberUuid: newUuid,
                .changePhoneNumberOld: oldPhoneNumber,
                .changePhoneNumberNew: newPhoneNumber
            ]
            let uuidAddress = SignalServiceAddress(uuidString: newUuid)
            let contactThread = TSContactThread.getOrCreateThread(withContactAddress: uuidAddress,
                                                                  transaction: transaction.asAnyWrite)
            let infoMessage = TSInfoMessage(thread: contactThread,
                                            messageType: .phoneNumberChange,
                                            infoMessageUserInfo: infoMessageUserInfo)
            infoMessage.anyInsert(transaction: transaction.asAnyWrite)
        }

        // Update TSThread
        do {
            let sql = """
            UPDATE \(ThreadRecord.databaseTableName)
            SET \(threadColumn: .contactUUID) = ?, \(threadColumn: .contactPhoneNumber) = ?
            WHERE (\(threadColumn: .contactUUID) IS ? OR \(threadColumn: .contactUUID) IS NULL)
            AND (\(threadColumn: .contactPhoneNumber) IS ? OR \(threadColumn: .contactPhoneNumber) IS NULL)
            AND NOT (\(threadColumn: .contactUUID) IS NULL AND \(threadColumn: .contactPhoneNumber) IS NULL)
            """

            transaction.executeUpdate(sql: sql, arguments: arguments)
        }

        // Update TSGroupMember
        do {
            let sql = """
            UPDATE \(GroupMemberRecord.databaseTableName)
            SET \(groupMemberColumn: .uuidString) = ?, \(groupMemberColumn: .phoneNumber) = ?
            WHERE (\(groupMemberColumn: .uuidString) IS ? OR \(groupMemberColumn: .uuidString) IS NULL)
            AND (\(groupMemberColumn: .phoneNumber) IS ? OR \(groupMemberColumn: .phoneNumber) IS NULL)
            AND NOT (\(groupMemberColumn: .uuidString) IS NULL AND \(groupMemberColumn: .phoneNumber) IS NULL)
            """

            transaction.executeUpdate(sql: sql, arguments: arguments)
        }

        // Update OWSReaction
        do {
            let sql = """
            UPDATE \(ReactionRecord.databaseTableName)
            SET \(reactionColumn: .reactorUUID) = ?, \(reactionColumn: .reactorE164) = ?
            WHERE (\(reactionColumn: .reactorUUID) IS ? OR \(reactionColumn: .reactorUUID) IS NULL)
            AND (\(reactionColumn: .reactorE164) IS ? OR \(reactionColumn: .reactorE164) IS NULL)
            AND NOT (\(reactionColumn: .reactorUUID) IS NULL AND \(reactionColumn: .reactorE164) IS NULL)
            """

            transaction.executeUpdate(sql: sql, arguments: arguments)
        }

        // Update TSInteraction
        do {
            let sql = """
            UPDATE \(InteractionRecord.databaseTableName)
            SET \(interactionColumn: .authorUUID) = ?, \(interactionColumn: .authorPhoneNumber) = ?
            WHERE (\(interactionColumn: .authorUUID) IS ? OR \(interactionColumn: .authorUUID) IS NULL)
            AND (\(interactionColumn: .authorPhoneNumber) IS ? OR \(interactionColumn: .authorPhoneNumber) IS NULL)
            AND NOT (\(interactionColumn: .authorUUID) IS NULL AND \(interactionColumn: .authorPhoneNumber) IS NULL)
            """

            transaction.executeUpdate(sql: sql, arguments: arguments)
        }

        // Update OWSUserProfile
        do {
            let sql = """
            UPDATE \(UserProfileRecord.databaseTableName)
            SET \(userProfileColumn: .recipientUUID) = ?, \(userProfileColumn: .recipientPhoneNumber) = ?
            WHERE (\(userProfileColumn: .recipientUUID) IS ? OR \(userProfileColumn: .recipientUUID) IS NULL)
            AND (\(userProfileColumn: .recipientPhoneNumber) IS ? OR \(userProfileColumn: .recipientPhoneNumber) IS NULL)
            AND NOT (\(userProfileColumn: .recipientUUID) IS NULL AND \(userProfileColumn: .recipientPhoneNumber) IS NULL)
            """

            transaction.executeUpdate(
                sql: sql,
                arguments: [recipientUUID, recipientPhoneNumber, recipientUUID, oldPhoneNumber]
            )
        }

        // Update SignalAccount
        do {
            let sql = """
            UPDATE \(SignalAccountRecord.databaseTableName)
            SET \(signalAccountColumn: .recipientUUID) = ?, \(signalAccountColumn: .recipientPhoneNumber) = ?
            WHERE (\(signalAccountColumn: .recipientUUID) IS ? OR \(signalAccountColumn: .recipientUUID) IS NULL)
            AND (\(signalAccountColumn: .recipientPhoneNumber) IS ? OR \(signalAccountColumn: .recipientPhoneNumber) IS NULL)
            AND NOT (\(signalAccountColumn: .recipientUUID) IS NULL AND \(signalAccountColumn: .recipientPhoneNumber) IS NULL)
            """

            transaction.executeUpdate(
                sql: sql,
                arguments: [recipientUUID, recipientPhoneNumber, recipientUUID, oldPhoneNumber]
            )
        }

        // Update pending_read_receipts
        do {
            let sql = """
            UPDATE pending_read_receipts
            SET authorUuid = ?, authorPhoneNumber = ?
            WHERE (authorUuid IS ? OR authorUuid IS NULL)
            AND (authorPhoneNumber IS ? OR authorPhoneNumber IS NULL)
            AND NOT (authorUuid IS NULL AND authorPhoneNumber IS NULL)
            """

            transaction.executeUpdate(
                sql: sql,
                arguments: [recipientUUID, recipientPhoneNumber, recipientUUID, oldPhoneNumber]
            )
        }

        // TODO: we may need to do more here, this is just bear bones to make sure we
        // don't hold onto stale data with the old mapping.

        ModelReadCaches.shared.evacuateAllCaches()

        if let contactThread = AnyContactThreadFinder().contactThread(for: address, transaction: transaction.asAnyRead) {
            SDSDatabaseStorage.shared.touch(thread: contactThread, shouldReindex: true, transaction: transaction.asAnyWrite)
        }

        // Update SignalServiceAddressCache with the new uuid <-> phone number mapping
        let recipientUUID = self.recipientUUID
        if let newUuidString = recipientUUID,
            let newUuid = UUID(uuidString: newUuidString) {

            Self.signalServiceAddressCache.updateMapping(uuid: newUuid, phoneNumber: newPhoneNumber)

            // Verify the mapping change worked as expected.
            owsAssertDebug(SignalServiceAddress(uuid: newUuid).phoneNumber == newPhoneNumber)
            if let newPhoneNumber = newPhoneNumber {
                owsAssertDebug(SignalServiceAddress(phoneNumber: newPhoneNumber).uuid == newUuid)
            }
            if let oldPhoneNumber = oldPhoneNumber {
                owsAssertDebug(SignalServiceAddress(phoneNumber: oldPhoneNumber).uuid == nil)
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

        transaction.addAsyncCompletion(queue: .global()) {
            // Evacuate caches again once the transaction completes, in case
            // some kind of race occured.
            ModelReadCaches.shared.evacuateAllCaches()

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

                Self.databaseStorage.write { _ in
                    ProfileFetcherJob.clearProfileState(address: obsoleteAddress, transaction: transaction.asAnyWrite)
                }

                Self.udManager.setUnidentifiedAccessMode(.unknown, address: obsoleteAddress)

                if !CurrentAppContext().isRunningTests {
                    ProfileFetcherJob.fetchProfile(address: obsoleteAddress, ignoreThrottling: true)
                }
            }

            if let newUuidString = recipientUUID,
                let newUuid = UUID(uuidString: newUuidString) {
                let newAddress = SignalServiceAddress(uuid: newUuid, phoneNumber: newPhoneNumber)
                Self.udManager.setUnidentifiedAccessMode(.unknown, address: newAddress)
                if !CurrentAppContext().isRunningTests {
                    ProfileFetcherJob.fetchProfile(address: newAddress, ignoreThrottling: true)
                }
            }
        }
    }

    @objc
    public var addressComponentsDescription: String {
        var splits = [String]()
        if let uuid = self.recipientUUID?.nilIfEmpty {
            splits.append("uuid: " + uuid)
        }
        if let phoneNumber = self.recipientPhoneNumber?.nilIfEmpty {
            splits.append("phoneNumber: " + phoneNumber)
        }
        if let uuid = self.recipientUUID?.nilIfEmpty,
           tsAccountManager.localUuid?.uuidString == uuid {
            splits.append("*local address")
        }
        return "[" + splits.joined(separator: ", ") + "]"
    }
}
