//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import GRDB

/// Improves the performance of `AuthorMergeObserver`.
///
/// We might have messages (and related objects) stored with their address
/// specified as (ACI_A, nil), (ACI_A, E164_A), or (nil, E164_A). In this
/// case, we'd also expect to have an (ACI_A, E164_A) SignalRecipient. At
/// runtime, if we build a SignalServiceAddress for any of these messages,
/// we'll populate the missing ACI/E164 component. If some other ACI claims
/// E164_A in the future, that doesn't let them claim messages sent by the
/// old account. For the messages with ACI_A populated, this will be fine;
/// for the messages with only E164_A populated, they'd move to the new ACI.
///
/// The `AuthorMergeObserver` exists to correct this problem. If we have an
/// (ACI_A, E164_A) SignalRecipient and will change that E164 to nil or some
/// other value, we check the database to ensure all (nil, E164_A) objects
/// are updated to be (ACI_A, ?).
///
/// However, this operation is slow because it requires scanning the entire
/// messages table (and several (likely) smaller tables). Even if we did a
/// slow migration to build indexes, there still could be a large number of
/// messages to update when learning about a change number.
///
/// Enter `AuthorMergeHelper`. This class keeps track of which E164s have
/// ACI-less values in any of the relevant tables, and it will only run the
/// slow migration when absolutely necessary. Fresh installs (and likely
/// those from the past few years) will never need to run a slow migration.
/// The class works by performing a non-blocking migration to preemptively
/// assign ACIs whenever they're known.
///
/// This class also has a further optimization that should avoid the slow
/// migration even when it is "absolutely necessary". If we don't currently
/// know the ACI for a phone number, then we expect to (1) learn it at some
/// point in the future and (2) un-learn it at some further point in the
/// future. When (2) happens, we trigger the slow migration. However, we'd
/// generally expect a significant amount of time between (1) and (2) --
/// it's roughly how long an account has a particular phone number, and it's
/// generally measured in months rather than minutes. Between (1) and (2),
/// we can run our non-blocking migration again, such that by the time we
/// get to (2), the phone number no longer requires a migration.
public class AuthorMergeHelper {
    private let metadataStore: KeyValueStore
    public let nextRowIdStore: KeyValueStore
    private let phoneNumberMissingAciStore: KeyValueStore
    private let phoneNumberJustLearnedAciStore: KeyValueStore

    public init(keyValueStoreFactory: KeyValueStoreFactory) {
        self.metadataStore = keyValueStoreFactory.keyValueStore(collection: "AuthorMergeMetadata")
        self.nextRowIdStore = keyValueStoreFactory.keyValueStore(collection: "AuthorMergeNextRowId")
        self.phoneNumberMissingAciStore = keyValueStoreFactory.keyValueStore(collection: "AuthorMergeMissingAci")
        self.phoneNumberJustLearnedAciStore = keyValueStoreFactory.keyValueStore(collection: "AuthorMergeJustLearnedAci")
    }

    /// If true, then we need to run a slow migration for `phoneNumber`.
    ///
    /// This method may have false positives while the lookup table is being
    /// built or rebuilt. However, note that false positives simply fall back to
    /// the pre-optimization behavior, which is still correct but slower.
    func shouldCleanUp(phoneNumber: String, tx: DBReadTransaction) -> Bool {
        guard currentVersion(tx: tx) >= 1 else {
            // We haven't finished processing yet, so we need to clean up everything.
            // If we've already finished processing once and are checking newly-learned
            // values, we can still trust the existing values since they're a superset.
            return true
        }
        return phoneNumberMissingAciStore.hasValue(phoneNumber, transaction: tx)
    }

    /// We just performed a blocking migration for `phoneNumber`.
    ///
    /// This blocking migration will remove all references to `phoneNumber`, so
    /// we don't need to do a slow migration in the future for `phoneNumber`.
    func didCleanUp(phoneNumber: String, tx: DBWriteTransaction) {
        phoneNumberJustLearnedAciStore.removeValue(forKey: phoneNumber, transaction: tx)
        phoneNumberMissingAciStore.removeValue(forKey: phoneNumber, transaction: tx)
    }

    /// We learned a `phoneNumber` for an ACI; start a background migration.
    func maybeJustLearnedAci(for phoneNumber: String, tx: DBWriteTransaction) {
        // If we don't think we're missing this one, then there's nothing to do. If
        // we're still building the first version of the helper and haven't yet
        // encountered this phone number, then the code here is still correct --
        // we'll simply never add it since we learn it just in time.
        guard phoneNumberMissingAciStore.hasValue(phoneNumber, transaction: tx) else {
            return
        }
        phoneNumberJustLearnedAciStore.setData(Data(), key: phoneNumber, transaction: tx)
        // We increment the next version, thereby invalidating the current version
        // (if it matches) and any in-progress operation (which must be restarted).
        metadataStore.setInt(nextVersion(tx: tx) + 1, key: Constants.nextVersionKey, transaction: tx)
        // We also clear `nextRowIdStore` so that we start at the beginning of each
        // table on the next attempt.
        nextRowIdStore.removeAll(transaction: tx)
    }

    /// We found a `phoneNumber` without an ACI, so add it to the lookup table.
    public func foundMissingAci(for phoneNumber: String, tx: DBWriteTransaction) {
        phoneNumberMissingAciStore.setData(Data(), key: phoneNumber, transaction: tx)
    }

    private enum Constants {
        static let currentVersionKey = "current"
        static let nextVersionKey = "next"
    }

    public enum VersionError: Error {
        case nextVersionChanged
    }

    /// The current version of the lookup table.
    ///
    /// - If zero, we haven't finished building the table yet, so while there
    /// may be values, they can't be trusted for skipping blocking migrations.
    ///
    /// - If one or higher, we've built at least one version of the table, so
    /// the phone numbers can be trusted for skipping blocking migrations. If
    /// `nextVersion > currentVersion`, then there might be some phone numbers
    /// we're in the process of cleaning up in a background migration.
    public func currentVersion(tx: DBReadTransaction) -> Int {
        return metadataStore.getInt(Constants.currentVersionKey, defaultValue: 0, transaction: tx)
    }

    /// Marks that we just finished a particular version of the table.
    public func setCurrentVersion(nextVersion: Int, tx: DBWriteTransaction) throws {
        try checkNextVersion(nextVersion, tx: tx)
        metadataStore.setInt(nextVersion, key: Constants.currentVersionKey, transaction: tx)
        phoneNumberMissingAciStore.removeValues(forKeys: phoneNumberJustLearnedAciStore.allKeys(transaction: tx), transaction: tx)
    }

    public func nextVersion(tx: DBReadTransaction) -> Int {
        return metadataStore.getInt(Constants.nextVersionKey, defaultValue: 1, transaction: tx)
    }

    public func checkNextVersion(_ nextVersion: Int, tx: DBReadTransaction) throws {
        guard nextVersion == self.nextVersion(tx: tx) else {
            throw VersionError.nextVersionChanged
        }
    }
}
