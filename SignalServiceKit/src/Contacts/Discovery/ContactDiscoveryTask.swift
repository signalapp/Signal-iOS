//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

/// The primary interface for discovering contacts through the CDS service
@objc(OWSContactDiscoveryTask)
public class ContactDiscoveryTask: NSObject {

    let identifiersToFetch: Set<String>
    @objc public init(identifiers: Set<String>) {
        self.identifiersToFetch = identifiers
    }

    @objc (performOnQueue:success:failure:)
    public func perform(on queue: DispatchQueue = .sharedUtility,
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

    public func perform(on queue: DispatchQueue = .sharedUtility) -> Promise<Set<SignalRecipient>> {
        guard identifiersToFetch.count > 0 else {
            owsFailDebug("Cannot lookup zero identifiers")
            let error = OWSErrorWithCodeDescription(.invalidMethodParameters, "Cannot lookup zero identifiers")
            return Promise(error: error)
        }

        return Promise<Set<DiscoveredContactInfo>> { (resolver) in
            let identifiers = Array(self.identifiersToFetch)
            let operation = self.discoveryProviderMetatype.init(phoneNumbersToLookup: identifiers)
            operation.perform {
                if operation.isCancelled {
                    resolver.reject(NSError())
                } else if let error = operation.failingError {
                    resolver.reject(error)
                } else {
                    resolver.fulfill(operation.discoveredContactInfo ?? Set())
                }
            }

        }.map(on: queue) { (discoveredContacts) -> Set<SignalRecipient> in
            let discoveredIdentifiers = Set(discoveredContacts.compactMap { $0.e164 })

            let addressesToRegister = discoveredContacts
                .map { SignalServiceAddress(uuid: $0.uuid, phoneNumber: $0.e164) }

            let addressesToUnregister = self.identifiersToFetch
                .subtracting(discoveredIdentifiers)
                .map { SignalServiceAddress(uuid: nil, phoneNumber: $0)}

            return SDSDatabaseStorage.shared.write { (tx) -> Set<SignalRecipient> in
                let recipientSet = Set(addressesToRegister.map { address in
                    SignalRecipient.mark(asRegisteredAndGet: address, trustLevel: .high, transaction: tx)
                })
                addressesToUnregister.forEach { address in
                    SignalRecipient.mark(asUnregistered: address, transaction: tx)
                }
                return recipientSet
            }
        }
    }

    private let discoveryProviderMetatype: (OWSOperation & ContactDiscovering).Type = {
        if FeatureFlags.modernContactDiscovery {
            return ContactDiscoveryOperation.self
        } else {
            return LegacyContactDiscoveryOperation.self
        }
    }()
}
