//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public class AccountChecker {
    private let db: any DB
    private let networkManager: NetworkManager
    private let recipientFetcher: any RecipientFetcher
    private let recipientManager: any SignalRecipientManager
    private let recipientMerger: any RecipientMerger
    private let recipientStore: RecipientDatabaseTable
    private let tsAccountManager: any TSAccountManager

    init(
        db: any DB,
        networkManager: NetworkManager,
        recipientFetcher: any RecipientFetcher,
        recipientManager: any SignalRecipientManager,
        recipientMerger: any RecipientMerger,
        recipientStore: RecipientDatabaseTable,
        tsAccountManager: any TSAccountManager
    ) {
        self.db = db
        self.networkManager = networkManager
        self.recipientFetcher = recipientFetcher
        self.recipientManager = recipientManager
        self.recipientMerger = recipientMerger
        self.recipientStore = recipientStore
        self.tsAccountManager = tsAccountManager
    }

    /// Checks if an account exists for `serviceId`.
    ///
    /// If it exists, the `SignalRecipient` is marked as "registered". If it
    /// doesn't exist, the `SignalRecipient` is marked as "unregistered".
    func checkIfAccountExists(serviceId: ServiceId) async throws {
        let accountRequest = OWSRequestFactory.accountRequest(serviceId: serviceId)
        do {
            let response = try await networkManager.asyncRequest(accountRequest)
            guard response.responseStatusCode == 200 else {
                throw OWSGenericError("Unexpected server response.")
            }
            await db.awaitableWrite { tx in
                let recipient = recipientFetcher.fetchOrCreate(serviceId: serviceId, tx: tx)
                recipientManager.markAsRegisteredAndSave(recipient, shouldUpdateStorageService: true, tx: tx)
            }
        } catch where error.httpStatusCode == 404 {
            await db.awaitableWrite { tx in
                self.markAsUnregisteredAndSplitRecipientIfNeeded(serviceId: serviceId, shouldUpdateStorageService: true, tx: tx)
            }
            throw error
        }
    }

    func markAsUnregisteredAndSplitRecipientIfNeeded(
        serviceId: ServiceId,
        shouldUpdateStorageService: Bool,
        tx: DBWriteTransaction
    ) {
        AssertNotOnMainThread()

        guard let recipient = recipientStore.fetchRecipient(serviceId: serviceId, transaction: tx) else {
            return
        }

        recipientManager.markAsUnregisteredAndSave(
            recipient,
            unregisteredAt: .now,
            shouldUpdateStorageService: shouldUpdateStorageService,
            tx: tx
        )

        guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
            Logger.warn("Can't split recipient because we're not registered.")
            return
        }

        recipientMerger.splitUnregisteredRecipientIfNeeded(
            localIdentifiers: localIdentifiers,
            unregisteredRecipient: recipient,
            tx: tx
        )
    }
}
