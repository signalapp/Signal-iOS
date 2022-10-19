//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

/// The primary interface for discovering contacts through the CDS service
public class ContactDiscoveryTask: NSObject {

    // MARK: - Lifecycle

    /// The set of e164s that will be queried against CDS
    @objc
    public let e164FetchSet: Set<String>

    /// - Parameter phoneNumbers: A set of strings representing phone numbers. These should be e164.
    /// Any non-e164 numbers will be filtered out
    @objc
    public init(phoneNumbers: Set<String>) {
        e164FetchSet = phoneNumbers.filter { $0.isValidE164() }
    }

    // MARK: - Modifiers

    /// Tags this ContactDiscoveryTask as "critical priority". Modifies retry-after behavior to resolve a tiny risk of starvation around contact discovery tasks
    ///
    /// Some ContactDiscoveryTasks are opportunistic, e.g. discovering a user's contacts. Other ContactDiscoveryTasks are important,
    /// e.g. user initiated Find By Phone Number flow. Neither of these are considered "critical priority".
    /// Occasionally, a ContactDiscoveryTask is so important that all message processing in Signal is hung. In this state, we need a successful
    /// CDS lookup in order to resume message processing.
    ///
    /// To reduce the risk of these less critical discovery tasks starving out more critical tasks, a critical task may set this flag true. Critical priority tasks
    /// get an extra retry-after slot.
    /// Example:
    /// User contacts lookup starts, fails with retry-after of 30 minutes. UUIDBackfill starts shortly after. Instead of being blocked for 30 minutes it's allowed to proceed.
    /// If UUIDBackfill fails, the global retry-after counter will be set to the greater of the two failures and it will now affect both critical and non-critical tasks.
    @objc
    var isCriticalPriority = false

    // MARK: - Public

    /// Returns a promise that will perform contact discovery and return SignalRecipients
    /// - Parameter qos: The preferred quality of service for this task. A best effort attempt will be made to ensure that all works is performed
    /// at this priority or higher.
    /// - Parameter targetQueue: Callers may optionally provide a queue to target. Defaults to nil, and in that case work will be dispatched
    /// to the shared serial queue.
    /// - Parameter database: The persistent storage that will be updated with the CDS results. Defaults to the shared database.
    /// Nil is a valid database parameter, but only in a testing context. This will perform the discovery task and return a set of unsaved SignalRecipients
    public func perform(at qos: DispatchQoS = .utility,
                        targetQueue: DispatchQueue? = nil,
                        database: SDSDatabaseStorage? = SDSDatabaseStorage.shared) -> Promise<Set<SignalRecipient>> {
        guard e164FetchSet.count > 0 else {
            return Promise.value(Set())
        }
        if let retryAfterDate = Self.rateLimiter.currentRetryAfterDate(forCriticalPriority: isCriticalPriority) {
            return Promise(error: ContactDiscoveryError.rateLimit(expiryDate: retryAfterDate))
        }

        let workQueue = DispatchQueue(
            label: OWSDispatch.createLabel("\(type(of: self))"),
            qos: qos,
            autoreleaseFrequency: .workItem,
            target: targetQueue ?? .sharedQueue(at: qos))

        return firstly { () -> Promise<Set<DiscoveredContactInfo>> in
            let discoveryOperation = createContactDiscoveryOperation()
            return discoveryOperation.perform(on: workQueue)

        }.map(on: workQueue) { (discoveredContacts: Set<DiscoveredContactInfo>) -> Set<SignalRecipient> in
            let discoveredIdentifiers = Set(discoveredContacts.map { $0.e164 })

            let discoveredAddresses = discoveredContacts
                .map { SignalServiceAddress(uuid: $0.uuid, phoneNumber: $0.e164, trustLevel: .high) }

            let undiscoverableAddresses = self.e164FetchSet
                .subtracting(discoveredIdentifiers)
                .map { SignalServiceAddress(uuid: nil, phoneNumber: $0, trustLevel: .low) }

            return self.storeResults(discoveredAddresses: discoveredAddresses,
                                     undiscoverableAddresses: undiscoverableAddresses,
                                     database: database)

        }.recover(on: workQueue) { error -> Promise<Set<SignalRecipient>> in
            if error.isNetworkConnectivityFailure {
                Logger.warn("ContactDiscoveryTask network failure: \(error)")
            } else {
                Logger.error("ContactDiscoverTask failure: \(error)")
            }
            if let retryAfterDate = (error as? ContactDiscoveryError)?.retryAfterDate {
                Self.rateLimiter.updateRetryAfter(with: retryAfterDate, criticalPriority: self.isCriticalPriority)
            }
            throw error
        }
    }

    // MARK: - Private

    private func createContactDiscoveryOperation() -> ContactDiscovering {
        return SGXContactDiscoveryOperation(e164sToLookup: e164FetchSet)
    }

