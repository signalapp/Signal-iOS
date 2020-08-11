//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

/// The primary interface for discovering contacts through the CDS service
@objc(OWSContactDiscoveryTask)
public class ContactDiscoveryTask: NSObject {

    // MARK: - Lifecycle

    @objc public let identifiersToFetch: Set<String>
    @objc public init(identifiers: Set<String>) {
        self.identifiersToFetch = identifiers
    }

    // MARK: - Modifiers

    /// Tags this ContactDiscoveryTask as "critical priority". Modifies retry-after behavior to resolve a tiny risk of starvation around contact discovery tasks
    ///
    /// Some ContactDiscoveryTasks are opportunistic, e.g. discovering a user's contacts. Other ContactDiscoveryTasks are important,
    /// e.g. user initiated Find By Phone Number flow. Neither of these are considered "critical priority".
    /// Occassionally, a ContactDiscoveryTask is so important that all message processing in Signal is hung. In this state, we need a successful
    /// CDS lookup in order to resume message processing.
    ///
    /// To reduce the risk of these less critical discovery tasks starving out more critical tasks, a critical task may set this flag true. Critical priority tasks
    /// get an extra retry-after slot.
    /// Example:
    /// User contacts lookup starts, fails with retry-after of 30 minutes. UUIDBackfill starts shortly after. Instead of being blocked for 30 minutes it's allowed to proceed.
    /// If UUIDBackfill fails, the global retry-after counter will be set to the greater of the two failures and it will now affect both critical and non-critical tasks.
    @objc var criticalPriority = false

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
        guard identifiersToFetch.count > 0 else {
            return .value(Set())
        }
        if let retryAfterDate = Self.rateLimiter.currentRetryAfterDate(forCriticalPriority: criticalPriority) {
            return Promise(error: ContactDiscoveryError.rateLimit(expiryDate: retryAfterDate))
        }

        let workQueue = DispatchQueue(
            label: "org.whispersystems.signal.\(type(of: self))",
            qos: qos,
            autoreleaseFrequency: .workItem,
            target: targetQueue ?? .sharedQueue(at: qos))

        return firstly { () -> Promise<Set<DiscoveredContactInfo>> in
            let discoveryOperation = createContactDiscoveryOperation()
            return discoveryOperation.perform(on: workQueue)

        }.map(on: workQueue) { (discoveredContacts) -> Set<SignalRecipient> in
            let discoveredIdentifiers = Set(discoveredContacts.compactMap { $0.e164 })

            let addressesToRegister = discoveredContacts
                .map { SignalServiceAddress(uuid: $0.uuid, phoneNumber: $0.e164, trustLevel: .high) }

            let addressesToUnregister = self.identifiersToFetch
                .subtracting(discoveredIdentifiers)
                .map { SignalServiceAddress(uuid: nil, phoneNumber: $0, trustLevel: .high)}

            return self.storeResults(registering: addressesToRegister,
                                     unregistering: addressesToUnregister,
                                     database: database)

        }.recover(on: workQueue) { error -> Promise<Set<SignalRecipient>> in
            if IsNetworkConnectivityFailure(error) {
                Logger.warn("ContactDiscoveryTask network failure: \(error)")
            } else {
                owsFailDebug("ContactDiscoverTask failure: \(error)")
            }
            if let retryAfterDate = error.retryAfterDate {
                Self.rateLimiter.updateRetryAfter(with: retryAfterDate, criticalPriority: self.criticalPriority)
            }
            throw error
        }
    }

    // MARK: - Private

    private func createContactDiscoveryOperation() -> ContactDiscovering {
        if RemoteConfig.modernContactDiscovery {
            return ModernContactDiscoveryOperation(phoneNumbersToLookup: identifiersToFetch)
        } else {
            return LegacyContactDiscoveryOperation(phoneNumbersToLookup: identifiersToFetch)
        }
    }

    private func storeResults(registering toRegister: [SignalServiceAddress],
                              unregistering toUnregister: [SignalServiceAddress],
                              database: SDSDatabaseStorage?) -> Set<SignalRecipient> {

        Self.markUsersAsRecentlyKnownToBeUnregistered(toUnregister)

        guard let database = database else {
            // Just return a set of in-memory SignalRecipients built from toRegister
            owsAssertDebug(CurrentAppContext().isRunningTests)
            return Set(toRegister.map { SignalRecipient(address: $0) })
        }

        return database.write { tx in
            let recipientSet = Set(toRegister.map { address -> SignalRecipient in
                return SignalRecipient.mark(asRegisteredAndGet: address, trustLevel: .high, transaction: tx)
            })
            toUnregister.forEach { address in
                SignalRecipient.mark(asUnregistered: address, transaction: tx)
            }
            return recipientSet
        }
    }
}

