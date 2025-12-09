//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
public import LibSignalClient

public enum PinnedMessageError: Error {
    case messageSendTimeout
}

public class PinnedMessageManager {
    private let disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore
    private let accountManager: TSAccountManager
    private let interactionStore: InteractionStore
    private let keyValueStore: NewKeyValueStore
    private let db: DB
    private let threadStore: ThreadStore

    // Int value of how many times the disappearing message warning has been shown.
    // If 3 or greater, don't show again.
    private static let disappearingMessageWarningShownKey = "disappearingMessageWarningShownKey"

    init(
        disappearingMessagesConfigurationStore: DisappearingMessagesConfigurationStore,
        interactionStore: InteractionStore,
        accountManager: TSAccountManager,
        db: DB,
        threadStore: ThreadStore
    ) {
        self.disappearingMessagesConfigurationStore = disappearingMessagesConfigurationStore
        self.interactionStore = interactionStore
        self.accountManager = accountManager
        self.db = db
        self.threadStore = threadStore
        self.keyValueStore = NewKeyValueStore(collection: "PinnedMessage")
    }

    public func fetchPinnedMessagesForThread(
        threadId: Int64,
        tx: DBReadTransaction
        ) -> [TSMessage] {
        return failIfThrows {
            return try InteractionRecord.fetchAll(
                tx.database,
                sql: """
                    SELECT m.* FROM \(InteractionRecord.databaseTableName) as m
                    JOIN \(PinnedMessageRecord.databaseTableName) as p
                    ON p.\(PinnedMessageRecord.CodingKeys.interactionId.rawValue) = m.\(InteractionRecord.CodingKeys.id.rawValue)
                    WHERE \(PinnedMessageRecord.CodingKeys.threadId.rawValue) = ?
                    ORDER BY p.\(PinnedMessageRecord.CodingKeys.id.rawValue) DESC
                """,
                arguments: [threadId]
            ).compactMap { try TSInteraction.fromRecord($0) as? TSMessage }
        }
    }

    public func pinMessage(
        pinMessageProto: SSKProtoDataMessagePinMessage,
        pinAuthor: Aci,
        thread: TSThread,
        timestamp: UInt64,
        expireTimer: UInt32?,
        expireTimerVersion: UInt32?,
        transaction: DBWriteTransaction
    ) throws -> TSInteraction {
        guard let localAci = accountManager.localIdentifiers(tx: transaction)?.aci else {
            throw OWSAssertionError("User not registered")
        }

        guard let targetAuthorAciBinary = pinMessageProto.targetAuthorAciBinary,
              let targetAuthorAci = try? Aci.parseFrom(serviceIdBinary: targetAuthorAciBinary) else {
            throw OWSAssertionError("Target author ACI not present")
        }

        guard let targetMessage = try interactionStore.fetchMessage(
            timestamp: pinMessageProto.targetSentTimestamp,
            incomingMessageAuthor: targetAuthorAci == localAci ? nil : targetAuthorAci,
            transaction: transaction
        ), let interactionId = targetMessage.grdbId?.int64Value
        else {
            throw OWSAssertionError("Can't find target pinned message")
        }

        var expiresAt: Int64?
        if pinMessageProto.hasPinDurationSeconds {
            expiresAt = Int64(timestamp) + Int64(pinMessageProto.pinDurationSeconds)
        } else if pinMessageProto.hasPinDurationForever {
            // expiresAt should stay nil
        } else {
            throw OWSAssertionError("Pin message has no duration")
        }

        guard let threadId = thread.sqliteRowId else {
            throw OWSAssertionError("threadId not found")
        }

        pruneOldestPinnedMessagesIfNecessary(
            threadId: threadId,
            transaction: transaction
        )

        failIfThrows {
            _ = try PinnedMessageRecord.insertRecord(
                interactionId: interactionId,
                threadId: threadId,
                expiresAt: expiresAt,
                tx: transaction
            )
        }

        let dmConfig = disappearingMessagesConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: transaction)

        insertInfoMessageForPinnedMessage(
            timestamp: MessageTimestampGenerator.sharedInstance.generateTimestamp(),
            thread: thread,
            targetMessageTimestamp: pinMessageProto.targetSentTimestamp,
            targetMessageAuthor: targetAuthorAci,
            pinAuthor: pinAuthor,
            expireTimer: dmConfig.durationSeconds,
            expireTimerVersion: dmConfig.timerVersion,
            tx: transaction
        )

