//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalCoreKit

final class LocalProfileChecker {
    private let db: any DB
    private let messageProcessor: MessageProcessor
    private let profileManager: any ProfileManager
    private let storageServiceManager: any StorageServiceManager
    private let tsAccountManager: any TSAccountManager
    private let udManager: any OWSUDManager

    init(
        db: any DB,
        messageProcessor: MessageProcessor,
        profileManager: any ProfileManager,
        storageServiceManager: any StorageServiceManager,
        tsAccountManager: any TSAccountManager,
        udManager: any OWSUDManager
    ) {
        self.db = db
        self.messageProcessor = messageProcessor
        self.profileManager = profileManager
        self.storageServiceManager = storageServiceManager
        self.tsAccountManager = tsAccountManager
        self.udManager = udManager
    }

    struct RemoteProfile {
        var avatarUrlPath: String?
        var decryptedProfile: DecryptedProfile
    }

    private struct State {
        var isReconciling: Bool = false
        var mostRecentRemoteProfile: RemoteProfile?
        var consecutiveMismatchCount = 0
    }

    private let state = AtomicValue(State(), lock: AtomicLock())

    func didFetchLocalProfile(_ remoteProfile: RemoteProfile) {
        state.update { $0.mostRecentRemoteProfile = remoteProfile }
        reconcileProfileIfNeeded()
    }

    private func reconcileProfileIfNeeded() {
        let shouldStart = state.update {
            if $0.isReconciling {
                return false
            }
            if $0.mostRecentRemoteProfile == nil {
                return false
            }
            $0.isReconciling = true
            return true
        }
        guard shouldStart else {
            return
        }
        Task {
            do {
                do {
                    defer {
                        state.update { $0.isReconciling = false }
                    }
                    try await self.reconcileProfile()
                }
                reconcileProfileIfNeeded()
            } catch {
                // Stop if we hit an error; we'll retry the next time we fetch our profile.
            }
        }
    }

    private func reconcileProfile() async throws {
        // Wait until we've reached the current state of the world to ensure we're
        // comparing the latest remote profile against the latest local copy.
        await messageProcessor.waitForFetchingAndProcessing().awaitable()
        try await storageServiceManager.waitForPendingRestores().asVoid().awaitable()

        // After waiting, grab the `mostRecentRemoteProfile`. We do this after
        // waiting since we might fetch it several more times while waiting, and we
        // only want to consider the latest profile.
        let mostRecentRemoteProfile = state.update {
            let result = $0.mostRecentRemoteProfile!
            $0.mostRecentRemoteProfile = nil
            return result
        }

        let shouldReuploadProfile = db.read { tx in
            guard let localAddress = tsAccountManager.localIdentifiers(tx: tx)?.aciAddress else {
                owsFailDebug("Not registered.")
                return false
            }
            guard let localProfile = profileManager.getUserProfile(for: localAddress, transaction: SDSDB.shimOnlyBridge(tx)) else {
                return false
            }
            // We check these because they are considered "Storage Service properties"
            // in OWSUserProfile.applyChanges & consider the local state to be the
            // source of truth.
            var mismatchedProperties = [String]()
            if localProfile.avatarUrlPath != mostRecentRemoteProfile.avatarUrlPath {
                mismatchedProperties.append("avatarUrlPath")
            }
            if localProfile.givenName != mostRecentRemoteProfile.decryptedProfile.givenName {
                mismatchedProperties.append("givenName")
            }
            if localProfile.familyName != mostRecentRemoteProfile.decryptedProfile.familyName {
                mismatchedProperties.append("familyName")
            }
            let localPhoneNumberSharing = udManager.phoneNumberSharingMode(tx: tx) == .everybody
            if localPhoneNumberSharing != mostRecentRemoteProfile.decryptedProfile.phoneNumberSharing {
                mismatchedProperties.append("phoneNumberSharing")
            }

            if mismatchedProperties.isEmpty {
                return false
            }

            Logger.warn("Will reupload; found mismatched properties: [\(mismatchedProperties.joined(separator: ", "))]")
            return true
        }

        guard shouldReuploadProfile else {
            state.update { $0.consecutiveMismatchCount = 0 }
            return
        }

        let consecutiveMismatchCount = state.update {
            $0.consecutiveMismatchCount += 1
            return $0.consecutiveMismatchCount
        }

        let backoffDelay = (1 << (consecutiveMismatchCount - 1)) - 1
        if backoffDelay > 0 {
            Logger.warn("Waiting for \(backoffDelay) second(s) due to consecutive mismatches.")
            try await Task.sleep(nanoseconds: UInt64(backoffDelay) * NSEC_PER_SEC)
        }

        try await db.awaitableWrite { [profileManager] tx in
            profileManager.reuploadLocalProfile(unsavedRotatedProfileKey: nil, authedAccount: .implicit(), tx: tx)
        }.awaitable()
    }
}
