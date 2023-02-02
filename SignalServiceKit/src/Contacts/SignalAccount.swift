//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

extension SignalAccount {
    @objc
    public func buildContactAvatarJpegData() -> Data? {
        guard let contact = self.contact else {
            return nil
        }
        guard contact.isFromLocalAddressBook else {
            return nil
        }
        guard let cnContactId: String = contact.cnContactId else {
            owsFailDebug("Missing cnContactId.")
            return nil
        }
        guard let contactAvatarData = Self.contactsManager.avatarData(forCNContactId: cnContactId) else {
            return nil
        }
        guard let contactAvatarJpegData = UIImage.validJpegData(fromAvatarData: contactAvatarData) else { owsFailDebug("Could not convert avatar to JPEG.")
            return nil
        }
        return contactAvatarJpegData
    }

    @objc
    public var addressComponentsDescription: String {
        SignalServiceAddress.addressComponentsDescription(uuidString: recipientUUID,
                                                          phoneNumber: recipientPhoneNumber)
    }

    public func hasSameContent(_ otherAccount: SignalAccount) -> Bool {
        // NOTE: We don't want to compare contactAvatarJpegData. It can't change
        // without contactAvatarHash changing as well.
        recipientPhoneNumber == otherAccount.recipientPhoneNumber
        && recipientUUID == otherAccount.recipientUUID
        && multipleAccountLabelText == otherAccount.multipleAccountLabelText
        && contactAvatarHash == otherAccount.contactAvatarHash
        && contactHasSameContent(otherAccount.contact)
    }

    private func contactHasSameContent(_ otherContact: Contact?) -> Bool {
        if let contact, let otherContact {
            return contact.hasSameContent(otherContact)
        } else {
            return contact == nil && otherContact == nil
        }
    }
}
