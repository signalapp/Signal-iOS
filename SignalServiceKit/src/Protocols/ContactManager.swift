//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import Foundation

public protocol ContactManager: ContactsManagerProtocol {
    /// Get the ``SignalAccount`` backed by the given phone number.
    func fetchSignalAccount(forPhoneNumber phoneNumber: String, transaction: SDSAnyReadTransaction) -> SignalAccount?

    func displayNames(for addresses: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> [String]

    func nameComponents(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> PersonNameComponents?

    func isSystemContact(phoneNumber: String, transaction: SDSAnyReadTransaction) -> Bool

    func comparableName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String

    func systemContactName(for address: SignalServiceAddress, tx: SDSAnyReadTransaction) -> String?

    func leaseCacheSize(_ cacheSize: Int) -> ModelReadCacheSizeLease

    func cnContact(withId cnContactId: String?) -> CNContact?
}

extension ContactManager {
    public func fetchSignalAccount(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        guard let phoneNumber = address.phoneNumber else {
            return nil
        }
        return fetchSignalAccount(forPhoneNumber: phoneNumber, transaction: transaction)
    }

    public func avatarData(for cnContactId: String?) -> Data? {
        // Don't bother to cache avatar data.
        return Contact.avatarData(for: cnContact(withId: cnContactId))
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
