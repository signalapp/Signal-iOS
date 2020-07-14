//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import GRDB

extension SignalRecipient {
    @objc
    func changePhoneNumber(_ phoneNumber: String?, transaction: GRDBWriteTransaction) {
        if phoneNumber == nil && recipientUUID == nil {
            owsFailDebug("Unexpectedly tried to clear out the phone number on a recipient with no UUID")
            // Fill in a random UUID, so we can complete the change and maintain a common
            // association for all the records and not leave them dangling. This should
            // in general never happen.
            recipientUUID = UUID().uuidString
        }

        let oldPhoneNumber = recipientPhoneNumber
        recipientPhoneNumber = phoneNumber

        let arguments: StatementArguments = [recipientUUID, recipientPhoneNumber, recipientUUID, oldPhoneNumber]

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

        // TODO: we probably need to some kind of cache purge / update..
    }
}
