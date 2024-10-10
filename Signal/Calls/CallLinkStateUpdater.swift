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
        return try await _updateExclusively(rootKey: rootKey, updateAndFetch: updateAndFetch)!.get()
    }

    private enum UpdateAction {
        case update(SignalServiceKit.CallLinkState)
        case notFound
        case delete
    }

    private func _updateExclusively(
        rootKey: CallLinkRootKey,
        updateAndFetch: (CallLinkAuthCredential) async throws -> SignalServiceKit.CallLinkState?
    ) async throws -> Result<SignalServiceKit.CallLinkState, CallLinkNotFoundError>? {
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
            return try callLinkStore.fetch(roomId: roomId, tx: tx)
        }
        let authCredential = try await authCredentialManager.fetchCallLinkAuthCredential(localIdentifiers: localIdentifiers)
        let updateResult = await Result { try await updateAndFetch(authCredential) }

        let updateAction: UpdateAction
        let returnResult: Result<SignalServiceKit.CallLinkState, CallLinkNotFoundError>?

        switch updateResult {
        case .success(let callLinkState?):
            updateAction = .update(callLinkState)
            returnResult = .success(callLinkState)
        case .success(nil):
            updateAction = .delete
            returnResult = nil
        case .failure(let error as CallLinkNotFoundError):
            updateAction = .notFound
            returnResult = .failure(error)
        case .failure(let error):
            throw error
        }

        try await db.awaitableWrite { tx in
            if var newRecord = try self.callLinkStore.fetch(roomId: roomId, tx: tx) {
                if !newRecord.isDeleted {
                    switch updateAction {
                    case .update(let newState):
                        newRecord.updateState(newState)
                    case .notFound:
                        break
                    case .delete:
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

        return returnResult
    }

    /// Reads a call link from the server.
    ///
    /// There are two layers of errors interesting to callers: the method itself
    /// and the `Result` that's returned.
    ///
    /// This is a "state updater" object, so if the "state update" operation is
    /// successful, no error is thrown. The "state update" is successful when
    /// we're able to call `clearNeedsFetch` on the underlying CallLinkRecord.
    /// (For example, no error is thrown when the call link can't be found, but
    /// an error *is* thrown when there's no network.)
    ///
    /// Many callers will want access to the `CallLinkState`, and they can use
    /// `try readCallLink(...).get()` to gloss over this distinction.
    func readCallLink(rootKey: CallLinkRootKey) async throws -> Result<SignalServiceKit.CallLinkState, CallLinkNotFoundError> {
        return try await _updateExclusively(rootKey: rootKey, updateAndFetch: { authCredential in
            return try await callLinkFetcher.readCallLink(rootKey, authCredential: authCredential)
        })!
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
