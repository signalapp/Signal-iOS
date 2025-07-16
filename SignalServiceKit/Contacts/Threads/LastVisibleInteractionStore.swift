//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension TSThread {
    public struct LastVisibleInteraction: Codable, Equatable {
        public let sortId: UInt64
        public let onScreenPercentage: CGFloat

        public init(sortId: UInt64, onScreenPercentage: CGFloat) {
            self.sortId = sortId
            self.onScreenPercentage = onScreenPercentage
        }
    }
}

/// Tracks the last visible interaction per thread (the interaction we last scrolled to).
public class LastVisibleInteractionStore {

    public typealias LastVisibleInteraction = TSThread.LastVisibleInteraction

    private let kvStore: KeyValueStore

    public init() {
        self.kvStore = KeyValueStore(collection: "lastVisibleInteractionStore")
    }

    public func hasLastVisibleInteraction(for thread: TSThread, tx: DBReadTransaction) -> Bool {
        return lastVisibleInteraction(for: thread, tx: tx) != nil
    }

    public func lastVisibleInteraction(for thread: TSThread, tx: DBReadTransaction) -> LastVisibleInteraction? {
        guard let data = kvStore.getData(thread.uniqueId, transaction: tx) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(LastVisibleInteraction.self, from: data)
        } catch {
            owsFailDebug("Error: \(error)")
            return nil
        }
    }

    public func clearLastVisibleInteraction(for thread: TSThread, tx: DBWriteTransaction) {
        setLastVisibleInteraction(nil, for: thread, tx: tx)
    }

    public func setLastVisibleInteraction(
        _ lastVisibleInteraction: LastVisibleInteraction?,
        for thread: TSThread,
        tx: DBWriteTransaction
    ) {
        guard let lastVisibleInteraction = lastVisibleInteraction else {
            kvStore.removeValue(forKey: thread.uniqueId, transaction: tx)
            return
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(lastVisibleInteraction)
        } catch {
            owsFailDebug("Error: \(error)")
            kvStore.removeValue(forKey: thread.uniqueId, transaction: tx)
            return
        }
        kvStore.setData(data, key: thread.uniqueId, transaction: tx)
    }
}

extension TSThread {

    func hasLastVisibleInteraction(transaction: DBReadTransaction) -> Bool {
        return DependenciesBridge.shared.lastVisibleInteractionStore.hasLastVisibleInteraction(
            for: self,
            tx: transaction
        )
    }

    func clearLastVisibleInteraction(transaction: DBWriteTransaction) {
        return DependenciesBridge.shared.lastVisibleInteractionStore.clearLastVisibleInteraction(
            for: self,
            tx: transaction
        )
    }

    func lastVisibleSortId(transaction: DBReadTransaction) -> UInt64? {
        guard
            let lastVisibleInteraction = DependenciesBridge.shared.lastVisibleInteractionStore
                .lastVisibleInteraction(for: self, tx: transaction)
        else {
            return nil
        }
        return lastVisibleInteraction.sortId
    }

    func setLastVisibleInteraction(
        sortId: UInt64,
        onScreenPercentage: CGFloat,
        transaction: DBWriteTransaction
    ) {
        let lastVisibleInteraction = LastVisibleInteraction(sortId: sortId, onScreenPercentage: onScreenPercentage)
        DependenciesBridge.shared.lastVisibleInteractionStore.setLastVisibleInteraction(
            lastVisibleInteraction,
            for: self,
            tx: transaction
        )
    }
}
