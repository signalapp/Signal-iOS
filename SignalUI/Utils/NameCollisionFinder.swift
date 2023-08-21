//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit

/// A collection of addresses (and adjacent info) that collide (i.e. the user many confuse one element's `currentName` for another)
/// Useful when reporting a profile spoofing attempt to the user.
/// In cases where a colliding addresses' display name has recently changed, `oldName` and `latestUpdate` may be populated.
public struct NameCollision: Dependencies {
    public struct Element {
        public let address: SignalServiceAddress
        public let currentName: String
        public let oldName: String?
        public let latestUpdateTimestamp: UInt64?
    }

    public let elements: [Element]
    public init(_ elements: [Element]) {
        self.elements = elements
    }
}

public protocol NameCollisionFinder {
    var thread: TSThread { get }

    /// Finds collections of thread participants that have a colliding display name
    func findCollisions(transaction: SDSAnyReadTransaction) -> [NameCollision]

    /// Invoked whenever the user has opted to ignore any remaining collisions
    func markCollisionsAsResolved(transaction: SDSAnyWriteTransaction)
}

/// Finds all name collisions for a given contact thread. Compares the contact
/// thread recipient with all known Signal accounts.
public class ContactThreadNameCollisionFinder: NameCollisionFinder, Dependencies {
    private var contactThread: TSContactThread
    private let onlySearchIfMessageRequest: Bool

    private init(contactThread: TSContactThread, onlySearchIfMessageRequest: Bool) {
        self.contactThread = contactThread
        self.onlySearchIfMessageRequest = onlySearchIfMessageRequest
    }

    /// Builds a collision finder that will only return collisions if the
    /// target contact thread represents a pending message request.
    public static func makeToCheckMessageRequestNameCollisions(
        forContactThread contactThread: TSContactThread
    ) -> ContactThreadNameCollisionFinder {
        ContactThreadNameCollisionFinder(
            contactThread: contactThread,
            onlySearchIfMessageRequest: true
        )
    }

    // MARK: NameCollisionFinder

    public var thread: TSThread { contactThread }

    public func findCollisions(transaction: SDSAnyReadTransaction) -> [NameCollision] {
        guard let updatedThread = TSContactThread.getWithContactAddress(contactThread.contactAddress, transaction: transaction) else {
            return []
        }

        contactThread = updatedThread

        if
            onlySearchIfMessageRequest,
            !contactThread.hasPendingMessageRequest(transaction: transaction)
        {
            return []
        }

        let collisionCandidates = contactsViewHelper.signalAccounts(
            matchingSearch: contactThread.contactAddress.displayName(transaction: transaction),
            transaction: transaction)

        // ContactsViewHelper uses substring matching, so it might return false positives
        // Filter to just the matches that are valid collisions
        let collidingAddresses = collisionCandidates
            .map { $0.recipientAddress }
            .filter { !$0.isLocalAddress }
            .filter { isCollision($0, contactThread.contactAddress, transaction: transaction) }

        if collidingAddresses.isEmpty {
            return []
        } else {
            let collidingAddresses = [contactThread.contactAddress] + collidingAddresses
            let collision = NameCollision(collidingAddresses.map {
                NameCollision.Element(
                    address: $0,
                    currentName: $0.displayName(transaction: transaction),
                    oldName: nil,
                    latestUpdateTimestamp: nil)
            })

            // Contact threads can only have one collision
            return [collision]
        }
    }

    public func markCollisionsAsResolved(transaction: SDSAnyWriteTransaction) {
        // Do nothing
        // Contact threads always display all collisions
    }

    // MARK: Utils

    private func isCollision(
        _ address1: SignalServiceAddress,
        _ address2: SignalServiceAddress,
        transaction: SDSAnyReadTransaction) -> Bool {

        guard address1 != address2 else { return false }
        let name1 = address1.displayName(transaction: transaction)
        let name2 = address2.displayName(transaction: transaction)
        return name1 == name2
    }
}

public class GroupMembershipNameCollisionFinder: NameCollisionFinder {
    private var groupThread: TSGroupThread
    public var thread: TSThread { groupThread }

