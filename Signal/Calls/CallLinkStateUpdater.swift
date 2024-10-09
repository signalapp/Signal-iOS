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
    private let callLinkManager: any CallLinkManager
    private let callLinkStore: any CallLinkRecordStore
    private let callRecordDeleteManager: any CallRecordDeleteManager
    private let callRecordStore: any CallRecordStore
    private let db: any DB
    private let tsAccountManager: any TSAccountManager

    private var pendingUpdates: [Data: [CheckedContinuation<Void, Never>]]

    init(
        authCredentialManager: any AuthCredentialManager,
        callLinkFetcher: CallLinkFetcherImpl,
        callLinkManager: any CallLinkManager,
        callLinkStore: any CallLinkRecordStore,
        callRecordDeleteManager: any CallRecordDeleteManager,
        callRecordStore: any CallRecordStore,
        db: any DB,
        tsAccountManager: any TSAccountManager
    ) {
        self.authCredentialManager = authCredentialManager
        self.callLinkFetcher = callLinkFetcher
        self.callLinkManager = callLinkManager
        self.callLinkStore = callLinkStore
        self.callRecordDeleteManager = callRecordDeleteManager
        self.callRecordStore = callRecordStore
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
        return try await _updateExclusively(rootKey: rootKey, updateAndFetch: updateAndFetch)!
    }

    private func _updateExclusively(
        rootKey: CallLinkRootKey,
        updateAndFetch: (CallLinkAuthCredential) async throws -> SignalServiceKit.CallLinkState?
    ) async throws -> SignalServiceKit.CallLinkState? {
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
                    if let newState {
                        newRecord.updateState(newState)
                    } else {
                        newRecord.markDeleted(atTimestampMs: Date.ows_millisecondTimestamp())
                        try self.callRecordDeleteManager.deleteCallRecords(
                            self.callRecordStore.fetchExisting(conversationId: .callLink(callLinkRowId: newRecord.id), limit: nil, tx: tx),
                            sendSyncMessageOnDelete: true,
                            tx: tx
                        )
                    }
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

    func deleteCallLink(rootKey: CallLinkRootKey, adminPasskey: Data) async throws {
        _ = try await _updateExclusively(
            rootKey: rootKey,
            updateAndFetch: { authCredential in
                try await callLinkManager.deleteCallLink(rootKey: rootKey, adminPasskey: adminPasskey, authCredential: authCredential)
                return nil
            }
        )
    }
}
