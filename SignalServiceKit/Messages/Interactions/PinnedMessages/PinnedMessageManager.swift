//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB
import LibSignalClient

public class PinnedMessageManager {
    private let accountManager: TSAccountManager
    private let interactionStore: InteractionStore
    private let keyValueStore: NewKeyValueStore
    private let db: DB

    // Int value of how many times the disappearing message warning has been shown.
    // If 3 or greater, don't show again.
    private static let disappearingMessageWarningShownKey = "disappearingMessageWarningShownKey"

    init(
        interactionStore: InteractionStore,
        accountManager: TSAccountManager,
        db: DB
    ) {
        self.interactionStore = interactionStore
        self.accountManager = accountManager
        self.db = db
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
        threadId: Int64,
        timestamp: Int64,
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
            expiresAt = timestamp + Int64(pinMessageProto.pinDurationSeconds)
        } else if pinMessageProto.hasPinDurationForever {
            // expiresAt should stay nil
        } else {
            throw OWSAssertionError("Pin message has no duration")
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
        return targetMessage
        // TODO: insert info message.
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

    private func pruneOldestPinnedMessagesIfNecessary(
        threadId: Int64,
        transaction: DBWriteTransaction
    ) {
        failIfThrows {
            // Keep the newest 2 pinned messages
            let mostRecentPinnedMessageIds: [Int64] = try PinnedMessageRecord
                .filter(PinnedMessageRecord.Columns.threadId == threadId)
                .order(PinnedMessageRecord.Columns.id.desc)
                .limit(2)
                .select(PinnedMessageRecord.Columns.id)
                .fetchAll(transaction.database)

            // Delete all others
            try PinnedMessageRecord
                .filter(PinnedMessageRecord.Columns.threadId == threadId)
                .filter(!mostRecentPinnedMessageIds.contains(PinnedMessageRecord.Columns.id))
                .deleteAll(transaction.database)
        }
    }

    public func shouldShowDisappearingMessageWarning(message: TSMessage) -> Bool {
        if message.expiresInSeconds == 0 {
            return false
        }
        let numberOfTimesWarningShown: Int64 = db.read { tx in
            keyValueStore.fetchValue(Int64.self, forKey: Self.disappearingMessageWarningShownKey, tx: tx) ?? 0
        }
        return numberOfTimesWarningShown < 3
    }

    public func incrementDisappearingMessageWarningCount() {
        db.write { tx in
            let numberOfTimesWarningShown = keyValueStore.fetchValue(Int64.self, forKey: Self.disappearingMessageWarningShownKey, tx: tx) ?? 0
            keyValueStore.writeValue(numberOfTimesWarningShown + 1, forKey: Self.disappearingMessageWarningShownKey, tx: tx)
        }
    }

    public func stopShowingDisappearingMessageWarning() {
        db.write { tx in
            keyValueStore.writeValue(3, forKey: Self.disappearingMessageWarningShownKey, tx: tx)
        }
    }
}
