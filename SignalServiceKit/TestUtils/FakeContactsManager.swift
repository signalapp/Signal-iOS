//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts

#if TESTABLE_BUILD

@objc(OWSFakeContactsManager)
public class FakeContactsManager: NSObject, ContactManager {
    public var mockSignalAccounts = [String: SignalAccount]()

    public func fetchSignalAccounts(for phoneNumbers: [String], transaction: SDSAnyReadTransaction) -> [SignalAccount?] {
        return phoneNumbers.map { mockSignalAccounts[$0] }
    }

    public func displayNames(for addresses: [SignalServiceAddress], tx: SDSAnyReadTransaction) -> [DisplayName] {
        return addresses.map { address in
            if let phoneNumber = address.e164 {
                if let contact = mockSignalAccounts[phoneNumber.stringValue]?.contact {
                    var nameComponents = PersonNameComponents()
                    nameComponents.givenName = contact.firstName
                    nameComponents.familyName = contact.lastName
                    return .systemContactName(DisplayName.SystemContactName(
                        nameComponents: nameComponents,
                        multipleAccountLabel: nil
                    ))
                }
                return .phoneNumber(phoneNumber)
            }
            return .unknown
        }
    }

    public func displayNameString(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        return displayName(for: address, tx: transaction).resolvedValue(config: DisplayName.Config(shouldUseNicknames: false))
    }

    public func shortDisplayNameString(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        return displayNameString(for: address, transaction: transaction)
    }

    public var systemContactPhoneNumbers: [String] = []

    public func isSystemContact(phoneNumber: String, transaction: SDSAnyReadTransaction) -> Bool {
        return systemContactPhoneNumbers.contains(phoneNumber)
    }

    public func sortSignalServiceAddressesObjC(_ addresses: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        return addresses
    }

    public func leaseCacheSize(_ cacheSize: Int) -> ModelReadCacheSizeLease {
        fatalError()
    }

    public func cnContact(withId contactId: String?) -> CNContact? {
        return nil
    }
}

#endif
