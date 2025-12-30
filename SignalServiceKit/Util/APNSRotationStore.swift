//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

/// This object serves as a store of data for interop between the NSE and SyncPushTokensJob.
/// It lets the NSE record when it handles messages, so that if it hasn't done so in a while,
/// SyncPushTokensJob can rotate the APNS token to try and recover.
public final class APNSRotationStore {

    private static let kvStore = KeyValueStore(collection: "APNSRotationStore")

    // exposed for testing. we need a better way to do this.
    static var nowMs: () -> UInt64 = { Date().ows_millisecondsSince1970 }

    public static func didReceiveAPNSPush(transaction: DBWriteTransaction) {
        // See comments on `setAppVersionTimeForAPNSRotationIfNeeded`.
        // If we actually get an APNS push, even before the app version bake time
        // has passed, we have all the state we need and don't need the app version
        // check anymore. Bypass it by writing a timestamp far enough in the past that
        // we think the bake time has passed already.
        kvStore.setUInt64(
            nowMs() - Constants.appVersionBakeTimeMs - 1,
            key: Constants.apnsRotationAppVersionUpdateTimestampKey,
            transaction: transaction,
        )
        // Mark the current token as one we know works!
        guard let token = SSKEnvironment.shared.preferencesRef.getPushToken(tx: transaction) else {
            // The value returned by `getPushToken` is saved after we receive a
            // successful response from the server. If that response gets lost, the
            // server may have (and use) a token that we haven't yet persisted. That's
            // unusual but correct behavior.
            //
            // Additionally, the server may send a push challenge using an APNs token
            // we haven't yet persisted to disk; that's also expected behavior.
            Logger.warn("Got a push without a push token; not marking any token as working.")
            return
        }
        kvStore.setString(
            token,
            key: Constants.lastKnownWorkingAPNSTokenKey,
            transaction: transaction,
        )
        kvStore.setUInt64(
            nowMs(),
            key: Constants.lastKnownWorkingAPNSTokenTimestampKey,
            transaction: transaction,
        )
    }

    public static func didRotateAPNSToken(transaction: DBWriteTransaction) {
        kvStore.setUInt64(
            nowMs(),
            key: Constants.lastAPNSRotationTimestampKey,
            transaction: transaction,
        )
        kvStore.removeValue(
            forKey: Constants.lastKnownWorkingAPNSTokenKey,
            transaction: transaction,
        )
        kvStore.removeValue(
            forKey: Constants.lastKnownWorkingAPNSTokenTimestampKey,
            transaction: transaction,
        )
    }

