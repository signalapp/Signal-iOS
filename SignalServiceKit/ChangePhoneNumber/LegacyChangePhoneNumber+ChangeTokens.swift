//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - ChangeToken

extension LegacyChangePhoneNumber {
    public struct ChangeToken {
        fileprivate let legacyChangeIds: [String]

        init(
            legacyChangeIds: [String]
        ) {
            self.legacyChangeIds = legacyChangeIds
        }

        init(legacyChangeId: String) {
            self.init(
                legacyChangeIds: [legacyChangeId]
            )
        }
    }
}

// MARK: - ChangeTokenStore

extension LegacyChangePhoneNumber {
    /// Convenience type managing persistence of ``ChangeToken``s.
    ///
    /// For historical backwards-compatibility, we maintain ``ChangeToken``
    /// state in a couple different places. This type is intended to abstract
    /// that away.
    struct IncompleteChangeTokenStore {
        private typealias PendingState = ChangePhoneNumberPni.PendingState

        /// Keys for storing ChangeToken-related values.
        ///
        /// If adding keys, please ensure they are considered when calculating
        /// legacy change IDs below.
        private enum ChangeTokenKeys {
            static let changeTokenPniPendingState = "ChangeNumberPniPendingState"
        }

        private let keyValueStore = SDSKeyValueStore(
            collection: "ChangePhoneNumber.incompleteChanges"
        )

        func existingToken(
            transaction: SDSAnyReadTransaction
        ) -> ChangeToken? {
            let legacyChangeIds = allLegacyChangeIds(transaction: transaction)

            if legacyChangeIds.isEmpty {
                return nil
            }

            return ChangeToken(
                legacyChangeIds: legacyChangeIds
            )
        }

        /// We used to store string "change IDs", each of which represented an
        /// interrupted attempt to change number. This method fetches all such
        /// legacy change IDs.
        private func allLegacyChangeIds(
            transaction: SDSAnyReadTransaction
        ) -> [String] {
            let legacyChangeIds = Set(keyValueStore.allKeys(
                transaction: transaction
            )).subtracting([
                ChangeTokenKeys.changeTokenPniPendingState
            ])

            return Array(legacyChangeIds)
        }

        /// Save the given incomplete change token.
        func save(
            changeToken: ChangeToken,
            transaction: SDSAnyWriteTransaction
        ) throws {
            for legacyChangeId in changeToken.legacyChangeIds {
                keyValueStore.setString(
                    legacyChangeId,
                    key: legacyChangeId,
                    transaction: transaction
                )
            }
        }

        /// Clear the given change token, thereby marking it complete.
        func clear(
            changeToken: ChangeToken,
            transaction: SDSAnyWriteTransaction
        ) {
            for legacyChangeId in changeToken.legacyChangeIds {
                keyValueStore.removeValue(
                    forKey: legacyChangeId,
                    transaction: transaction
                )
            }
        }
    }
}