    /// Contains a list of recent profile update messages for the given address
    /// "Recent" is defined as all profile update messages since a call to `markCollisionsAsResolved`
    /// This is only fetched once for the lifetime of the collision finder. Thread-safe.
    let lock = UnfairLock()
    private var recentProfileUpdateMessages: [SignalServiceAddress: [TSInfoMessage]]?
    public var hasFetchedProfileUpdateMessages: Bool {
        lock.withLock { recentProfileUpdateMessages != nil }
    }

    public init(thread: TSGroupThread) {
        groupThread = thread
    }

    public func findCollisions(transaction: SDSAnyReadTransaction) -> [NameCollision] {
        guard let updatedThread = TSGroupThread.anyFetchGroupThread(uniqueId: groupThread.uniqueId, transaction: transaction) else {
            return []
        }
        groupThread = updatedThread

        // Build a dictionary mapping displayName -> (All addresses with that name)
        let groupMembers = groupThread.groupModel.groupMembers
        let displayNames = SignalServiceAddressCache.contactsManager.displayNames(forAddresses: groupMembers,
                                                                                  transaction: transaction)
        var collisionMap = [String: [SignalServiceAddress]]()
        for (address, name) in zip(groupMembers, displayNames) {
            collisionMap[name, default: []].append(address)
        }
        let allAddressCollisions = Array(collisionMap.values.filter { $0.count >= 2 })

        // Early-exit to avoid fetching unnecessary profile update messages
        // Move our start search pointer to try and proactively reduce our future interaction search space
        guard !allAddressCollisions.isEmpty else {
            setRecentProfileUpdateSearchStartIdToMax(transaction: transaction)
            return []
        }

        let profileUpdates = fetchRecentProfileUpdates(transaction: transaction)

        // For each collision set:
        // - Filter out any collision set that doesn't have at least one address that was recently changed
        // - Map the remaining address arrays to `NameCollision`s
        // - Build each NameCollision entry by grabbing:
        //      - The address
        //      - The oldest profile name in our update window (if available)
        //      - The most recent update message (if available)
        //
        //  We use the oldest/newest message in this way, because we're reporting to the user what has changed
        //  e.g. if I change my profile name from "Michelle1" to "Michelle2" to "Michelle3"
        //  the user will want to see it condensed to "Michelle3 changed their name from Michelle1 to Michelle3"
        //  or something similar. We'll want to sort by most recent profile change, so we grab the newest update
        //  message's timestamp as well.

        let filteredCollisions = allAddressCollisions
            .filter { $0.contains(where: { address in profileUpdates[address] != nil }) }
            .map { collidingAddresses in
                NameCollision(collidingAddresses.map { address in
                    let profileUpdateMessages = profileUpdates[address]
                    let oldestUpdateMessage = profileUpdateMessages?.min(by: { $0.sortId < $1.sortId })
                    let newestUpdateMessage = profileUpdateMessages?.max(by: { $0.sortId < $1.sortId })

                    return NameCollision.Element(
                        address: address,
                        currentName: address.displayName(transaction: transaction),
                        oldName: oldestUpdateMessage?.profileChangesOldFullName,
                        latestUpdateTimestamp: newestUpdateMessage?.timestamp)
                })
            }

        // Neat! No collisions. Let's make sure we update our search space since we know there are no collisions
        // in the update interactions we've fetched
        if filteredCollisions.isEmpty {
            SDSDatabaseStorage.shared.asyncWrite { writeTx in
                self.markCollisionsAsResolved(transaction: writeTx)
            }
        }

        return filteredCollisions
    }

    private func fetchRecentProfileUpdates(transaction: SDSAnyReadTransaction) -> [SignalServiceAddress: [TSInfoMessage]] {
        lock.withLock {
            if let cachedResults = recentProfileUpdateMessages { return cachedResults }

            let sortId = recentProfileUpdateSearchStartId(transaction: transaction) ?? 0
            let finder = GRDBInteractionFinder(threadUniqueId: thread.uniqueId)

            // Build a map from (SignalServiceAddress) -> (List of recent profile update messages)
            let results: [SignalServiceAddress: [TSInfoMessage]] = finder
                .profileUpdateInteractions(afterSortId: sortId, transaction: transaction.unwrapGrdbRead)
                .reduce(into: [:]) { dictBuilder, message in
                    guard let address = message.profileChangeAddress else { return }
                    dictBuilder[address, default: []].append(message)
                }

            recentProfileUpdateMessages = results
            return results
        }
    }

