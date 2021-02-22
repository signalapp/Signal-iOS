//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

/// A collection of addresses (and adjacent info) that collide (i.e. the user many confuse one element's `currentName` for another)
/// Useful when reporting a profile spoofing attempt to the user.
/// In cases where a colliding addresses' display name has recently changed, `oldName` and `latestUpdate` may be populated.
public struct NameCollision {
    public struct Element {
        public let address: SignalServiceAddress
        public let currentName: String
        public let oldName: String?
        public let latestUpdate: UInt64?
    }

    public let elements: [Element]
    init(_ elements: [Element]) {
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

/// Finds all name collisions for a given contact thread
/// Compares the contact thread recipient with all known
public class ContactThreadNameCollisionFinder: NameCollisionFinder {
    var contactThread: TSContactThread
    public var thread: TSThread { contactThread }

    public init(thread: TSContactThread) {
        contactThread = thread
    }

    public func findCollisions(transaction: SDSAnyReadTransaction) -> [NameCollision] {
        // Only look for name collisions in pending message requests
        guard let updatedThread = TSContactThread.getWithContactAddress(contactThread.contactAddress, transaction: transaction) else {
            return []
        }
        contactThread = updatedThread
        guard contactThread.hasPendingMessageRequest(transaction: transaction.unwrapGrdbRead) else { return [] }

        let collisionCandidates = Environment.shared.contactsViewHelper.signalAccounts(
            matchingSearch: contactThread.contactAddress.getDisplayName(transaction: transaction),
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
                    currentName: $0.getDisplayName(transaction: transaction),
                    oldName: nil,
                    latestUpdate: nil)
            })

            // Contact threads can only have one collision
            return [collision]
        }
    }

    public func markCollisionsAsResolved(transaction: SDSAnyWriteTransaction) {
        // Do nothing
        // Contact threads always display all collisions
    }

    private func isCollision(
        _ address1: SignalServiceAddress,
        _ address2: SignalServiceAddress,
        transaction: SDSAnyReadTransaction) -> Bool {

        guard address1 != address2 else { return false }
        let name1 = address1.getDisplayName(transaction: transaction)
        let name2 = address1.getDisplayName(transaction: transaction)
        return name1 == name2
    }
}

public class GroupMembershipNameCollisionFinder: NameCollisionFinder {
    var groupThread: TSGroupThread
    public var thread: TSThread { groupThread }

    /// Contains a list of recent profile update messages for the given address
    /// "Recent" is defined as all profile update messages since a call to `markCollisionsAsResolved`
    /// This is only fetched once for the lifetime of the collision finder. This is okay, since the only place we use this XXXXX
    var recentProfileUpdateMessages: [SignalServiceAddress: [TSInfoMessage]]? = nil

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
        let collisionMap: [String: [SignalServiceAddress]] = groupMembers.reduce(into: [:]) { (dictBuilder, address) in
            let displayName = address.getDisplayName(transaction: transaction)
            dictBuilder[displayName, default: []].append(address)
        }
        let allAddressCollisions = Array(collisionMap.values.filter { $0.count >= 2 })

        // Early-exit to avoid fetching unnecessary profile update messages
        guard !allAddressCollisions.isEmpty else { return [] }
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

        return allAddressCollisions
            .filter { $0.contains(where: { address in profileUpdates[address] != nil }) }
            .map { collidingAddresses in
                NameCollision(collidingAddresses.map { address in
                    let profileUpdateMessages = profileUpdates[address]
                    let oldestUpdateMessage = profileUpdateMessages?.min(by: { $0.sortId < $1.sortId })
                    let newestUpdateMessage = profileUpdateMessages?.max(by: { $0.sortId < $1.sortId })

                    return NameCollision.Element(
                        address: address,
                        currentName: address.getDisplayName(transaction: transaction),
                        oldName: oldestUpdateMessage?.profileChangesOldFullName,
                        latestUpdate: newestUpdateMessage?.timestamp)
                })
            }
    }

    private func fetchRecentProfileUpdates(transaction: SDSAnyReadTransaction) -> [SignalServiceAddress: [TSInfoMessage]] {
        if let cachedResults = recentProfileUpdateMessages { return cachedResults }

        let sortId = lastApprovedProfileUpdateInteractionId(transaction: transaction) ?? 0
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

    public func markCollisionsAsResolved(transaction: SDSAnyWriteTransaction) {
        let allRecentMessages = recentProfileUpdateMessages?.values.flatMap({ $0 })
        guard let newMaxSortId = allRecentMessages?.max(by: { $0.sortId < $1.sortId })?.sortId else { return }

        setLastApprovedProfileUpdateInteractionId(newValue: newMaxSortId, transaction: transaction)
        recentProfileUpdateMessages?.removeAll()
    }

    // MARK: Storage

    private static var keyValueStore = SDSKeyValueStore(collection: "GroupThreadCollisionFinder")

    private func lastApprovedProfileUpdateInteractionId(transaction: SDSAnyReadTransaction) -> UInt64? {
        Self.keyValueStore.getUInt64(groupThread.uniqueId, transaction: transaction)
    }

    private func setLastApprovedProfileUpdateInteractionId(newValue: UInt64, transaction: SDSAnyWriteTransaction) {
        let existingValue = lastApprovedProfileUpdateInteractionId(transaction: transaction) ?? 0
        Self.keyValueStore.setUInt64(max(newValue, existingValue), key: groupThread.uniqueId, transaction: transaction)
    }
}

// MARK: - Helpers

fileprivate extension SignalServiceAddress {
    func getDisplayName(transaction readTx: SDSAnyReadTransaction) -> String {
        Environment.shared.contactsManager.displayName(for: self, transaction: readTx)
    }
}
