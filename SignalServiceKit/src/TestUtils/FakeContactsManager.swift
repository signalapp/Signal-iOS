//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Contacts

@objc(OWSFakeContactsManager)
public class FakeContactsManager: NSObject, ContactsManagerProtocol {
    public func displayName(for address: SignalServiceAddress) -> String {
        return "Fake name"
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

    public func nameComponents(for address: SignalServiceAddress) -> PersonNameComponents? {
        return PersonNameComponents()
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

    public func isSystemContact(phoneNumber: String) -> Bool {
        return true
    }

    public func isSystemContact(address: SignalServiceAddress) -> Bool {
        return true
    }

    public func isSystemContact(withSignalAccount phoneNumber: String) -> Bool {
        return true
    }

    public func isSystemContact(withSignalAccount phoneNumber: String, transaction: SDSAnyReadTransaction) -> Bool {
        return true
    }

    public func hasNameInSystemContacts(for address: SignalServiceAddress) -> Bool {
        return true
    }

    public func hasNameInSystemContacts(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> Bool {
        return true
    }

    public func conversationColorName(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> ConversationColorName {
        ConversationColorName.indigo
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
}
