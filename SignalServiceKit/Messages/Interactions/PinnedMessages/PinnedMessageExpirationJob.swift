//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public final class PinnedMessageExpirationJob: ExpirationJob<PinnedMessageRecord> {

    init(
        dateProvider: @escaping DateProvider,
        db: DB
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

    override public func deleteExpiredElement(_ pin: PinnedMessageRecord, tx: DBWriteTransaction) {
        _ = failIfThrows {
            try pin.delete(tx.database)
        }
    }
}
