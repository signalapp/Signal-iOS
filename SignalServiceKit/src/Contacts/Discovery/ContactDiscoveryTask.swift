//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

/// The primary interface for discovering contacts through the CDS service.
protocol ContactDiscoveryTaskQueue {
    func perform(for phoneNumbers: Set<String>, mode: ContactDiscoveryMode) -> Promise<Set<SignalRecipient>>
}

final class ContactDiscoveryTaskQueueImpl: ContactDiscoveryTaskQueue, Dependencies {
    func perform(for phoneNumbers: Set<String>, mode: ContactDiscoveryMode) -> Promise<Set<SignalRecipient>> {
        let e164s = Set(phoneNumbers.compactMap { E164($0) })
        guard !e164s.isEmpty else {
            return .value([])
        }

        let workQueue = DispatchQueue(
            label: "contact-discovery-task",
            qos: .userInitiated,
            autoreleaseFrequency: .workItem,
            target: .sharedUserInitiated
        )

        return firstly {
            Self.createContactDiscoveryOperation(for: e164s, mode: mode).perform(on: workQueue)
        }.map(on: workQueue) { (discoveredContacts: Set<DiscoveredContactInfo>) -> Set<SignalRecipient> in
            let discoveredE164s = Set(discoveredContacts.map { $0.e164 })

            let discoveredAddresses = discoveredContacts
                .map { SignalServiceAddress(uuid: $0.uuid, phoneNumber: $0.e164.stringValue, trustLevel: .high) }

            let undiscoverableAddresses = e164s.subtracting(discoveredE164s).map { SignalServiceAddress($0) }

            return Self.storeResults(
                discoveredAddresses: discoveredAddresses,
                undiscoverableAddresses: undiscoverableAddresses
            )
        }
    }

    private static func createContactDiscoveryOperation(for e164s: Set<E164>, mode: ContactDiscoveryMode) -> ContactDiscoveryOperation {
        if !RemoteConfig.contactDiscoveryV2KillSwitch {
            return ContactDiscoveryV2CompatibilityOperation(e164sToLookup: e164s, mode: mode)
        } else {
            return SGXContactDiscoveryOperation(e164sToLookup: e164s, mode: mode)
        }
    }

    private static func storeResults(
        discoveredAddresses: [SignalServiceAddress],
        undiscoverableAddresses: [SignalServiceAddress]
    ) -> Set<SignalRecipient> {

        // It's possible we have an undiscoverable address that has a UUID in a
        // number of scenarios, such as (but not exclusive to) the following:
        //
        // * You do "find by phone number" for someone you've previously interacted
        //   with (and had a UUID for) who is no longer registered.
        //
        // * You do an intersection to look up someone who has shared their phone
        //   number with you (via message send) but has chosen to be undiscoverable
        //   by CDS lookups.
        //
        // When any of these scenarios occur, we cannot know with certainty if the
        // user is unregistered or has only turned off discoverability, so we
        // *only* mark the addresses without any UUIDs as unregistered. Everything
        // else we ignore; we will identify their current registration status
        // either when attempting to send a message or when fetching their profile.
        //
        // The UUIDBackfillTask relies on this behavior in order to converge. If we
        // don't mark undiscoverable addresses without a UUID as unregistered,
        // we'll look them up again on the next launch.
        let phoneNumberOnlyUndiscoverableAddresses = undiscoverableAddresses.filter { $0.uuid == nil }

        return databaseStorage.write { transaction in
            let registeredRecipients = Set(discoveredAddresses.map { address -> SignalRecipient in
                let recipient = SignalRecipient.fetchOrCreate(for: address, trustLevel: .high, transaction: transaction)
                recipient.markAsRegistered(transaction: transaction)
                return recipient
            })
            phoneNumberOnlyUndiscoverableAddresses.forEach { address in
                let recipient = SignalRecipient.fetchOrCreate(for: address, trustLevel: .low, transaction: transaction)
                recipient.markAsUnregistered(transaction: transaction)
            }
            return registeredRecipients
        }
    }
}
