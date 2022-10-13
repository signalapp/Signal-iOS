//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
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
        if !shouldBeSaved || isDynamicInteraction || self is OWSOutgoingSyncMessage {
            owsFailDebug("Unexpected interaction type: \(type(of: self))")
            return false
        }

        switch self {
        case let errorMessage as TSErrorMessage:
            switch errorMessage.errorType {
            case .nonBlockingIdentityChange:
                // Otherwise all group threads with the recipient will percolate to the top of the inbox, even though
                // there was no meaningful interaction.
                return false
            case .decryptionFailure:
                if errorMessage is OWSRecoverableDecryptionPlaceholder {
                    // Replaceable interactions should never be shown to the user
                    return false
                } else {
                    return true
                }
            default:
                return true
            }
        case let infoMessage as TSInfoMessage:
            switch infoMessage.messageType {
            case .verificationStateChange,
                 .profileUpdate,
                 .phoneNumberChange:
                return false
            case .typeGroupUpdate:
                guard let updates = infoMessage.groupUpdateItems(transaction: transaction) else {
                    return true
                }
                return updates.contains { $0.shouldAppearInInbox }
            default:
                return true
            }
        case let message as TSMessage:
            return !message.isGroupStoryReply
        default:
            return true
        }
    }

    /// Returns `true` if the receiver was inserted into the database by updating the placeholder
    /// Returns `false` if the receiver needs to be inserted into the database.
    private func updatePlaceholder(
        from sender: SignalServiceAddress,
        transaction: SDSAnyWriteTransaction
    ) -> Bool {
        let placeholders: [TSInteraction]
        do {
            placeholders = try InteractionFinder.interactions(
                withTimestamp: timestamp,
                filter: { candidate in
                    guard let placeholder = candidate as? OWSRecoverableDecryptionPlaceholder else { return false }
                    return placeholder.sender == sender && placeholder.timestamp == self.timestamp
                },
                transaction: transaction
            )
        } catch {
            owsFailDebug("Failed to fetch placeholder interaction: \(error)")
            return false
        }

        guard !placeholders.isEmpty else {
            return false
        }

        Logger.info("Fetched placeholder with timestamp: \(timestamp) from sender: \(sender). Performing replacement...")
        guard let placeholder = (placeholders.first as? OWSRecoverableDecryptionPlaceholder) else {
            owsFailDebug("Unexpected interaction type")
            return false
        }

        if placeholder.supportsReplacement {
            placeholder.replaceWithInteraction(self, writeTx: transaction)
            return true
        } else {
            Logger.info("Placeholder not eligible for replacement, deleting.")
            placeholder.anyRemove(transaction: transaction)
            return false
        }
    }

    @objc
    public func insertOrReplacePlaceholder(from sender: SignalServiceAddress, transaction: SDSAnyWriteTransaction) {
        if updatePlaceholder(from: sender, transaction: transaction) {
            Logger.info("Successfully replaced placeholder with interaction: \(timestamp)")
        } else {
            anyInsert(transaction: transaction)

            // Replaced interactions will inherit the existing sortId
            // Inserted interactions will be assigned a sortId from SQLite, but
            // we need to fetch from the database.
            owsAssertDebug(sortId == 0)
            fillInMissingSortIdForJustInsertedInteraction(transaction: transaction)
            owsAssertDebug(sortId > 0)
        }
    }
}
