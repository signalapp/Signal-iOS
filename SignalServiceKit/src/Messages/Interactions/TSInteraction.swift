//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit

extension TSInteraction {

    @objc
    public func fillInMissingSortIdForJustInsertedInteraction(transaction: SDSAnyReadTransaction) {
        switch transaction.readTransaction {
        case .grdbRead(let grdbRead):
            fillInMissingSortIdForJustInsertedInteraction(transaction: grdbRead)
        }
    }

    private func fillInMissingSortIdForJustInsertedInteraction(transaction: GRDBReadTransaction) {
        guard self.sortId == 0 else {
            owsFailDebug("Unexpected sortId: \(sortId).")
            return
        }
        guard let sortId = BaseModel.grdbIdByUniqueId(tableMetadata: TSInteractionSerializer.table,
                                                      uniqueIdColumnName: InteractionRecord.columnName(.uniqueId),
                                                      uniqueIdColumnValue: self.uniqueId,
                                                      transaction: transaction) else {
            owsFailDebug("Missing sortId.")
            return
        }
        guard sortId > 0, sortId <= UInt64.max else {
            owsFailDebug("Invalid sortId: \(sortId).")
            return
        }
        self.replaceSortId(UInt64(sortId))
        owsAssertDebug(self.sortId > 0)
    }

    /// Returns whether the given interaction should pull a conversation to the top of the list and
    /// marked unread.
    ///
    /// This operation necessarily happens after the interaction has been pulled out of the
    /// database. If possible, they should also be filtered as part of the database queries in the
    /// `mostRecentInteractionForInbox(transaction:)` implementations in InteractionFinder.swift.
    @objc
    public func shouldAppearInInbox(transaction: SDSAnyReadTransaction) -> Bool {
        if !shouldBeSaved || isDynamicInteraction() || self is OWSOutgoingSyncMessage {
            owsFailDebug("Unexpected interaction type: \(type(of: self))")
            return false
        }

        switch self {
        case let errorMessage as TSErrorMessage:
            // Otherwise all group threads with the recipient will percolate to the top of the inbox, even though
            // there was no meaningful interaction.
            return errorMessage.errorType != .nonBlockingIdentityChange

        case let infoMessage as TSInfoMessage:
            switch infoMessage.messageType {
            case .verificationStateChange,
                 .profileUpdate:
                return false
            case .typeGroupUpdate:
                guard let updates = infoMessage.groupUpdateItems(transaction: transaction) else {
                    return true
                }
                return updates.contains { $0.shouldAppearInInbox }
            default:
                return true
            }

        default:
            return true
        }
    }

    private func replacePlaceholder(
        from sender: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) -> Bool {
        do {
            let placeholders = try InteractionFinder.interactions(
                withTimestamp: timestamp,
                filter: { candidate in
                    guard let placeholder = candidate as? OWSRecoverableDecryptionPlaceholder else { return false }
                    return placeholder.sender == sender && placeholder.timestamp == self.timestamp
                },
                transaction: transaction
            )

            if let placeholder = (placeholders.first as? OWSRecoverableDecryptionPlaceholder) {
                owsAssertDebug(placeholders.count == 1)
                placeholder.replaceWithInteraction(self, writeTx: transaction)
                return true
            }
        } catch {
            owsFailDebug("\(error)")
        }
        return false
    }

    @objc
    public func insertOrReplacePlaceholder(from sender: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        if replacePlaceholder(from: sender, transaction: transaction) {
            // Done!
        } else {
            anyInsert(transaction: transaction)
        }
    }

    @objc
    public func upsertOrReplacePlaceholder(from sender: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        if replacePlaceholder(from: sender, transaction: transaction) {
            // Done!
        } else {
            anyUpsert(transaction: transaction)
        }
    }
}