    /// Call this on app startup once launched, registered, and ready.
    /// Takes a closure that rotates the APNS token. If the token should be rotated, calls this closure.
    public static func rotateIfNeededOnAppLaunchAndReadiness(
        waitForFetchingAndProcessing: () async throws(CancellationError) -> Void,
        performRotation: () async throws -> Void,
    ) async throws {
        // Structuring as efficiently as possible: in a single read we check if we
        // are eligible to rotate, if not whether we need to open an expensive write transaction
        // to write the app version to (which we should only ever do once),
        // if we need to write the "known good" token timestamp (only need to do this once
        // to catch app versions from after we started rotating but before we wrote timestamps),
        // and if we are eligible to rotate fetch the latest message for later comparison.
        // Presence of a latestMessageTimestamp implies we should attempt a rotation after message processing.
        let (needsAppVersionWrite, needsKnownWorkingWrite, latestMessageTimestamp) =
            SSKEnvironment.shared.databaseStorageRef.read { transaction -> (Bool, Bool, UInt64?) in
                let needsKnownWorkingWrite = APNSRotationStore.kvStore.hasValue(
                    Constants.lastKnownWorkingAPNSTokenKey,
                    transaction: transaction,
                ) && !APNSRotationStore.kvStore.hasValue(
                    Constants.lastKnownWorkingAPNSTokenTimestampKey,
                    transaction: transaction,
                )
                if APNSRotationStore.needsAppVersionWrite(transaction: transaction) {
                    // We need to do a write to set the app version check.
                    // No need to actually check if we need a rotation, we definitely don't
                    // if we haven't written the app version time.
                    return (true, needsKnownWorkingWrite, nil)
                }

                let canRotate = APNSRotationStore.canRotateAPNSToken(transaction: transaction)
                if canRotate {
                    return (false, needsKnownWorkingWrite, InteractionFinder.lastInsertedIncomingMessage(transaction: transaction)?.timestamp)
                } else {
                    return (false, needsKnownWorkingWrite, nil)
                }
            }

        if let latestMessageTimestampBeforeProcessing = latestMessageTimestamp {
            // We are eligible to rotate the APNS token. Wait for fetching and processing to finish,
            // and if the latest message changed that means we had new messages to process
            // and therefore missed messages when the app wasn't active.
            try await waitForFetchingAndProcessing()
            let latestMessageTimestamp = SSKEnvironment.shared.databaseStorageRef.read { transaction -> UInt64? in
                return InteractionFinder.lastInsertedIncomingMessage(transaction: transaction)?.timestamp
            }
            if let latestMessageTimestamp, latestMessageTimestamp != latestMessageTimestampBeforeProcessing {
                // Rotate.
                Logger.info("New messages seen on app startup, rotating APNS token.")
                try await performRotation()
            }
        } else if needsAppVersionWrite || needsKnownWorkingWrite {
            await SSKEnvironment.shared.databaseStorageRef.awaitableWrite { transaction in
                if needsAppVersionWrite {
                    APNSRotationStore.setAppVersionTimeForAPNSRotationIfNeeded(transaction: transaction)
                }
                if needsKnownWorkingWrite {
                    APNSRotationStore.kvStore.setUInt64(
                        APNSRotationStore.nowMs(),
                        key: Constants.lastKnownWorkingAPNSTokenTimestampKey,
                        transaction: transaction,
                    )
                }
            }
        }
    }

    public static func canRotateAPNSToken(transaction: DBReadTransaction) -> Bool {
        guard let currentToken = SSKEnvironment.shared.preferencesRef.getPushToken(tx: transaction) else {
            // No need to rotate if we don't even have a token yet.
            Logger.info("No push token available, not rotating.")
            return false
        }
        guard RemoteConfig.current.enableAutoAPNSRotation else {
            Logger.info("Not enabled remotely, not rotating token.")
            return false
        }
        guard isClientEligibleForAPNSTokenRotation(transaction: transaction) else {
            // We gotta give this client time to sit on the app release that added
            // this check before we attempt a rotation.
            Logger.info("Letting client update bake before rotating push token.")
            return false
        }
        guard hasLockoutPeriodElapsed(transaction: transaction) else {
            // We rotated too recently!
            Logger.info("Last push token rotation too recent; not rotating again.")
            return false
        }
        let knownGoodToken = self.kvStore.getString(
            Constants.lastKnownWorkingAPNSTokenKey,
            transaction: transaction,
        )
        let now = nowMs()
        // Default to now; the initial release of this code didn't track
        // this date, so it may be nil even if the known-good token is not.
        let knownGoodTokenTimestamp = self.kvStore.getUInt64(
            Constants.lastKnownWorkingAPNSTokenTimestampKey,
            transaction: transaction,
        ) ?? now
        let isUsingKnownGoodToken = currentToken == knownGoodToken
        if isUsingKnownGoodToken {
            if
                now > knownGoodTokenTimestamp,
                now - knownGoodTokenTimestamp > Constants.lastKnownWorkingAPNSTokenExpirationTimeMs
            {
                // Too long ago, eligible to rotate.
                Logger.warn("APNS token was known-good long ago, rotating.")
                return true
            } else {
                // Our current token is a known working one, don't rotate.
                Logger.info("Has known-good APNS token, skipping rotation.")
                return false
            }
        }
        return true
    }

