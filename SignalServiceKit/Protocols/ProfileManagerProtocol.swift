//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol ProfileManagerProtocol {
    var badgeStore: BadgeStore { get }

    /// Fetch the profile for the local user. (It should always exist.)
    func localUserProfile(tx: DBReadTransaction) -> OWSUserProfile?

    /// Fetch the locally-cached profile for an address.
    func userProfile(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSUserProfile?

    func isUser(inProfileWhitelist address: SignalServiceAddress, transaction: DBReadTransaction) -> Bool
    func normalizeRecipientInProfileWhitelist(_ recipient: SignalRecipient, tx: DBWriteTransaction)
    func isThread(inProfileWhitelist thread: TSThread, transaction: DBReadTransaction) -> Bool
    func addThread(toProfileWhitelist thread: TSThread, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction)
    func addUser(toProfileWhitelist address: SignalServiceAddress, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction)
    func addUsers(toProfileWhitelist addresses: [SignalServiceAddress], userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction)
    func removeUser(fromProfileWhitelist address: SignalServiceAddress)
    func removeUser(fromProfileWhitelist address: SignalServiceAddress, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction)
    func isGroupId(inProfileWhitelist groupId: Data, transaction: DBReadTransaction) -> Bool
    func addGroupId(toProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction)
    func removeGroupId(fromProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction)

    /// Rotates the local profile key. Intended specifically for the use case of recipient hiding.
    ///
    /// - parameter tx: the transaction to use for this operation
    func rotateProfileKeyUponRecipientHide(withTx tx: DBWriteTransaction)

    /// Rotating the profile key is expensive, and should be done as infrequently as possible.
    /// You probably want `rotateLocalProfileKeyIfNecessary` which checks for whether
    /// a rotation is necessary given whitelist/blocklist and other conditions.
    /// This method exists solely for when we leave a group that had a blocked user in it; when we call
    /// this we already determined we need a rotation based on _group+blocked_ state and will
    /// force a rotation independently of whitelist state.
    func forceRotateLocalProfileKeyForGroupDeparture(with transaction: DBWriteTransaction)
}
