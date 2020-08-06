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
        let workQueue = DispatchQueue(
            label: "org.whispersystems.signal.\(type(of: self))",
            qos: qos,
            autoreleaseFrequency: .workItem,
            target: targetQueue ?? .sharedQueue(at: qos)
        )

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
            throw error
        }
    }

    // MARK: - Private

    private func createContactDiscoveryOperation() -> ContactDiscovering {
        if FeatureFlags.modernContactDiscovery {
            return ModernContactDiscoveryOperation(phoneNumbersToLookup: identifiersToFetch)
        } else {
            return LegacyContactDiscoveryOperation(phoneNumbersToLookup: identifiersToFetch)
        }
    }

    private func storeResults(registering toRegister: [SignalServiceAddress],
                              unregistering toUnregister: [SignalServiceAddress],
                              database: SDSDatabaseStorage?) -> Set<SignalRecipient> {
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
