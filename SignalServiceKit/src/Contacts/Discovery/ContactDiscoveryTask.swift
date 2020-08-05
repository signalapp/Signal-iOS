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

    /// Returns a promise that will perform contact discovery and SignalRecipients
    /// - Parameter queue: The queue where most work will be performed. Promise will be resolved on this queue, but some underlying
    /// work may be dispatched to a global queue.
    /// - Parameter database: The persistent storage that will be updated with the CDS results. Defaults to the shared database, but
    /// a caller can pass in nil to have the returned Promise resolve to unsaved SignalRecipients
    public func perform(on queue: DispatchQueue = .sharedUtility,
                        database: SDSDatabaseStorage? = SDSDatabaseStorage.shared) -> Promise<Set<SignalRecipient>> {
        guard identifiersToFetch.count > 0 else {
            owsFailDebug("Cannot lookup zero identifiers")
            let error = OWSErrorWithCodeDescription(.invalidMethodParameters, "Cannot lookup zero identifiers")
            return Promise(error: error)
        }

        return firstly { () -> Promise<Set<DiscoveredContactInfo>> in
            let discoveryOperation = createContactDiscoveryOperation()
            return discoveryOperation.perform(on: queue)

        }.map(on: queue) { (discoveredContacts) -> Set<SignalRecipient> in
            let discoveredIdentifiers = Set(discoveredContacts.compactMap { $0.e164 })

            let addressesToRegister = discoveredContacts
                .map { SignalServiceAddress(uuid: $0.uuid, phoneNumber: $0.e164) }

            let addressesToUnregister = self.identifiersToFetch
                .subtracting(discoveredIdentifiers)
                .map { SignalServiceAddress(uuid: nil, phoneNumber: $0)}

            return self.storeResults(registering: addressesToRegister,
                                     unregistering: addressesToUnregister,
                                     database: database)

        }.recover(on: queue) { error -> Promise<Set<SignalRecipient>> in
            // Insert our log message then rethrow
            Logger.warn("ContactDiscoveryTask failed: \(error)")
            return Promise(error: error)
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

    @objc (performOnQueue:success:failure:)
    func perform(on queue: DispatchQueue = .sharedUtility,
                        success: @escaping (Set<SignalRecipient>) -> Void,
                        failure: @escaping (Error) -> Void) {
        firstly {
            perform(on: queue)
        }.done(on: queue) { (results) in
            success(results)
        }.catch(on: queue) { error in
            failure(error)
        }
    }
}
