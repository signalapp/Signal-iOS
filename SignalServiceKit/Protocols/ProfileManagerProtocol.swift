//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol ProfileManagerProtocol: NSObjectProtocol {

    /// - returns: true if there is a local profile with a name or avatar.
    var hasLocalProfile: Bool { get }
    var hasProfileName: Bool { get }
    var badgeStore: BadgeStore { get }
    var localProfileKey: Aes256Key { get }
    var localGivenName: String? { get }
    var localFamilyName: String? { get }
    var localFullName: String? { get }
    var localProfileAvatarImage: UIImage? { get }
    var localProfileAvatarData: Data? { get }
    var localProfileBadgeInfo: [OWSUserProfileBadgeInfo]? { get }

    /// - returns: true if there is _ANY_ local profile.
    func localProfileExists(with transaction: SDSAnyReadTransaction) -> Bool
    func fullName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String?
    func getUserProfile(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> OWSUserProfile?
    func profileKeyData(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Data?
    func profileKey(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Aes256Key?
    func hasProfileAvatarData(_ address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool
    func profileAvatarData(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Data?
    func profileAvatarURLPath(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String?
    func isUser(inProfileWhitelist address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool
    func normalizeRecipientInProfileWhitelist(_ recipient: SignalRecipient, tx: SDSAnyWriteTransaction)
    func isThread(inProfileWhitelist thread: TSThread, transaction: SDSAnyReadTransaction) -> Bool
    func addThread(toProfileWhitelist thread: TSThread, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction)
    func addUser(toProfileWhitelist address: SignalServiceAddress, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction)
    func addUsers(toProfileWhitelist addresses: [SignalServiceAddress], userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction)
    func removeUser(fromProfileWhitelist address: SignalServiceAddress)
    func removeUser(fromProfileWhitelist address: SignalServiceAddress, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction)
    func isGroupId(inProfileWhitelist groupId: Data, transaction: SDSAnyReadTransaction) -> Bool
    func addGroupId(toProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction)
    func removeGroupId(fromProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: SDSAnyWriteTransaction)
    func warmCaches()

    /// This is an internal implementation detail and should only be used by OWSUserProfile.
    func localProfileWasUpdated(_ localUserProfile: OWSUserProfile)

    /// Rotates the local profile key. Intended specifically for the use case of recipient hiding.
    ///
    /// - parameter tx: the transaction to use for this operation
    func rotateProfileKeyUponRecipientHide(withTx tx: SDSAnyWriteTransaction)

    /// Rotating the profile key is expensive, and should be done as infrequently as possible.
    /// You probably want `rotateLocalProfileKeyIfNecessary` which checks for whether
    /// a rotation is necessary given whitelist/blocklist and other conditions.
    /// This method exists solely for when we leave a group that had a blocked user in it; when we call
    /// this we already determined we need a rotation based on _group+blocked_ state and will
    /// force a rotation independently of whitelist state.
    func forceRotateLocalProfileKeyForGroupDeparture(with transaction: SDSAnyWriteTransaction)
}
