//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

extension MessageBackup {

    enum Timestamps {
        private static let maxTimestampValue: UInt64 = 8640000000000000

        static func isValid(_ timestamp: UInt64?) -> Bool {
            // The max limit is imposed by desktop and is lower than
            // the limit the iOS client requires, but we should keep
            // checking that this doesn't change and our own limit
            // (<= Int64.max) is enforced.
            owsPrecondition(maxTimestampValue <= Int64.max)
            guard let timestamp else { return true }
            return timestamp <= maxTimestampValue
        }

        /// We validate timestamps on _export_ of a backup and drop frames that would have
        /// invalid timestamps. This is because invalid timestamps are rejected by the validator
        /// and are never cases of valid, legitimate data that we shouldn't drop.
        static func validateTimestamp(_ timestamp: UInt64?) -> MessageBackup.ArchiveInteractionResult<Void> {
            guard isValid(timestamp) else {
                return .skippableChatUpdate(.timestampTooLarge)
            }
            return .success(())
        }

        static func setTimestampIfValid<Source, Proto>(
            from source: Source,
            _ sourceKeyPath: KeyPath<Source, UInt64>,
            on proto: inout Proto,
            _ protoKeyPath: WritableKeyPath<Proto, UInt64>,
            allowZero: Bool
        ) {
            let timestamp = source[keyPath: sourceKeyPath]
            guard isValid(timestamp) else {
                return
            }
            if !allowZero, timestamp == 0 {
                return
            }
            proto[keyPath: protoKeyPath] = timestamp
        }

        static func setTimestampIfValid<Source, Proto>(
            from source: Source,
            _ sourceKeyPath: KeyPath<Source, UInt64?>,
            on proto: inout Proto,
            _ protoKeyPath: WritableKeyPath<Proto, UInt64>,
            allowZero: Bool
        ) {
            let timestamp = source[keyPath: sourceKeyPath]
            guard let timestamp, isValid(timestamp) else {
                return
            }
            if !allowZero, timestamp == 0 {
                return
            }
            proto[keyPath: protoKeyPath] = timestamp
        }
    }
}
