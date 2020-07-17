//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
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
            profileUpdateMessage.anyInsert(transaction: transaction)
        }

        let contactThread = TSContactThread.getOrCreateThread(withContactAddress: address, transaction: transaction)
        saveProfileUpdateMessage(thread: contactThread)

        for groupThread in TSGroupThread.groupThreads(with: address, transaction: transaction) {
            saveProfileUpdateMessage(thread: groupThread)
        }
    }
}

@objcMembers
public class ProfileChanges: MTLModel {
    var address: SignalServiceAddress?

    var oldNameComponents: PersonNameComponents?
    var newNameComponents: PersonNameComponents?

    var hasRenderableChanges: Bool {
        return oldNameComponents != nil && newNameComponents != nil && oldNameComponents != newNameComponents
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

    var contactsManager: ContactsManagerProtocol {
        return SSKEnvironment.shared.contactsManager
    }

    func descriptionForUpdate(transaction: SDSAnyReadTransaction) -> String? {
        guard let address = address else {
            owsFailDebug("Unexpectedly missing address for profile change")
            return nil
        }

        guard let oldNameComponents = oldNameComponents, let newNameComponents = newNameComponents else {
            owsFailDebug("Unexpectedly missing name change for profile change")
            return nil
        }

        let oldFullName = PersonNameComponentsFormatter.localizedString(
            from: oldNameComponents,
            style: .default,
            options: []
        )
        let newFullName = PersonNameComponentsFormatter.localizedString(
            from: newNameComponents,
            style: .default,
            options: []
        )

        if contactsManager.hasNameInSystemContacts(for: address) {
            let displayName = contactsManager.displayName(for: address, transaction: transaction)

            let formatString = NSLocalizedString(
                "PROFILE_NAME_CHANGE_SYSTEM_CONTACT_FORMAT",
                comment: "The copy rendered in a conversation when someone in your address book changes their profile name. Embeds {contact name}, {old profile name}, {new profile name}"
            )
            return String(format: formatString, displayName, oldFullName, newFullName)
        } else {
            let formatString = NSLocalizedString(
                "PROFILE_NAME_CHANGE_SYSTEM_NONCONTACT_FORMAT",
                comment: "The copy rendered in a conversation when someone not in your address book changes their profile name. Embeds {old profile name}, {new profile name}"
            )
            return String(format: formatString, oldFullName, newFullName)
        }
    }
}