    private func storeResults(
        discoveredAddresses: [SignalServiceAddress],
        undiscoverableAddresses: [SignalServiceAddress],
        database: SDSDatabaseStorage?
    ) -> Set<SignalRecipient> {

        // It's possible we have an undiscoverable address that has a UUID in a number of
        // scenarios such as (but not exclusive to) the following;
        // * You do "find by phone number" for someone you've previously interacted with
        //   and had a UUID for who is no longer registered.
        // * You do an intersection to lookup someone who has shared their phone number with you
        //   (via message send) but has chose to be undiscoverable by CDS lookups.
        //
        // When any of these scenarios occur, we cannot know with certainty if the user is
        // unregistered or has only turned off discoverability, so we *only* mark the addresses
        // without any UUIDs as unregistered. Everything else we ignore and will identify their
        // current registration status for when either attempting to send a message or fetch
        // their profile in the future.
        let phoneNumberOnlyUndiscoverableAddresses = undiscoverableAddresses.filter { $0.uuid == nil }

        Self.markUsersAsRecentlyKnownToBeUndiscoverable(phoneNumberOnlyUndiscoverableAddresses)

        guard let database = database else {
            // Just return a set of in-memory SignalRecipients built from discoveredAddresses
            owsAssertDebug(CurrentAppContext().isRunningTests)
            #if TESTABLE_BUILD
            return Set(discoveredAddresses.map { SignalRecipient(address: $0) })
            #else
            return Set()
            #endif
        }

        return database.write { tx in
            let recipientSet = Set(discoveredAddresses.map { address -> SignalRecipient in
                return SignalRecipient.mark(asRegisteredAndGet: address, trustLevel: .high, transaction: tx)
            })

            phoneNumberOnlyUndiscoverableAddresses.forEach { address in
                SignalRecipient.mark(asUnregistered: address, transaction: tx)
            }

            return recipientSet
        }
    }
}

// MARK: - Undiscoverable Users

@objc
public extension ContactDiscoveryTask {

    private static let unfairLock = UnfairLock()
    @nonobjc
    private static let undiscoverableUserCache = LRUCache<String, Date>(maxSize: 1024)

    fileprivate static func markUsersAsRecentlyKnownToBeUndiscoverable(_ addresses: [SignalServiceAddress]) {
        guard !addresses.isEmpty else {
            return
        }
        Logger.verbose("Marking users as known to be undiscoverable: \(addresses.count)")

        let markAsUndiscoverableDate = Date()
        unfairLock.withLock {
            for address in addresses {
                guard let phoneNumber = address.phoneNumber else {
                    owsFailDebug("Address missing phoneNumber.")
                    continue
                }
                guard address.uuid == nil else {
                    // Addresses that have UUIDs should never be treated as undiscoverable.
                    owsFailDebug("address unexpectedly had UUID")
                    continue
                }
                Self.undiscoverableUserCache.setObject(markAsUndiscoverableDate, forKey: phoneNumber)
            }
        }
    }

    static func addressesRecentlyMarkedAsUndiscoverableForMessageSends(_ addresses: [SignalServiceAddress]) -> [SignalServiceAddress] {
        return addressesRecentlyMarkedAsUndiscoverable(addresses)
    }

    static func addressesRecentlyMarkedAsUndiscoverableForGroupMigrations(_ addresses: [SignalServiceAddress]) -> [SignalServiceAddress] {
        return addressesRecentlyMarkedAsUndiscoverable(addresses)
    }

    private static func addressesRecentlyMarkedAsUndiscoverable(_ addresses: [SignalServiceAddress]) -> [SignalServiceAddress] {
        return unfairLock.withLock {
            addresses.filter { address in
                guard let phoneNumber = address.phoneNumber else {
                    // We should only be consulting this cache for numbers with a phone number but without a UUID.
                    owsFailDebug("Address missing phone number.")
                    return false
                }
                guard address.uuid == nil else {
                    // Addresses that have UUIDs should never be treated as undiscoverable.
                    owsFailDebug("address unexpectedly had UUID")
                    return false
                }
                guard let markAsUndiscoverableDate = Self.undiscoverableUserCache.object(forKey: phoneNumber) else {
                    // Not marked as undiscoverable.
                    return false
                }
                // Consider the user as undiscoverable if CDS indicated they
                // didn't exist in the last N minutes.
                let acceptableInterval: TimeInterval = 6 * kHourInterval
                return abs(markAsUndiscoverableDate.timeIntervalSinceNow) <= acceptableInterval
            }
        }
    }
}

// MARK: - Retry After tracking

extension ContactDiscoveryTask {

    private static let rateLimiter = RateLimiter()

    // Declared `internal` to expose to tests
    internal final class RateLimiter {
        private var lock: UnfairLock = UnfairLock()
        private var standardRetryAfter: Date = .distantPast
        private var criticalRetryAfter: Date = .distantPast

        fileprivate init() {}
        static internal func createForTesting() -> RateLimiter {
            owsAssertDebug(CurrentAppContext().isRunningTests, "`createForTesting` not intended to be used outside of tests")
            return RateLimiter()

        }

        func updateRetryAfter(with date: Date, criticalPriority: Bool) {
            lock.withLock {
                if criticalPriority {
                    criticalRetryAfter = max(criticalRetryAfter, date)
                }
                standardRetryAfter = max(standardRetryAfter, date)
            }
        }

        func currentRetryAfterDate(forCriticalPriority: Bool) -> Date? {
            lock.withLock {
                let date = forCriticalPriority ? criticalRetryAfter : standardRetryAfter
                return (date > Date()) ? date : nil
            }
        }
    }
}
