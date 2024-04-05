//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

public protocol NicknameManager {
    func fetch(recipient: SignalRecipient, tx: DBReadTransaction) -> NicknameRecord?
    func insert(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction)
    func update(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction)
    func delete(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction)
}

public struct NicknameManagerImpl: NicknameManager {
    private let nicknameRecordStore: any NicknameRecordStore
    private let searchableNameIndexer: any SearchableNameIndexer
    private let schedulers: any Schedulers

    public init(
        nicknameRecordStore: any NicknameRecordStore,
        searchableNameIndexer: any SearchableNameIndexer,
        schedulers: any Schedulers
    ) {
        self.nicknameRecordStore = nicknameRecordStore
        self.searchableNameIndexer = searchableNameIndexer
        self.schedulers = schedulers
    }

    private func notifyContactChanges(tx: DBWriteTransaction) {
        tx.addAsyncCompletion(on: self.schedulers.main) {
            NotificationCenter.default.postNotificationNameAsync(.OWSContactsManagerSignalAccountsDidChange, object: nil)
        }
    }

    // MARK: Read

    public func fetch(
        recipient: SignalRecipient,
        tx: DBReadTransaction
    ) -> NicknameRecord? {
        recipient.id.flatMap { nicknameRecordStore.fetch(recipientRowID: $0, tx: tx) }
    }

    // MARK: Insert

    public func insert(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction) {
        self.nicknameRecordStore.insert(nicknameRecord, tx: tx)
        self.searchableNameIndexer.insert(nicknameRecord, tx: tx)
        self.notifyContactChanges(tx: tx)
    }

    // MARK: Update

    public func update(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction) {
        self.nicknameRecordStore.update(nicknameRecord, tx: tx)
        self.searchableNameIndexer.update(nicknameRecord, tx: tx)
        self.notifyContactChanges(tx: tx)
    }

    // MARK: Delete

    public func delete(_ nicknameRecord: NicknameRecord, tx: DBWriteTransaction) {
        self.searchableNameIndexer.delete(nicknameRecord, tx: tx)
        self.nicknameRecordStore.delete(nicknameRecord, tx: tx)
        self.notifyContactChanges(tx: tx)
    }
}
