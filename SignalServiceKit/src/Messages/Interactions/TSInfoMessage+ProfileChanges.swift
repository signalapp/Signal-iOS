//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension TSInfoMessage {
    @objc
    class func insertProfileChangeMessagesIfNecessary(
        oldProfile: OWSUserProfile,
        newProfile: OWSUserProfile,
        transaction: SDSAnyWriteTransaction
    ) {
        let profileChanges = ProfileChanges(oldProfile: oldProfile, newProfile: newProfile)

        guard profileChanges.hasRenderableChanges, let address = profileChanges.address else { return }

        func saveProfileUpdateMessage(thread: TSThread) {
            let profileUpdateMessage = TSInfoMessage(
                thread: thread,
                messageType: .profileUpdate,
                infoMessageUserInfo: [.profileChanges: profileChanges]
            )
            profileUpdateMessage.wasRead = true
            profileUpdateMessage.anyInsert(transaction: transaction)
        }

        let contactThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction)
        if contactThread.shouldThreadBeVisible {
            saveProfileUpdateMessage(thread: contactThread)
        }

        for groupThread in TSGroupThread.groupThreads(with: address, transaction: transaction) {
            guard groupThread.groupModel.groupMembership.isLocalUserFullMember && groupThread.shouldThreadBeVisible else { continue }
            saveProfileUpdateMessage(thread: groupThread)
        }
    }
}

@objcMembers
public class ProfileChanges: MTLModel {
    var address: SignalServiceAddress?

    var oldNameComponents: PersonNameComponents?
    var newNameComponents: PersonNameComponents?

    var oldFullName: String? {
        guard let oldNameComponents = oldNameComponents else { return nil }
        return OWSFormat.formatNameComponents(oldNameComponents).filterStringForDisplay()
    }

    var newFullName: String? {
        guard let newNameComponents = newNameComponents else { return nil }
        return OWSFormat.formatNameComponents(newNameComponents).filterStringForDisplay()
    }

    var hasRenderableChanges: Bool {
        return oldFullName != nil && newFullName != nil && oldFullName != newFullName
    }

    init(oldProfile: OWSUserProfile, newProfile: OWSUserProfile) {
        address = newProfile.address

        oldNameComponents = oldProfile.nameComponents
        newNameComponents = newProfile.nameComponents

        // TODO: Eventually, we'll want to track profile
        // photo and username changes here too.

        super.init()
    }

    public override init!() {
        super.init()
    }

    required init!(coder: NSCoder!) {
        super.init(coder: coder)
    }

    required init(dictionary dictionaryValue: [String: Any]!) throws {
        try super.init(dictionary: dictionaryValue)
    }

    func descriptionForUpdate(transaction: SDSAnyReadTransaction) -> String? {
        guard let address = address else {
            owsFailDebug("Unexpectedly missing address for profile change")
            return nil
        }

        guard let oldFullName = oldFullName, let newFullName = newFullName else {
            owsFailDebug("Unexpectedly missing old and new full name")
            return nil
        }

        if contactsManager.hasNameInSystemContacts(for: address, transaction: transaction) {
            let displayName = contactsManager.displayName(for: address, transaction: transaction)

            let formatString = OWSLocalizedString(
                "PROFILE_NAME_CHANGE_SYSTEM_CONTACT_FORMAT",
                comment: "The copy rendered in a conversation when someone in your address book changes their profile name. Embeds {contact name}, {old profile name}, {new profile name}"
            )
            return String(format: formatString, displayName, oldFullName, newFullName)
        } else {
            let formatString = OWSLocalizedString(
                "PROFILE_NAME_CHANGE_SYSTEM_NONCONTACT_FORMAT",
                comment: "The copy rendered in a conversation when someone not in your address book changes their profile name. Embeds {old profile name}, {new profile name}"
            )
            return String(format: formatString, oldFullName, newFullName)
        }
    }
}
