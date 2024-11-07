//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

/// The primary interface for discovering contacts through the CDS service.
protocol ContactDiscoveryTaskQueue {
    func perform(for phoneNumbers: Set<String>, mode: ContactDiscoveryMode) async throws -> Set<SignalRecipient>
}

final class ContactDiscoveryTaskQueueImpl: ContactDiscoveryTaskQueue {
    private let db: any DB
    private let recipientDatabaseTable: RecipientDatabaseTable
    private let recipientFetcher: RecipientFetcher
    private let recipientManager: any SignalRecipientManager
    private let recipientMerger: RecipientMerger
    private let tsAccountManager: TSAccountManager
    private let udManager: OWSUDManager
    private let libsignalNet: Net

    init(
        db: any DB,
        recipientDatabaseTable: RecipientDatabaseTable,
        recipientFetcher: RecipientFetcher,
        recipientManager: any SignalRecipientManager,
        recipientMerger: RecipientMerger,
        tsAccountManager: TSAccountManager,
        udManager: OWSUDManager,
        libsignalNet: Net
    ) {
        self.db = db
        self.recipientDatabaseTable = recipientDatabaseTable
        self.recipientFetcher = recipientFetcher
        self.recipientManager = recipientManager
        self.recipientMerger = recipientMerger
        self.tsAccountManager = tsAccountManager
        self.udManager = udManager
        self.libsignalNet = libsignalNet
    }

    func perform(for phoneNumbers: Set<String>, mode: ContactDiscoveryMode) async throws -> Set<SignalRecipient> {
        let e164s = Set(phoneNumbers.compactMap { E164($0) })
        if e164s.isEmpty {
            return []
        }

        let discoveryResults = try await ContactDiscoveryV2Operation(
            e164sToLookup: e164s,
            mode: mode,
            udManager: ContactDiscoveryV2Operation<LibSignalClient.Net>.Wrappers.UDManager(db: db, udManager: udManager),
            connectionImpl: libsignalNet,
            remoteAttestation: ContactDiscoveryV2Operation<LibSignalClient.Net>.Wrappers.RemoteAttestation()
        ).perform()

        return try await self.processResults(requestedPhoneNumbers: e164s, discoveryResults: discoveryResults)
    }

    private func processResults(
        requestedPhoneNumbers: Set<E164>,
        discoveryResults: [ContactDiscoveryResult]
    ) async throws -> Set<SignalRecipient> {
        var registeredRecipients = Set<SignalRecipient>()

        try await TimeGatedBatch.enumerateObjects(discoveryResults, db: db) { discoveryResult, tx in
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                throw OWSAssertionError("Not registered.")
            }
            let recipient = recipientMerger.applyMergeFromContactDiscovery(
                localIdentifiers: localIdentifiers,
                phoneNumber: discoveryResult.e164,
                pni: discoveryResult.pni,
                aci: discoveryResult.aci,
                tx: tx
            )
            guard let recipient else {
                return
            }
            setPhoneNumberDiscoverable(true, for: recipient, tx: tx)
            recipientManager.markAsRegisteredAndSave(recipient, shouldUpdateStorageService: true, tx: tx)

            // We process all the results that we were provided, but we only return the
            // recipients that were specifically requested as part of this operation.
            if requestedPhoneNumbers.contains(discoveryResult.e164) {
                registeredRecipients.insert(recipient)
            }
        }

        let undiscoverablePhoneNumbers = requestedPhoneNumbers.subtracting(discoveryResults.lazy.map { $0.e164 })
        await TimeGatedBatch.enumerateObjects(undiscoverablePhoneNumbers, db: db) { phoneNumber, tx in
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
            let recipient = recipientDatabaseTable.fetchRecipient(phoneNumber: phoneNumber.stringValue, transaction: tx)
            guard let recipient else {
                return
            }
            setPhoneNumberDiscoverable(false, for: recipient, tx: tx)
            guard recipient.aci == nil, recipient.pni == nil else {
                return
            }
            recipientManager.markAsUnregisteredAndSave(recipient, unregisteredAt: .now, shouldUpdateStorageService: true, tx: tx)
        }

        return registeredRecipients
    }

    private func setPhoneNumberDiscoverable(
        _ isPhoneNumberDiscoverable: Bool,
        for recipient: SignalRecipient,
        tx: DBWriteTransaction
    ) {
        if recipient.phoneNumber?.isDiscoverable == isPhoneNumberDiscoverable {
            return
        }
        recipient.phoneNumber?.isDiscoverable = isPhoneNumberDiscoverable
        recipient.anyOverwritingUpdate(transaction: SDSDB.shimOnlyBridge(tx))
    }
}
