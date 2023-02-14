//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts

@objc(OWSFakeContactsManager)
public class FakeContactsManager: NSObject, ContactsManagerProtocol {
    public func fetchSignalAccount(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> SignalAccount? {
        return nil
    }

    public func displayName(for address: SignalServiceAddress) -> String {
        return "Fake name"
    }

    public func displayNames(forAddresses addresses: [SignalServiceAddress], transaction: SDSAnyReadTransaction) -> [String] {
        return Array(repeating: "Fake name", count: addresses.count)
    }

    public func displayName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        return self.displayName(for: address)
    }

    public func displayName(for signalAccount: SignalAccount) -> String {
        return "Fake name"
    }

    public func displayName(for thread: TSThread, transaction: SDSAnyReadTransaction) -> String {
        return "Fake name"
    }

    public func shortDisplayName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        return "Short fake name"
    }

    public func nameComponents(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> PersonNameComponents? {
        return PersonNameComponents()
    }

    public func displayNameWithSneakyTransaction(thread: TSThread) -> String {
        return "Fake name"
    }

    public func signalAccounts() -> [SignalAccount] {
        return []
    }

    public var systemContacts: [SignalServiceAddress] = []

    public func isSystemContactWithSneakyTransaction(phoneNumber: String) -> Bool {
        return systemContacts.contains { $0.phoneNumber == phoneNumber }
    }

    public func isSystemContact(phoneNumber: String, transaction: SDSAnyReadTransaction) -> Bool {
        return isSystemContactWithSneakyTransaction(phoneNumber: phoneNumber)
    }

    public func isSystemContactWithSneakyTransaction(address: SignalServiceAddress) -> Bool {
        return systemContacts.contains(address)
    }

    public func isSystemContact(address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        return isSystemContactWithSneakyTransaction(address: address)
    }

    public func isSystemContact(withSignalAccount phoneNumber: String) -> Bool {
        return isSystemContactWithSneakyTransaction(phoneNumber: phoneNumber)
    }

    public func isSystemContact(withSignalAccount phoneNumber: String, transaction: SDSAnyReadTransaction) -> Bool {
        return isSystemContact(withSignalAccount: phoneNumber)
    }

    public func hasNameInSystemContacts(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        return true
    }

    public func isSystemContactWithSignalAccount(_ address: SignalServiceAddress) -> Bool {
        return isSystemContactWithSneakyTransaction(address: address)
    }

    public func isSystemContactWithSignalAccount(_ address: SignalServiceAddress,
                                                 transaction: SDSAnyReadTransaction) -> Bool {
        return isSystemContactWithSignalAccount(address)
    }

    public func sortSignalServiceAddresses(_ addresses: [SignalServiceAddress],
                                           transaction: SDSAnyReadTransaction) -> [SignalServiceAddress] {
        return addresses
    }

    public func compare(signalAccount left: SignalAccount, with right: SignalAccount) -> ComparisonResult {
        // If this method ends up being used by the tests, we should provide a better implementation.
        owsFail("TODO")
    }

    public func comparableName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        return "Fake name"
    }

    public func comparableName(for signalAccount: SignalAccount, transaction: SDSAnyReadTransaction) -> String {
        return "Fake name"
    }

    public func cnContact(withId contactId: String?) -> CNContact? {
        return nil
    }

    public func avatarData(forCNContactId contactId: String?) -> Data? {
        return nil
    }

    public func avatarImage(forCNContactId contactId: String?) -> UIImage? {
        return nil
    }

    public var unknownUserLabel: String {
        "Unknown"
    }

    public func leaseCacheSize(_ size: Int) -> ModelReadCacheSizeLease? {
        return nil
    }
}
