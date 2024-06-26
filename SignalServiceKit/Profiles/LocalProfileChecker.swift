//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

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
        var decryptedProfile: DecryptedProfile?
    }

    private struct State {
        var isReconciling: Bool = false
        var mostRecentRemoteProfile: RemoteProfile?
        var mostRecentRemoteProfileUpdateCount = 0
        var consecutiveMismatchCount = 0
    }

    private let state = AtomicValue(State(), lock: .init())

    func didFetchLocalProfile(_ remoteProfile: RemoteProfile) {
        state.update {
            $0.mostRecentRemoteProfile = remoteProfile
            $0.mostRecentRemoteProfileUpdateCount += 1
        }
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

    private func waitForSteadyState() async throws -> RemoteProfile {
        while true {
            let updateCountSnapshot = state.get().mostRecentRemoteProfileUpdateCount

            // When changing your own profile name/avatar, your profile and Storage
            // Service can't be updated atomically. As a result, it's possible that we
            // may temporarily see inconsistencies. Given that this class is about
            // eventual consistency, wait a few seconds after fetching our own profile
            // to give linked devices a chance to finish updating Storage Service.
            try await Task.sleep(nanoseconds: 3*NSEC_PER_SEC)

            // At this point, we believe the linked device will have queued a sync
            // message (if necessary) and that the latest information is available on
            // Storage Service. Wait for both of those systems to stabilize.
            await messageProcessor.waitForFetchingAndProcessing().awaitable()
            try await storageServiceManager.waitForPendingRestores().asVoid().awaitable()

            // After waiting, ensure we're still considering the same profile. If we're
            // not, wait again since it's possible that our profile changed again.
            let stableProfile = state.update { mutableState -> RemoteProfile? in
                guard mutableState.mostRecentRemoteProfileUpdateCount == updateCountSnapshot else {
                    return nil
                }
                let result = mutableState.mostRecentRemoteProfile!
                mutableState.mostRecentRemoteProfile = nil
                return result
            }
            if let stableProfile {
                return stableProfile
            }
        }
    }

    private func reconcileProfile() async throws {
        let mostRecentRemoteProfile = try await waitForSteadyState()

        var mustReuploadAvatar = false
        let shouldReuploadProfile = db.read { tx in
            guard let localAddress = tsAccountManager.localIdentifiers(tx: tx)?.aciAddress else {
                owsFailDebug("Not registered.")
                return false
            }
            guard let localProfile = profileManager.getUserProfile(for: localAddress, transaction: SDSDB.shimOnlyBridge(tx)) else {
                return false
            }
            guard let decryptedProfile = mostRecentRemoteProfile.decryptedProfile else {
                Logger.warn("Will reupload; we don't appear to have a profile")
                return true
            }
            // We check these because they are considered "Storage Service properties"
            // in OWSUserProfile.applyChanges & consider the local state to be the
            // source of truth.
            var mismatchedProperties = [String]()
            if localProfile.avatarUrlPath != mostRecentRemoteProfile.avatarUrlPath {
                mustReuploadAvatar = true
                mismatchedProperties.append("avatarUrlPath")
            }
            if localProfile.givenName != (try? decryptedProfile.nameComponents.get()?.givenName) {
                mismatchedProperties.append("givenName")
            }
            if localProfile.familyName != (try? decryptedProfile.nameComponents.get()?.familyName) {
                mismatchedProperties.append("familyName")
            }
            let localPhoneNumberSharing = udManager.phoneNumberSharingMode(tx: tx).orDefault == .everybody
            if localPhoneNumberSharing != (try? decryptedProfile.phoneNumberSharing.get()) {
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
            profileManager.reuploadLocalProfile(
                unsavedRotatedProfileKey: nil,
                mustReuploadAvatar: mustReuploadAvatar,
                authedAccount: .implicit(),
                tx: tx
            )
        }.awaitable()
    }
}
