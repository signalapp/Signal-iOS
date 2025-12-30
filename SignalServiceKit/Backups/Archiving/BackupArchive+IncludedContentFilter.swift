//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

extension BackupArchive {

    struct IncludedContentFilter {
        /// The minimum absolute expiration time for a message, such that it
        /// is eligible for inclusion.
        ///
        /// For example, a value of 24h will exclude messages with a
        /// "lifetime" of a day or less, regardless of whether they have
        /// been read and their expiration timer has started.
        private let minExpirationTimeMs: UInt64

        /// The minimum remaining time before a message will expire, such
        /// that it is eligible for inclusion.
        ///
        /// For example, a value of 24h will exclude messages that will
        /// expire in the next day, regardless of how long their original
        /// "lifetime" was.
        private let minRemainingTimeUntilExpirationMs: UInt64

        /// Unviewed view-once messages should be treated as viewed and
        /// tombstoned for this export.
        let shouldTombstoneViewOnce: Bool

        /// Whether or not the plaintext SVR PIN should be included.
        let shouldIncludePin: Bool

        init(backupPurpose: MessageBackupPurpose) {
            self.minExpirationTimeMs = {
                switch backupPurpose {
                case .deviceTransfer:
                    // Don't exclude any messages in "device transfer" backups,
                    // i.e. Link'n'Syncs.
                    return 0
                case .remoteBackup:
                    // Skip messages with timers of less than a day.
                    return .dayInMs
                }
            }()
            self.minRemainingTimeUntilExpirationMs = {
                switch backupPurpose {
                case .deviceTransfer:
                    // Don't exclude any messages in "device transfer" backups,
                    // i.e. Link'n'Syncs.
                    return 0
                case .remoteBackup:
                    // Skip messages with less than a day before they'll expire.
                    return .dayInMs
                }
            }()
            self.shouldTombstoneViewOnce = {
                switch backupPurpose {
                case .deviceTransfer:
                    return false
                case .remoteBackup:
                    return true
                }
            }()
            self.shouldIncludePin = true
        }

        func shouldSkipMessageBasedOnExpiration(
            expireStartDate: UInt64?,
            expiresInMs: UInt64?,
            currentTimestamp: UInt64,
        ) -> Bool {
            guard
                let expiresInMs,
                expiresInMs > 0
            else {
                // If the message isn't expiring, no reason to skip.
                return false
            }

            if expiresInMs <= self.minExpirationTimeMs {
                // If the expire timer was less than our minimum, we can always
                // skip.
                return true
            } else if let expireStartDate, expireStartDate > 0 {
                // If the expiration timer has started, check whether the
                // remaining time before it expires is sufficient.
                let expirationDate = expireStartDate + expiresInMs
                let minExpirationDate = currentTimestamp + self.minRemainingTimeUntilExpirationMs

                return expirationDate <= minExpirationDate
            } else {
                return false
            }
        }

        /// If this returns true, we will skip scheduling a media tier upload for the
        /// attachment with respect to this owning messager. If the attachment has
        /// other owners (e.g. if deduplicated by content hash), it may still be uploaded.
        func shouldSkipAttachment(
            owningMessage: TSMessage,
            currentTimestamp: UInt64,
        ) -> Bool {
            if
                shouldSkipMessageBasedOnExpiration(
                    expireStartDate: owningMessage.expireStartedAt,
                    expiresInMs: UInt64(owningMessage.expiresInSeconds) * 1000,
                    currentTimestamp: currentTimestamp,
                )
            {
                return true
            }
            if
                owningMessage.isViewOnceMessage,
                shouldTombstoneViewOnce
            {
                return true
            }
            return false
        }
    }
}
