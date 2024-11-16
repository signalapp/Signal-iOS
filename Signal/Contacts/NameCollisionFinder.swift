//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit

/// A collection of addresses (and adjacent info) that collide (i.e. the user many confuse one element's `currentName` for another)
/// Useful when reporting a profile spoofing attempt to the user.
/// In cases where a colliding addresses' display name has recently changed, `oldName` and `latestUpdate` may be populated.
public struct NameCollision {
    public struct Element {
        public let address: SignalServiceAddress
        public let comparableName: ComparableDisplayName
        public let profileNameChange: (oldestProfileName: String, newestProfileName: String)?
        public let latestUpdateTimestamp: UInt64?

        fileprivate init(
            comparableName: ComparableDisplayName,
            profileNameChange: (oldestProfileName: String, newestProfileName: String)? = nil,
            latestUpdateTimestamp: UInt64? = nil
        ) {
            self.address = comparableName.address
            self.comparableName = comparableName
            self.profileNameChange = profileNameChange
            self.latestUpdateTimestamp = latestUpdateTimestamp
        }
    }

    public let elements: [Element]
    public init?(_ elements: [Element]) {
        guard elements.count >= 2 else {
            return nil
        }
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
public class ContactThreadNameCollisionFinder: NameCollisionFinder {
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

        let candidateAddresses = { () -> [SignalServiceAddress] in
            var result = Set<SignalServiceAddress>()
            result.formUnion(SSKEnvironment.shared.profileManagerRef.allWhitelistedRegisteredAddresses(tx: transaction))
            // Include all SignalAccounts as well (even though most are redundant) to
            // ensure we check against blocked system contact names.
            result.formUnion(SignalAccount.anyFetchAll(transaction: transaction).map { $0.recipientAddress })
            result.remove(contactThread.contactAddress)
            result = result.filter { !$0.isLocalAddress }
            return Array(result)
        }()

        let config: DisplayName.ComparableValue.Config = .current()

        let targetName = ComparableDisplayName(
            address: contactThread.contactAddress,
            displayName: SSKEnvironment.shared.contactManagerRef.displayName(for: contactThread.contactAddress, tx: transaction),
            config: config
        )

        // If we don't have a name for this person, don't show collisions.
        guard targetName.displayName.hasKnownValue else {
            return []
        }

        var collisionElements = [NameCollision.Element]()
        collisionElements.append(NameCollision.Element(comparableName: targetName))

        let candidateNames = SSKEnvironment.shared.contactManagerRef.displayNames(for: candidateAddresses, tx: transaction)
        for (candidateAddress, candidateName) in zip(candidateAddresses, candidateNames) {
            let candidateName = ComparableDisplayName(address: candidateAddress, displayName: candidateName, config: config)
            // If we don't have a name for this person, don't consider them for collisions.
            guard candidateName.displayName.hasKnownValue else {
                continue
            }
            guard candidateName.resolvedValue() == targetName.resolvedValue() else {
                continue
            }
            collisionElements.append(NameCollision.Element(comparableName: candidateName))
        }

        return [NameCollision(collisionElements)].compacted()
    }

    public func markCollisionsAsResolved(transaction: SDSAnyWriteTransaction) {
        // Do nothing
        // Contact threads always display all collisions
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

        let config: DisplayName.ComparableValue.Config = .current()

        // Build a dictionary mapping displayName -> (All addresses with that name)
        let groupMembers = groupThread.groupModel.groupMembers
        let displayNames = SSKEnvironment.shared.contactManagerRef.displayNames(for: groupMembers, tx: transaction)
        var collisionMap = [String: [ComparableDisplayName]]()
        for (address, displayName) in zip(groupMembers, displayNames) {
            let comparableName = ComparableDisplayName(address: address, displayName: displayName, config: config)
            // If we don't have a name for this person, don't consider them for collisions.
            guard comparableName.displayName.hasKnownValue else {
                continue
            }
            collisionMap[comparableName.resolvedValue(), default: []].append(comparableName)
        }
        let allCollisions = Array(collisionMap.values.filter { $0.count >= 2 })

        // Early-exit to avoid fetching unnecessary profile update messages
        // Move our start search pointer to try and proactively reduce our future interaction search space
        if allCollisions.isEmpty {
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

        let filteredCollisions = allCollisions
            .filter { $0.contains(where: { profileUpdates[$0.address] != nil }) }
            .map { collidingNames in
                NameCollision(collidingNames.map {
                    let profileUpdateMessages = profileUpdates[$0.address]
                    let newestUpdateMessage = profileUpdateMessages?.max(by: { $0.sortId < $1.sortId })
                    return NameCollision.Element(
                        comparableName: $0,
                        profileNameChange: profileNameChange(profileUpdateMessages: profileUpdateMessages),
                        latestUpdateTimestamp: newestUpdateMessage?.timestamp
                    )
                })!
            }

        // Neat! No collisions. Let's make sure we update our search space since we know there are no collisions
        // in the update interactions we've fetched
        if filteredCollisions.isEmpty {
            SSKEnvironment.shared.databaseStorageRef.asyncWrite { writeTx in
                self.markCollisionsAsResolved(transaction: writeTx)
            }
        }

        return filteredCollisions.standardSort(readTx: transaction)
    }

    private func profileNameChange(
        profileUpdateMessages: [TSInfoMessage]?
    ) -> (oldestProfileName: String, newestProfileName: String)? {
        let oldestUpdateMessage = profileUpdateMessages?.min(by: { $0.sortId < $1.sortId })
        let newestUpdateMessage = profileUpdateMessages?.max(by: { $0.sortId < $1.sortId })
        guard
            let oldProfileName = oldestUpdateMessage?.profileChangesOldFullName,
            let newProfileName = newestUpdateMessage?.profileChangesNewFullName
        else {
            return nil
        }
        return (oldProfileName, newProfileName)
    }

    private func fetchRecentProfileUpdates(transaction: SDSAnyReadTransaction) -> [SignalServiceAddress: [TSInfoMessage]] {
        lock.withLock {
            if let cachedResults = recentProfileUpdateMessages { return cachedResults }

            let sortId = recentProfileUpdateSearchStartId(transaction: transaction) ?? 0
            let finder = InteractionFinder(threadUniqueId: thread.uniqueId)

            // Build a map from (SignalServiceAddress) -> (List of recent profile update messages)
            let results: [SignalServiceAddress: [TSInfoMessage]] = finder
                .profileUpdateInteractions(afterSortId: sortId, transaction: transaction)
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

    private static var keyValueStore = KeyValueStore(collection: "GroupThreadCollisionFinder")

    private func recentProfileUpdateSearchStartId(transaction: SDSAnyReadTransaction) -> UInt64? {
        Self.keyValueStore.getUInt64(groupThread.uniqueId, transaction: transaction.asV2Read)
    }

    private func setRecentProfileUpdateSearchStartId(newValue: UInt64, transaction: SDSAnyWriteTransaction) {
        let existingValue = recentProfileUpdateSearchStartId(transaction: transaction) ?? 0
        Self.keyValueStore.setUInt64(max(newValue, existingValue), key: groupThread.uniqueId, transaction: transaction.asV2Write)
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
        SSKEnvironment.shared.databaseStorageRef.asyncWrite { writeTx in
            self.setRecentProfileUpdateSearchStartId(newValue: maxInteractionId, transaction: writeTx)
        }
    }
}

// MARK: - Helpers

private extension NameCollision {
    func standardSort(readTx: SDSAnyReadTransaction) -> NameCollision {
        NameCollision(
            elements.sorted { lhs, rhs in
                // Given two colliding elements, we sort by:
                // - Most recent profile update first (if available)
                // - SignalServiceAddress UUID otherwise, to ensure stable sorting
                if lhs.latestUpdateTimestamp != nil || rhs.latestUpdateTimestamp != nil {
                    return (lhs.latestUpdateTimestamp ?? 0) > (rhs.latestUpdateTimestamp ?? 0)
                } else {
                    return lhs.address.sortKey < rhs.address.sortKey
                }
            }
        )!
    }
}

private extension Array where Element == NameCollision {
    func standardSort(readTx: SDSAnyReadTransaction) -> [NameCollision] {
        self.map { $0.standardSort(readTx: readTx) }.sorted { lhs, rhs in
            return lhs.elements[0].comparableName < rhs.elements[1].comparableName
        }
    }
}
