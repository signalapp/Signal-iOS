//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

public final class PinnedMessageExpirationJob: ExpirationJob<PinnedMessageRecord> {

    init(
        dateProvider: @escaping DateProvider,
        db: DB,
    ) {
        super.init(
            dateProvider: dateProvider,
            db: db,
            logger: PrefixedLogger(prefix: "[PinnedMessagesExpirationJob]"),
        )
    }

    // MARK: -

    override public func nextExpiringElement(tx: DBReadTransaction) -> PinnedMessageRecord? {
        return PinnedMessageManager.nextExpiringPinnedMessage(tx: tx)
    }

    override public func expirationDate(ofElement pin: PinnedMessageRecord) -> Date {
        if let expiresAt = pin.expiresAt {
            return Date(millisecondsSince1970: expiresAt)
        }
        owsFailDebug("Expiring element should always have an expiration time")
        return Date.distantFuture
    }

    private func sendSyncExpiryMessage(pin: PinnedMessageRecord, tx: DBWriteTransaction) {
        let interactionStore = DependenciesBridge.shared.interactionStore
        let accountManager = DependenciesBridge.shared.tsAccountManager
        let messageSenderJobQueue = SSKEnvironment.shared.messageSenderJobQueueRef

        guard
            let targetMessage = interactionStore.fetchInteraction(rowId: pin.interactionId, tx: tx)
        else {
            owsFailDebug("Can't find target pinned message")
            return
        }

        let authorAci: Aci
        guard let localAci = accountManager.localIdentifiers(tx: tx)?.aci else {
            owsFailDebug("Can't find data for original message")
            return
        }

        if let _ = targetMessage as? TSOutgoingMessage {
            authorAci = localAci
        } else if
            let incomingMessage = targetMessage as? TSIncomingMessage,
            let authorUUID = incomingMessage.authorUUID,
            let incomingAci = try? Aci.parseFrom(serviceIdString: authorUUID)
        {
            authorAci = incomingAci
        } else {
            owsFailDebug("Can't parse author aci")
            return
        }

        let localThread = TSContactThread.getOrCreateLocalThread(transaction: tx)!
        let unpinMessage = OutgoingUnpinMessage(
            thread: localThread,
            targetMessageTimestamp: targetMessage.timestamp,
            targetMessageAuthorAciBinary: authorAci,
            messageExpiresInSeconds: 0,
            tx: tx,
        )

        let preparedMessage = PreparedOutgoingMessage.preprepared(
            transientMessageWithoutAttachments: unpinMessage,
        )

        messageSenderJobQueue.add(
            message: preparedMessage,
            transaction: tx,
        )
    }

    override public func deleteExpiredElement(_ pin: PinnedMessageRecord, tx: DBWriteTransaction) {
        failIfThrows {
            sendSyncExpiryMessage(pin: pin, tx: tx)
            try pin.delete(tx.database)
        }
    }
}