        return targetMessage
    }

    public func unpinMessage(
        unpinMessageProto: SSKProtoDataMessageUnpinMessage,
        transaction: DBWriteTransaction
    ) throws -> TSInteraction {
        guard let localAci = accountManager.localIdentifiers(tx: transaction)?.aci else {
            throw OWSAssertionError("User not registered")
        }

        guard let targetAuthorAciBinary = unpinMessageProto.targetAuthorAciBinary,
              let targetAuthorAci = try? Aci.parseFrom(serviceIdBinary: targetAuthorAciBinary) else {
            throw OWSAssertionError("Target author ACI not present")
        }

        guard let targetMessage = try interactionStore.fetchMessage(
            timestamp: unpinMessageProto.targetSentTimestamp,
            incomingMessageAuthor: targetAuthorAci == localAci ? nil : targetAuthorAci,
            transaction: transaction
        ), let interactionId = targetMessage.grdbId?.int64Value
        else {
            throw OWSAssertionError("Can't find target pinned message")
        }

        failIfThrows {
            _ = try PinnedMessageRecord
                .filter(PinnedMessageRecord.Columns.interactionId == interactionId)
                .deleteAll(transaction.database)
        }

        return targetMessage
    }

    public func pruneOldestPinnedMessagesIfNecessary(
        threadId: Int64,
        transaction: DBWriteTransaction
    ) {
        let maxNumberOfPinnedMessages = RemoteConfig.current.pinnedMessageLimit

        failIfThrows {
            // Keep the newest pinned messages up to the limit minus one, since we're about to insert.
            let mostRecentPinnedMessageIds: [Int64] = try PinnedMessageRecord
                .filter(PinnedMessageRecord.Columns.threadId == threadId)
                .order(PinnedMessageRecord.Columns.id.desc)
                .limit(Int(maxNumberOfPinnedMessages) - 1)
                .select(PinnedMessageRecord.Columns.id)
                .fetchAll(transaction.database)

            // Delete all others
            try PinnedMessageRecord
                .filter(PinnedMessageRecord.Columns.threadId == threadId)
                .filter(!mostRecentPinnedMessageIds.contains(PinnedMessageRecord.Columns.id))
                .deleteAll(transaction.database)
        }
    }

    public func shouldShowDisappearingMessageWarning(
        message: TSMessage,
        tx: DBReadTransaction
    ) -> Bool {
        if message.expiresInSeconds == 0 {
            return false
        }
        let numberOfTimesWarningShown = keyValueStore.fetchValue(
            Int64.self,
            forKey: Self.disappearingMessageWarningShownKey,
            tx: tx
        ) ?? 0

        return numberOfTimesWarningShown < 3
    }

    public func incrementDisappearingMessageWarningCount(tx: DBWriteTransaction) {
        let numberOfTimesWarningShown = keyValueStore.fetchValue(Int64.self, forKey: Self.disappearingMessageWarningShownKey, tx: tx) ?? 0

        keyValueStore.writeValue(numberOfTimesWarningShown + 1, forKey: Self.disappearingMessageWarningShownKey, tx: tx)
    }

    public func stopShowingDisappearingMessageWarning(tx: DBWriteTransaction) {
        keyValueStore.writeValue(3, forKey: Self.disappearingMessageWarningShownKey, tx: tx)
    }

    public func applyPinMessageChangeToLocalState(
        targetTimestamp: UInt64,
        targetAuthorAci: Aci,
        expiresAt: Int64?,
        isPin: Bool,
        tx: DBWriteTransaction
    ) {
        guard let localAci = accountManager.localIdentifiers(tx: tx)?.aci else {
            owsFailDebug("User not registered")
            return
        }

        guard let targetMessage = try? interactionStore.fetchMessage(
            timestamp: targetTimestamp,
            incomingMessageAuthor: targetAuthorAci == localAci ? nil : targetAuthorAci,
            transaction: tx
        ), let thread = threadStore.fetchThread(
            uniqueId: targetMessage.uniqueThreadId,
            tx: tx
        ), let threadId = thread.sqliteRowId,
           let interactionId = targetMessage.sqliteRowId
        else {
            return
        }

        if !isPin {
            return failIfThrows {
                try PinnedMessageRecord
                    .filter(PinnedMessageRecord.Columns.interactionId == interactionId)
                    .deleteAll(tx.database)

                db.touch(
                    interaction: targetMessage,
                    shouldReindex: false,
                    tx: tx
                )
            }
        }

        pruneOldestPinnedMessagesIfNecessary(
            threadId: threadId,
            transaction: tx
        )

        failIfThrows {
            _ = try PinnedMessageRecord.insertRecord(
                interactionId: interactionId,
                threadId: threadId,
                expiresAt: expiresAt,
                tx: tx
            )
        }

        db.touch(
            interaction: targetMessage,
            shouldReindex: false,
            tx: tx
        )

        let dmConfig = disappearingMessagesConfigurationStore.fetchOrBuildDefault(for: .thread(thread), tx: tx)

        insertInfoMessageForPinnedMessage(
            timestamp: MessageTimestampGenerator.sharedInstance.generateTimestamp(),
            thread: thread,
            targetMessageTimestamp: targetTimestamp,
            targetMessageAuthor: targetAuthorAci,
            pinAuthor: localAci,
            expireTimer: dmConfig.durationSeconds,
            expireTimerVersion: dmConfig.timerVersion,
            tx: tx
        )
    }

    private func getMessageAuthorAci(interaction: TSMessage, tx: DBReadTransaction) -> Aci? {
        guard let localAci = accountManager.localIdentifiers(tx: tx)?.aci else {
            owsFailDebug("Can't find data for original message")
            return nil
        }

        if let _ = interaction as? TSOutgoingMessage {
            return localAci
        } else if let incomingMessage = interaction as? TSIncomingMessage,
                  let authorUUID = incomingMessage.authorUUID,
                  let incomingAci = try? Aci.parseFrom(serviceIdString: authorUUID) {
            return incomingAci
        } else {
            return nil
        }
    }

    public func getOutgoingPinMessage(
        interaction: TSMessage,
        thread: TSThread,
        expiresAt: Int64?,
        tx: DBWriteTransaction
    ) -> OutgoingPinMessage? {
        guard let authorAci = getMessageAuthorAci(interaction: interaction, tx: tx) else {
            owsFailDebug("unable to parse authorAci")
            return nil
        }

        var pinDurationSeconds: UInt32?
        if let expiresAt {
            pinDurationSeconds = UInt32(expiresAt)
        }

        return OutgoingPinMessage(
            thread: thread,
            targetMessageTimestamp: interaction.timestamp,
            targetMessageAuthorAciBinary: authorAci,
            pinDurationSeconds: pinDurationSeconds ?? 0,
            pinDurationForever: expiresAt == nil,
            messageExpiresInSeconds: disappearingMessagesConfigurationStore.durationSeconds(for: thread, tx: tx),
            tx: tx)
    }

    public func getOutgoingUnpinMessage(
        interaction: TSMessage,
        thread: TSThread,
        expiresAt: Int64?,
        tx: DBWriteTransaction
    ) -> OutgoingUnpinMessage? {

        guard let authorAci = getMessageAuthorAci(interaction: interaction, tx: tx) else {
            owsFailDebug("unable to parse authorAci")
            return nil
        }

        return OutgoingUnpinMessage(
            thread: thread,
            targetMessageTimestamp: interaction.timestamp,
            targetMessageAuthorAciBinary: authorAci,
            messageExpiresInSeconds: disappearingMessagesConfigurationStore.durationSeconds(for: thread, tx: tx),
            tx: tx)
    }

    public func insertInfoMessageForPinnedMessage(
        timestamp: UInt64,
        thread: TSThread,
        targetMessageTimestamp: UInt64,
        targetMessageAuthor: Aci,
        pinAuthor: Aci,
        expireTimer: UInt32?,
        expireTimerVersion: UInt32?,
        tx: DBWriteTransaction
    ) {
        var userInfoForNewMessage: [InfoMessageUserInfoKey: Any] = [:]
        userInfoForNewMessage[.pinnedMessage] = PersistablePinnedMessageItem(
            pinnedMessageAuthorAci: pinAuthor,
            originalMessageAuthorAci: targetMessageAuthor,
            timestamp: Int64(targetMessageTimestamp)
        )

        var timerVersion: NSNumber?
        if let expireTimerVersion {
            timerVersion = NSNumber(value: expireTimerVersion)
        }

        let infoMessage = TSInfoMessage(
            thread: thread,
            timestamp: timestamp,
            serverGuid: nil,
            messageType: .typePinnedMessage,
            expireTimerVersion: timerVersion,
            expiresInSeconds: expireTimer ?? 0,
            infoMessageUserInfo: userInfoForNewMessage
        )

        infoMessage.anyInsert(transaction: tx)
    }
}
