//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension TSInteraction {

    public override func anyDidInsert(with tx: DBWriteTransaction) {
        super.anyDidInsert(with: tx)

        if let thread = thread(tx: tx) {
            thread.updateWithInsertedInteraction(self, tx: tx)
        }
    }

    public override func anyDidUpdate(with tx: DBWriteTransaction) {
        let interactionReadCache = SSKEnvironment.shared.modelReadCachesRef.interactionReadCache

        super.anyDidUpdate(with: tx)

        if let thread = thread(tx: tx) {
            thread.updateWithUpdatedInteraction(self, tx: tx)
        }

        interactionReadCache.didUpdate(interaction: self, transaction: tx)
    }

    // MARK: -

    @objc
    public func fillInMissingSortIdForJustInsertedInteraction(transaction: DBReadTransaction) {
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

    /// Returns `true` if the receiver was inserted into the database by updating the placeholder
    /// Returns `false` if the receiver needs to be inserted into the database.
    private func updatePlaceholder(
        from sender: SignalServiceAddress,
        transaction: DBWriteTransaction
    ) -> Bool {
        let placeholders: [OWSRecoverableDecryptionPlaceholder]
        do {
            placeholders = try InteractionFinder.fetchInteractions(
                timestamp: timestamp,
                transaction: transaction
            ).compactMap { candidate -> OWSRecoverableDecryptionPlaceholder? in
                guard let placeholder = candidate as? OWSRecoverableDecryptionPlaceholder else {
                    return nil
                }
                guard placeholder.sender == sender && placeholder.timestamp == self.timestamp else {
                    return nil
                }
                return placeholder
            }
        } catch {
            owsFailDebug("Failed to fetch placeholder interaction: \(error)")
            return false
        }

        guard let placeholder = placeholders.first else {
            return false
        }

        Logger.info("Fetched placeholder with timestamp: \(timestamp) from sender: \(sender). Performing replacement...")

        if placeholder.supportsReplacement {
            placeholder.replaceWithInteraction(self, writeTx: transaction)
            return true
        } else {
            Logger.info("Placeholder not eligible for replacement, deleting.")
            DependenciesBridge.shared.interactionDeleteManager
                .delete(placeholder, sideEffects: .default(), tx: transaction)
            return false
        }
    }

    @objc
    public func insertOrReplacePlaceholder(from sender: SignalServiceAddress, transaction: DBWriteTransaction) {
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

// MARK: - shouldAppearInInbox

extension TSInteraction {

    /// Returns whether the given interaction should pull a conversation to the top of the list and
    /// marked unread.
    ///
    /// This operation necessarily happens after the interaction has been pulled out of the
    /// database. If possible, they should also be filtered as part of the database queries in the
    /// `mostRecentInteractionForInbox(transaction:)` implementations in InteractionFinder.swift.
    @objc
    public func shouldAppearInInbox(transaction: DBReadTransaction) -> Bool {
        return shouldAppearInInbox(groupUpdateItemsBuilder: { infoMessage in
            guard
                let localIdentifiers = DependenciesBridge.shared.tsAccountManager
                    .localIdentifiers(tx: transaction),
                let updates = infoMessage.computedGroupUpdateItems(
                    localIdentifiers: localIdentifiers,
                    tx: transaction
                )
            else {
                return nil
            }
            return updates
        })
    }

    /// Returns whether the given interaction should pull a conversation to the top of the list and
    /// marked unread.
    ///
    /// - parameter groupUpdateItemsBuilder: If the message is a group update info message,
    /// a block that builds the PersistableGroupUpdateItems for the message, which is run synchronously
    /// and may make use of a transaction if needed.
    public func shouldAppearInInbox(
        groupUpdateItemsBuilder: (TSInfoMessage) -> [TSInfoMessage.PersistableGroupUpdateItem]?
    ) -> Bool {
        if !shouldBeSaved || isDynamicInteraction || self is OWSOutgoingSyncMessage {
            owsFailDebug("Unexpected interaction type: \(type(of: self))")
            return false
        }

        switch self {
        case let errorMessage as TSErrorMessage:
            return Self.shouldErrorMessageAppearInInbox(errorMessage)
        case let infoMessage as TSInfoMessage:
            return Self.shouldInfoMessageAppearInInbox(
                infoMessage,
                groupUpdateItemsBuilder: groupUpdateItemsBuilder
            )
        case let message as TSMessage:
            return Self.shouldMessageAppearInInbox(message)
        default:
            return true
        }
    }

    private static func shouldErrorMessageAppearInInbox(_ message: TSErrorMessage) -> Bool {
        switch message.errorType {
        case .nonBlockingIdentityChange:
            // Otherwise all group threads with the recipient will percolate to the top of the inbox, even though
            // there was no meaningful interaction.
            return false
        case .decryptionFailure:
            if message is OWSRecoverableDecryptionPlaceholder {
                // Replaceable interactions should never be shown to the user
                return false
            } else {
                return true
            }
        default:
            return true
        }
    }

    private static func shouldMessageAppearInInbox(_ message: TSMessage) -> Bool {
        owsPrecondition(!(message is TSErrorMessage))
        owsPrecondition(!(message is TSInfoMessage))
        // skip considering this message if it's a group story reply, or a past edit revision
        return !message.isGroupStoryReply && !message.isPastEditRevision()
    }

    private static func shouldInfoMessageAppearInInbox(
        _ message: TSInfoMessage,
        groupUpdateItemsBuilder: (TSInfoMessage) -> [TSInfoMessage.PersistableGroupUpdateItem]?
    ) -> Bool {
        switch message.messageType {
        case .verificationStateChange: return false
        case .profileUpdate: return false
        case .phoneNumberChange: return false
        case .recipientHidden: return false
        case .threadMerge: return false
        case .sessionSwitchover: return false
        case .reportedSpam: return false
        case .learnedProfileName: return false
        case .acceptedMessageRequest: return false
        case .typeGroupUpdate:
            guard
                let updates = groupUpdateItemsBuilder(message)
            else {
                return true
            }
            return updates.contains { $0.shouldAppearInInbox }
        case .typeLocalUserEndedSession: return true
        case .typeRemoteUserEndedSession: return true
        case .userNotRegistered: return true
        case .typeUnsupportedMessage: return true
        case .typeGroupQuit: return true
        case .typeDisappearingMessagesUpdate: return true
        case .addToContactsOffer: return true
        case .addUserToProfileWhitelistOffer: return true
        case .addGroupToProfileWhitelistOffer: return true
        case .unknownProtocolVersion: return true
        case .userJoinedSignal: return true
        case .syncedThread: return true
        case .paymentsActivationRequest: return true
        case .paymentsActivated: return true
        case .blockedOtherUser: return true
        case .blockedGroup: return true
        case .unblockedOtherUser: return true
        case .unblockedGroup: return true
        }
    }
}