    public func markCollisionsAsResolved(transaction: SDSAnyWriteTransaction) {
        lock.withLock {
            let allRecentMessages = recentProfileUpdateMessages?.values.flatMap({ $0 })
            guard let newMaxSortId = allRecentMessages?.max(by: { $0.sortId < $1.sortId })?.sortId else { return }

            setRecentProfileUpdateSearchStartId(newValue: newMaxSortId, transaction: transaction)
            recentProfileUpdateMessages?.removeAll()
        }
    }

    // MARK: Storage

    private static var keyValueStore = SDSKeyValueStore(collection: "GroupThreadCollisionFinder")

    private func recentProfileUpdateSearchStartId(transaction: SDSAnyReadTransaction) -> UInt64? {
        Self.keyValueStore.getUInt64(groupThread.uniqueId, transaction: transaction)
    }

    private func setRecentProfileUpdateSearchStartId(newValue: UInt64, transaction: SDSAnyWriteTransaction) {
        let existingValue = recentProfileUpdateSearchStartId(transaction: transaction) ?? 0
        Self.keyValueStore.setUInt64(max(newValue, existingValue), key: groupThread.uniqueId, transaction: transaction)
    }

    private func setRecentProfileUpdateSearchStartIdToMax(transaction: SDSAnyReadTransaction) {
        // This is a perf optimization to proactively reduce our search space, so it doesn't need to be exact.
        // `lastInteractionRowId` is the current latest interaction on the thread when we checked for collisions.
        //
        // - If that interaction is deleted in the future, that's okay since rowIDs are monotonic. Any future unchecked
        // interactions will always have a rowID after the current value.
        // - This can be called from the main thread, so we perform the write async to avoid blocking. If the write
        // doesn't make it in time, that's okay. In the worst case, we'll just recheck interactions that we already
        // know don't contain profile changes. As long as this is successful a majority of the time, we'll keep a lid
        // on our search space.
        // - In our searchStartId cache, we always set the max(currentValue, newValue). So even if maxInteractionId
        // is unset or invalid, we'll never mistakenly grow our search space by setting the startId to a smaller value.
        let maxInteractionId = UInt64(thread.lastInteractionRowId)
        SDSDatabaseStorage.shared.asyncWrite { writeTx in
            self.setRecentProfileUpdateSearchStartId(newValue: maxInteractionId, transaction: writeTx)
        }
    }
}

// MARK: - Helpers

fileprivate extension SignalServiceAddress {
    func displayName(transaction readTx: SDSAnyReadTransaction) -> String {
        Self.contactsManager.displayName(for: self, transaction: readTx)
    }
}

public extension NameCollision {
    func standardSort(readTx: SDSAnyReadTransaction) -> NameCollision {
        NameCollision(
            elements.sorted { element1, element2 in
                // Given two colliding elements, we sort by:
                // - Most recent profile update first (if available)
                // - SignalServiceAddress UUID otherwise, to ensure stable sorting
                if element1.latestUpdateTimestamp != nil || element2.latestUpdateTimestamp != nil {
                    return (element1.latestUpdateTimestamp ?? 0) > (element2.latestUpdateTimestamp ?? 0)

                } else {
                    return element1.address.sortKey < element2.address.sortKey
                }
            }
        )
    }
}

public extension Array where Element == NameCollision {
    func standardSort(readTx: SDSAnyReadTransaction) -> [NameCollision] {
        self
            .map { $0.standardSort(readTx: readTx) }
            .sorted { set1, set2 in
                // Across collision sets, (e.g. two independent collisions, two people named Michelle, two people named Nora)
                // We'll sort by the smallest comparable name in each collision set
                // (Usually they're all the same, but this might change in the future when comparing homographs)
                // This is to try and maintain stable sorting as individual elements within the set are resolved

                let smallestName1 = set1.elements
                    .map { SSKEnvironment.shared.contactsManager.comparableName(for: $0.address, transaction: readTx )}
                    .min()
                let smallestName2 = set2.elements
                    .map { SSKEnvironment.shared.contactsManager.comparableName(for: $0.address, transaction: readTx )}
                    .min()

                switch (smallestName1, smallestName2) {
                case let (name1?, name2?):
                    return name1 < name2
                case (_?, nil):
                    return true
                case (nil, _):
                    return false
                }
        }
    }
}
