//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
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

    public func compare(signalAccount left: SignalAccount, with right: SignalAccount) -> ComparisonResult {
        // If this method ends up being used by the tests, we should provide a better implementation.
        assertionFailure("TODO")
        return ComparisonResult.orderedAscending
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
}
