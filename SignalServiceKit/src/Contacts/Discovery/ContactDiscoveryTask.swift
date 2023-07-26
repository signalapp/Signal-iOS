//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

/// The primary interface for discovering contacts through the CDS service.
protocol ContactDiscoveryTaskQueue {
    func perform(for phoneNumbers: Set<String>, mode: ContactDiscoveryMode) -> Promise<Set<SignalRecipient>>
}

final class ContactDiscoveryTaskQueueImpl: ContactDiscoveryTaskQueue {
    private let db: DB
    private let recipientFetcher: RecipientFetcher
    private let recipientMerger: RecipientMerger
    private let tsAccountManager: TSAccountManager
    private let websocketFactory: WebSocketFactory

    init(
        db: DB,
        recipientFetcher: RecipientFetcher,
        recipientMerger: RecipientMerger,
        tsAccountManager: TSAccountManager,
        websocketFactory: WebSocketFactory
    ) {
        self.db = db
        self.recipientFetcher = recipientFetcher
        self.recipientMerger = recipientMerger
        self.tsAccountManager = tsAccountManager
        self.websocketFactory = websocketFactory
    }

    func perform(for phoneNumbers: Set<String>, mode: ContactDiscoveryMode) -> Promise<Set<SignalRecipient>> {
        let e164s = Set(phoneNumbers.compactMap { E164($0) })
        guard !e164s.isEmpty else {
            return .value([])
        }

        let workQueue = DispatchQueue(
            label: "org.signal.contact-discovery-task",
            qos: .userInitiated,
            autoreleaseFrequency: .workItem,
            target: .sharedUserInitiated
        )

        return firstly {
            Self.createContactDiscoveryOperation(
                for: e164s,
                mode: mode,
                websocketFactory: websocketFactory
            ).perform(on: workQueue)
        }.map(on: workQueue) { (discoveredContacts: Set<DiscoveredContactInfo>) -> Set<SignalRecipient> in
            try self.processResults(requestedPhoneNumbers: e164s, discoveryResults: discoveredContacts)
        }
    }

    private static func createContactDiscoveryOperation(
        for e164s: Set<E164>,
        mode: ContactDiscoveryMode,
        websocketFactory: WebSocketFactory
    ) -> ContactDiscoveryOperation {
        return ContactDiscoveryV2CompatibilityOperation(
            e164sToLookup: e164s,
            mode: mode,
            websocketFactory: websocketFactory
        )
    }

    private func processResults(
        requestedPhoneNumbers: Set<E164>,
        discoveryResults: Set<DiscoveredContactInfo>
    ) throws -> Set<SignalRecipient> {
        let undiscoverableE164s = requestedPhoneNumbers.subtracting(discoveryResults.lazy.map { $0.e164 })

        return try db.write { tx in
            guard let localIdentifiers = tsAccountManager.localIdentifiers(transaction: SDSDB.shimOnlyBridge(tx)) else {
                throw OWSAssertionError("Not registered.")
            }
            return storeResults(
                discoveredContacts: discoveryResults,
                undiscoverableE164s: undiscoverableE164s,
                localIdentifiers: localIdentifiers,
                tx: tx
            )
        }
    }

    private func storeResults(
        discoveredContacts: Set<DiscoveredContactInfo>,
        undiscoverableE164s: Set<E164>,
        localIdentifiers: LocalIdentifiers,
        tx: DBWriteTransaction
    ) -> Set<SignalRecipient> {
        let registeredRecipients = Set(discoveredContacts.map { discoveredContact -> SignalRecipient in
            let recipient = recipientMerger.applyMergeFromContactDiscovery(
                localIdentifiers: localIdentifiers,
                aci: UntypedServiceId(discoveredContact.uuid),
                phoneNumber: discoveredContact.e164,
                tx: tx
            )
            recipient.markAsRegisteredAndSave(tx: SDSDB.shimOnlyBridge(tx))
            return recipient
        })

        for undiscoverableE164 in undiscoverableE164s {
            let address = SignalServiceAddress(undiscoverableE164)

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
            guard address.uuid == nil else {
                continue
            }

            let recipient = recipientFetcher.fetchOrCreate(phoneNumber: undiscoverableE164, tx: tx)
            recipient.markAsUnregisteredAndSave(tx: SDSDB.shimOnlyBridge(tx))
        }

        return registeredRecipients
    }
}