// MARK: - ObjC Support

@objc public extension ContactDiscoveryTask {

    @objc (performAtQoS:callbackQueue:success:failure:)
    func perform(at rawQoS: qos_class_t,
                 callbackQueue: DispatchQueue,
                 success: @escaping (Set<SignalRecipient>) -> Void,
                 failure: @escaping (Error) -> Void) {
        firstly { () -> Promise<Set<SignalRecipient>> in
            let qosClass = DispatchQoS.QoSClass(flooring: rawQoS)
            let qos = DispatchQoS(qosClass: qosClass, relativePriority: 0)
            return perform(at: qos)
        }.done(on: callbackQueue) { (results) in
            success(results)
        }.catch(on: callbackQueue) { error in
            failure(error)
        }
    }
}

// MARK: - Unregistered Users

@objc
public extension ContactDiscoveryTask {

    private static let unfairLock = UnfairLock()
    private static let unregisteredUserCache = NSCache<NSString, NSDate>()

    fileprivate static func markUsersAsRecentlyKnownToBeUnregistered(_ addresses: [SignalServiceAddress]) {
        guard !addresses.isEmpty else {
            return
        }
        guard FeatureFlags.ignoreCDSUnregisteredUsersInMessageSends else {
            return
        }
        Logger.verbose("Marking users as known to be unregistered: \(addresses.count)")

        let markAsUnregisteredDate = Date() as NSDate
        unfairLock.withLock {
            for address in addresses {
                guard let phoneNumber = address.phoneNumber else {
                    owsFailDebug("Address missing phoneNumber.")
                    continue
                }
                Self.unregisteredUserCache.setObject(markAsUnregisteredDate, forKey: phoneNumber as NSString)
            }
        }
    }

    static func addressesRecentlyMarkedAsUnregistered(_ addresses: [SignalServiceAddress]) -> [SignalServiceAddress] {
        guard FeatureFlags.ignoreCDSUnregisteredUsersInMessageSends else {
            return []
        }
        return unfairLock.withLock {
            addresses.filter { address in
                guard let phoneNumber = address.phoneNumber else {
                    // We should only be consulting this cache for numbers with a phone number but without a UUID.
                    owsFailDebug("Address missing phone number.")
                    return false
                }
                guard let markAsUnregisteredDate = Self.unregisteredUserCache.object(forKey: phoneNumber as NSString) else {
                    // Not marked as unregistered.
                    return false
                }
                // Consider the user as unregistered if CDS indicated they were
                // unregistered in the last N minutes.
                let acceptableInterval: TimeInterval = kHourInterval
                return abs(markAsUnregisteredDate.timeIntervalSinceNow) <= acceptableInterval
            }
        }
    }
}

// MARK: - Retry After tracking

fileprivate extension ContactDiscoveryTask {

    static let rateLimiter = RateLimiter()

    class RateLimiter {
        var lock: UnfairLock = UnfairLock()
        var standardRetryAfter: Date = .distantPast
        var criticalRetryAfter: Date = .distantPast

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
