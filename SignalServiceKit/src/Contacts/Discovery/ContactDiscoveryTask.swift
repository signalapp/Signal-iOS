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
    private let recipientStore: RecipientDataStore
    private let tsAccountManager: TSAccountManagerProtocol
    private let udManager: OWSUDManager
    private let websocketFactory: WebSocketFactory

    init(
        db: DB,
        recipientFetcher: RecipientFetcher,
        recipientMerger: RecipientMerger,
        recipientStore: RecipientDataStore,
        tsAccountManager: TSAccountManagerProtocol,
        udManager: OWSUDManager,
        websocketFactory: WebSocketFactory
    ) {
        self.db = db
        self.recipientFetcher = recipientFetcher
        self.recipientMerger = recipientMerger
        self.recipientStore = recipientStore
        self.tsAccountManager = tsAccountManager
        self.udManager = udManager
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
            ContactDiscoveryV2Operation(
                e164sToLookup: e164s,
                mode: mode,
                tryToReturnAcisWithoutUaks: RemoteConfig.tryToReturnAcisWithoutUaks,
                udManager: ContactDiscoveryV2Operation.Wrappers.UDManager(db: db, udManager: udManager),
                websocketFactory: websocketFactory
            ).perform(on: workQueue)
        }.map(on: workQueue) { (discoveryResults: [ContactDiscoveryV2Operation.DiscoveryResult]) -> Set<SignalRecipient> in
            try self.processResults(requestedPhoneNumbers: e164s, discoveryResults: discoveryResults)
        }
    }

    private func processResults(
        requestedPhoneNumbers: Set<E164>,
        discoveryResults: [ContactDiscoveryV2Operation.DiscoveryResult]
    ) throws -> Set<SignalRecipient> {
        var registeredRecipients = Set<SignalRecipient>()

        try db.enumerateWithTimeBatchedWriteTx(discoveryResults) { discoveryResult, tx in
            // PNI TODO: Pass the PNI into the merging logic.
            guard let aci = discoveryResult.aci else {
                return
            }
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                throw OWSAssertionError("Not registered.")
            }
            let recipient = recipientMerger.applyMergeFromContactDiscovery(
                localIdentifiers: localIdentifiers,
                aci: aci,
                phoneNumber: discoveryResult.e164,
                tx: tx
            )
            recipient.markAsRegisteredAndSave(tx: SDSDB.shimOnlyBridge(tx))

            // We process all the results that we were provided, but we only return the
            // recipients that were specifically requested as part of this operation.
            if requestedPhoneNumbers.contains(discoveryResult.e164) {
                registeredRecipients.insert(recipient)
            }
        }

        let undiscoverablePhoneNumbers = requestedPhoneNumbers.subtracting(discoveryResults.lazy.map { $0.e164 })
        db.enumerateWithTimeBatchedWriteTx(undiscoverablePhoneNumbers) { phoneNumber, tx in
            // It's possible we have an undiscoverable phone number that already has an
            // ACI or PNI in a number of scenarios, such as (but not exclusive to) the
            // following:
            //
            // * You do "find by phone number" for someone you've previously interacted
            // with (and had an ACI or PNI for) who is no longer registered.
            //
            // * You do an intersection to look up someone who has shared their phone
            // number with you (via message send) but has chosen to be undiscoverable
            // by CDS lookups.
            //
            // When any of these scenarios occur, we cannot know with certainty if the
            // user is unregistered or has only turned off discoverability, so we
            // *only* mark the addresses without any UUIDs as unregistered. Everything
            // else we ignore; we will identify their current registration status
            // either when attempting to send a message or when fetching their profile.
            let recipient = recipientStore.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx)
            guard let recipient, recipient.aci == nil, recipient.pni == nil else {
                return
            }
            recipient.markAsUnregisteredAndSave(tx: SDSDB.shimOnlyBridge(tx))
        }

        return registeredRecipients
    }
}
