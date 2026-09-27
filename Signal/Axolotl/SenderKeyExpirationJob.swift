//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

class SenderKeyExpirationJob: ExpirationJob<SenderKeyRecord> {
    private let deletionType: SenderKeyRecord.DeletionType
    private let remoteConfigProvider: any RemoteConfigProvider
    private let senderKeyStore: SenderKeyStore

    init(
        dateProvider: @escaping DateProvider,
        db: any DB,
        deletionType: SenderKeyRecord.DeletionType,
        remoteConfigProvider: any RemoteConfigProvider,
        senderKeyStore: SenderKeyStore,
    ) {
        self.deletionType = deletionType
        self.remoteConfigProvider = remoteConfigProvider
        self.senderKeyStore = senderKeyStore
        super.init(
            dateProvider: dateProvider,
            db: db,
            logger: PrefixedLogger(prefix: "[SenderKeyExpJob]"),
        )
    }

    override func nextExpiringElement(tx: DBReadTransaction) -> SenderKeyRecord? {
        return senderKeyStore.fetchOldestSenderKeyRecord(deletionType: self.deletionType, tx: tx)
    }

    override func expirationDate(ofElement element: SenderKeyRecord) -> Date {
        return element.insertedAtDate.addingTimeInterval(remoteConfigProvider.currentConfig().maxSenderKeyAge)
    }

    override func deleteExpiredElement(_ element: SenderKeyRecord, tx: DBWriteTransaction) {
        failIfThrows {
            try element.delete(tx.database)
        }
    }
}
