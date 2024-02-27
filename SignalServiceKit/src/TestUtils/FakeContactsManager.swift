//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts

#if TESTABLE_BUILD

@objc(OWSFakeContactsManager)
public class FakeContactsManager: NSObject, ContactManager {
    public var mockSignalAccounts = [String: SignalAccount]()

    public func fetchSignalAccount(forPhoneNumber phoneNumber: String, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        return mockSignalAccounts[phoneNumber]
    }

    public func displayName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        return systemContactName(for: address, tx: transaction) ?? "John Doe"
    }

    public func displayNames(for addresses: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> [String] {
        return addresses.map { displayName(for: $0, transaction: transaction) }
    }

    public func shortDisplayName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        return displayName(for: address, transaction: transaction)
    }

    public func nameComponents(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> PersonNameComponents? {
        let nameComponents = displayName(for: address, transaction: transaction).split(separator: " ")
        var result = PersonNameComponents()
        result.givenName = nameComponents.first.map(String.init(_:))
        result.familyName = nameComponents.dropFirst().first.map(String.init(_:))
        return result
    }

    public var systemContactPhoneNumbers: [String] = []

    public func isSystemContact(phoneNumber: String, transaction: SDSAnyReadTransaction) -> Bool {
        return systemContactPhoneNumbers.contains(phoneNumber)
    }

    public func sortSignalServiceAddressesObjC(_ addresses: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        return addresses
    }

    public func comparableName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        return displayName(for: address, transaction: transaction)
    }

    public func systemContactName(for address: SignalServiceAddress, tx transaction: SDSAnyReadTransaction) -> String? {
        return fetchSignalAccount(for: address, transaction: transaction)?.contact?.fullName
    }

    public func leaseCacheSize(_ cacheSize: Int) -> ModelReadCacheSizeLease {
        fatalError()
    }

    public func cnContact(withId contactId: String?) -> CNContact? {
        return nil
    }
}

#endif
