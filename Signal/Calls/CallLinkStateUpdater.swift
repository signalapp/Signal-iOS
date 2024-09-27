//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalRingRTC
import SignalServiceKit
import SignalUI

/// Ensures mutually exclusive access for call link fetches/updates.
///
/// Both "read" and "update" operations may race with one another. (For
/// example, a "read" and "update" executed in parallel may complete in
/// either order, and the "read" may or may not see the newly-updated
/// state.) This type ensures "old" reads don't clobber "new" updates.
actor CallLinkStateUpdater {
    private let authCredentialManager: any AuthCredentialManager
    private let callLinkFetcher: CallLinkFetcherImpl
    private let callLinkStore: any CallLinkRecordStore
    private let db: any DB
    private let tsAccountManager: any TSAccountManager

    private var pendingUpdates: [Data: [CheckedContinuation<Void, Never>]]

    init(
        authCredentialManager: any AuthCredentialManager,
        callLinkFetcher: CallLinkFetcherImpl,
        callLinkStore: any CallLinkRecordStore,
        db: any DB,
        tsAccountManager: any TSAccountManager
    ) {
        self.authCredentialManager = authCredentialManager
        self.callLinkFetcher = callLinkFetcher
        self.callLinkStore = callLinkStore
        self.db = db
        self.tsAccountManager = tsAccountManager

        self.pendingUpdates = [:]
    }

    /// Runs `updateAndFetch` and persists the returned value.
    ///
    /// Note: The returned value is only persisted if the call link already
    /// exists. This ensures we don't create orphaned call link records that the
    /// user never joins.
    func updateExclusively(
        rootKey: CallLinkRootKey,
        updateAndFetch: (CallLinkAuthCredential) async throws -> SignalServiceKit.CallLinkState
    ) async throws -> SignalServiceKit.CallLinkState {
        let roomId = rootKey.deriveRoomId()

        await withCheckedContinuation { continuation in
            if pendingUpdates[roomId] == nil {
                pendingUpdates[roomId] = []
                continuation.resume()
            } else {
                pendingUpdates[roomId]!.append(continuation)
            }
        }
        defer {
            if let nextUpdate = pendingUpdates[roomId]!.first {
                pendingUpdates[roomId] = Array(pendingUpdates[roomId]!.dropFirst())
                nextUpdate.resume()
            } else {
                pendingUpdates[roomId] = nil
            }
        }

        guard let localIdentifiers = tsAccountManager.localIdentifiersWithMaybeSneakyTransaction else {
            throw OWSGenericError("Not registered.")
        }
        let oldRecord = try db.read { tx -> CallLinkRecord? in
            guard FeatureFlags.callLinkRecordTable else {
                return nil
            }
            return try callLinkStore.fetch(roomId: roomId, tx: tx)
        }
        let authCredential = try await authCredentialManager.fetchCallLinkAuthCredential(localIdentifiers: localIdentifiers)
        let newState = try await updateAndFetch(authCredential)
        try await db.awaitableWrite { tx in
            guard FeatureFlags.callLinkRecordTable else {
                return
            }
            if var newRecord = try self.callLinkStore.fetch(roomId: roomId, tx: tx) {
                if !newRecord.isDeleted {
                    newRecord.updateState(newState)
                }
                if newRecord.pendingFetchCounter == oldRecord?.pendingFetchCounter {
                    newRecord.clearNeedsFetch()
                }
                try self.callLinkStore.update(newRecord, tx: tx)
            }
        }
        return newState
    }

    func readCallLink(rootKey: CallLinkRootKey) async throws -> SignalServiceKit.CallLinkState {
        return try await updateExclusively(rootKey: rootKey, updateAndFetch: { authCredential in
            return try await callLinkFetcher.readCallLink(rootKey, authCredential: authCredential)
        })
    }
}
