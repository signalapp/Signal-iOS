//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol ProfileManagerProtocol {
    /// Fetch the profile for the local user. (It should always exist.)
    func localUserProfile(tx: DBReadTransaction) -> OWSUserProfile?

    /// Fetch the locally-cached profile for an address.
    func userProfile(for address: SignalServiceAddress, tx: DBReadTransaction) -> OWSUserProfile?

    func addRecipientToProfileWhitelist(_ recipient: inout SignalRecipient, userProfileWriter: UserProfileWriter, tx: DBWriteTransaction)
    func removeRecipientFromProfileWhitelist(_ recipient: inout SignalRecipient, userProfileWriter: UserProfileWriter, tx: DBWriteTransaction) -> Bool
    func isRecipientInProfileWhitelist(_ recipient: SignalRecipient, tx: DBReadTransaction) -> Bool

    func isGroupId(inProfileWhitelist groupId: Data, transaction: DBReadTransaction) -> Bool
    func addGroupId(toProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction)
    func removeGroupId(fromProfileWhitelist groupId: Data, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction) -> Bool

    func setLocalProfileKey(_ key: Aes256Key, userProfileWriter: UserProfileWriter, transaction: DBWriteTransaction)

    func setNeedsProfileKeyRotation(tx: DBWriteTransaction)
}

extension ProfileManagerProtocol {
    public func isUser(inProfileWhitelist address: SignalServiceAddress, transaction: DBReadTransaction) -> Bool {
        owsAssertDebug(address.isValid)
        let recipientStore = DependenciesBridge.shared.recipientDatabaseTable
        guard let recipient = recipientStore.fetchRecipient(address: address, tx: transaction) else {
            return false
        }
        return isRecipientInProfileWhitelist(recipient, tx: transaction)
    }

    public func isThread(inProfileWhitelist thread: TSThread, transaction: DBReadTransaction) -> Bool {
        if thread.isGroupThread, let groupThread = thread as? TSGroupThread {
            return isGroupId(inProfileWhitelist: groupThread.groupModel.groupId, transaction: transaction)
        } else if !thread.isGroupThread, let contactThread = thread as? TSContactThread {
            return isUser(inProfileWhitelist: contactThread.contactAddress, transaction: transaction)
        } else {
            return false
        }
    }
}
