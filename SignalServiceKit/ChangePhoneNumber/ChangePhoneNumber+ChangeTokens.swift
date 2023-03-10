//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

// MARK: - ChangeToken

extension ChangePhoneNumber {
    public struct ChangeToken {
        fileprivate let legacyChangeIds: [String]

        let pniPendingState: ChangePhoneNumberPni.PendingState?

        fileprivate init(
            legacyChangeIds: [String],
            pniPendingState: ChangePhoneNumberPni.PendingState?
        ) {
            self.legacyChangeIds = legacyChangeIds
            self.pniPendingState = pniPendingState
        }

        init(legacyChangeId: String) {
            self.init(
                legacyChangeIds: [legacyChangeId],
                pniPendingState: nil
            )
        }

        init(pniPendingState: ChangePhoneNumberPni.PendingState) {
            self.init(
                legacyChangeIds: [],
                pniPendingState: pniPendingState
            )
        }
    }
}

// MARK: - ChangeTokenStore

extension ChangePhoneNumber {
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

            guard legacyChangeIds.isEmpty else {
                // Legacy change IDs take precedence, as we want to clear them
                // before starting to use new change token formats.

                return ChangeToken(
                    legacyChangeIds: legacyChangeIds,
                    pniPendingState: nil
                )
            }

            do {
                if let pniPendingState: PendingState = try keyValueStore.getCodableValue(
                    forKey: ChangeTokenKeys.changeTokenPniPendingState,
                    transaction: transaction
                ) {
                    return ChangeToken(
                        legacyChangeIds: [],
                        pniPendingState: pniPendingState
                    )
                }
            } catch let error {
                owsFailDebug("Error fetching persisted pending state: \(error)!")
            }

            return nil
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
            if let pniPendingState = changeToken.pniPendingState {
                // If we have PNI state, store it in using a special key.

                try keyValueStore.setCodable(
                    pniPendingState,
                    key: ChangeTokenKeys.changeTokenPniPendingState,
                    transaction: transaction
                )
            } else {
                // If we have a legacy change token, store the legacy IDs.

                for legacyChangeId in changeToken.legacyChangeIds {
                    keyValueStore.setString(
                        legacyChangeId,
                        key: legacyChangeId,
                        transaction: transaction
                    )
                }
            }
        }

        /// Clear the given change token, thereby marking it complete.
        func clear(
            changeToken: ChangeToken,
            transaction: SDSAnyWriteTransaction
        ) {
            if changeToken.pniPendingState != nil {
                keyValueStore.removeValue(
                    forKey: ChangeTokenKeys.changeTokenPniPendingState,
                    transaction: transaction
                )
            } else {
                for legacyChangeId in changeToken.legacyChangeIds {
                    keyValueStore.removeValue(
                        forKey: legacyChangeId,
                        transaction: transaction
                    )
                }
            }
        }
    }
}