    /// See comments on `setAppVersionTimeForAPNSRotationIfNeeded`.
    /// This is a read transaction (faster) way to check if we _need_ to write anything before
    /// committing to a write transaction that blocks on a serial queue.
    private static func needsAppVersionWrite(transaction: DBReadTransaction) -> Bool {
        return kvStore.getUInt64(
            Constants.apnsRotationAppVersionUpdateTimestampKey,
            transaction: transaction,
        ) == nil
    }

    /// Consumers of this class should call this when they call `shouldRotateAPNSToken`
    /// (before or after, doesn't matter).
    /// This ensures that after an app version update, we give enough baking time to write state
    /// before attempting a rotation.
    static func setAppVersionTimeForAPNSRotationIfNeeded(transaction: DBWriteTransaction) {
        // Consider this scnario: the user updates their app to the first version which includes
        // this rotation checking code. We check and see that we haven't marked down any incoming
        // APNS pushes in `lastAPNSPushLocalTimestampKey` (we weren't storing that before this code was added!)
        // but we do have missed messages, so the code thinks we should rotate!
        //
        // To avoid this, we give the version update time to bake, marking down when we first
        // attempted a rotation (i.e. the first time we ran an app version with this code present)
        // and not rotating until enough time has passed (or we get an APNS push).
        guard needsAppVersionWrite(transaction: transaction) else {
            return
        }
        kvStore.setUInt64(
            nowMs(),
            key: Constants.apnsRotationAppVersionUpdateTimestampKey,
            transaction: transaction,
        )
    }

    private static func isClientEligibleForAPNSTokenRotation(transaction: DBReadTransaction) -> Bool {
        // Clients will update to a version that runs this code for the first time.
        // There might not be any APNS pushes since updating, but that doesn't mean it didn't
        // run for previous incoming messages; we just weren't storing anything
        // at the time, prior to the update.
        // Make sure its been some time since we first started checking to avoid this.
        let nowMs = self.nowMs()
        guard
            let clientUpdateTime = kvStore.getUInt64(
                Constants.apnsRotationAppVersionUpdateTimestampKey,
                transaction: transaction,
            ),
            // Protect against negative UInt64 values if the clock changes back in time.
            nowMs > clientUpdateTime,
            nowMs - clientUpdateTime >= Constants.appVersionBakeTimeMs
        else {
            return false
        }
        return true
    }

    private static func hasLockoutPeriodElapsed(transaction: DBReadTransaction) -> Bool {
        guard
            let lastRotationTime = kvStore.getUInt64(
                Constants.lastAPNSRotationTimestampKey,
                transaction: transaction,
            )
        else {
            // We haven't rotated before
            return true
        }
        let nowMs = self.nowMs()
        // Protect against negative UInt64 values if the clock changes back in time.
        return nowMs > lastRotationTime && nowMs - lastRotationTime > Constants.minRotationInterval
    }

    enum Constants {
        /// When we get an APNS push, we store the current token under this key
        /// since we know it is working.
        fileprivate static let lastKnownWorkingAPNSTokenKey = "lastKnownWorkingAPNSTokenKey"
        /// We also store the date at which the token last worked,
        /// if it was too long ago we might be eligible to rotate.
        fileprivate static let lastKnownWorkingAPNSTokenTimestampKey = "lastKnownWorkingAPNSTokenTimestampKey"
        static let lastKnownWorkingAPNSTokenExpirationTimeMs: UInt64 = 60 /* days */ * UInt64.dayInMs

        /// See comments on `setAppVersionTimeForAPNSRotationIfNeeded`.
        /// Time we wait after the app first updates to a version with this code before we issue
        /// a token rotation due to missed messages.
        static let appVersionBakeTimeMs: UInt64 = UInt64.weekInMs
        /// See comments on `setAppVersionTimeForAPNSRotationIfNeeded`.
        /// This is the key where we store when we have updated.
        fileprivate static let apnsRotationAppVersionUpdateTimestampKey = "apnsRotationAppVersionUpdateTimestampKey"

        /// Don't ever rotate tokens more often than this.
        static let minRotationInterval: UInt64 = UInt64.weekInMs
        fileprivate static let lastAPNSRotationTimestampKey = "lastAPNSRotationTimestampKey"
    }
}
