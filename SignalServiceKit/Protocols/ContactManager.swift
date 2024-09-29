//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts
import Foundation

public protocol ContactManager: ContactsManagerProtocol {
    func fetchSignalAccounts(for phoneNumbers: [String], transaction: SDSAnyReadTransaction) -> [SignalAccount?]

    func displayNames(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [DisplayName]

    func cnContactId(for phoneNumber: String) -> String?

    func cnContact(withId cnContactId: String?) -> CNContact?
}

extension ContactManager {
    public func fetchSignalAccount(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        guard let phoneNumber = address.phoneNumber else {
            return nil
        }
        return fetchSignalAccount(forPhoneNumber: phoneNumber, transaction: transaction)
    }

    public func fetchSignalAccount(forPhoneNumber phoneNumber: String, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        return fetchSignalAccounts(for: [phoneNumber], transaction: transaction)[0]
    }

    public func systemContactName(for phoneNumber: String, tx transaction: SDSAnyReadTransaction) -> DisplayName.SystemContactName? {
        return systemContactNames(for: [phoneNumber], tx: transaction)[0]
    }

    public func systemContactNames(for phoneNumbers: [String], tx: SDSAnyReadTransaction) -> [DisplayName.SystemContactName?] {
        return fetchSignalAccounts(for: phoneNumbers, transaction: tx).map {
            guard let nameComponents = $0?.contactNameComponents() else {
                return nil
            }
            return DisplayName.SystemContactName(
                nameComponents: nameComponents,
                multipleAccountLabel: $0?.multipleAccountLabelText
            )
        }
    }

    public func displayName(for address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> DisplayName {
        return displayNames(for: [address], tx: tx)[0]
    }

    public func avatarData(for cnContactId: String?) -> Data? {
        // Don't bother to cache avatar data.
        guard let cnContact = self.cnContact(withId: cnContactId) else {
            return nil
        }
        return avatarData(for: cnContact)
    }

    public func avatarData(for cnContact: CNContact) -> Data? {
        return SystemContact.avatarData(for: cnContact)
    }

    public func avatarImage(for cnContactId: String?) -> UIImage? {
        guard let avatarData = self.avatarData(for: cnContactId) else {
            return nil
        }
        guard avatarData.ows_isValidImage else {
            Logger.warn("Invalid image.")
            return nil
        }
        guard let avatarImage = UIImage(data: avatarData) else {
            Logger.warn("Couldn't load image.")
            return nil
        }
        return avatarImage
    }
}
