//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@objc(OWSFakeContactsManager)
public class FakeContactsManager: NSObject, ContactsManagerProtocol {
    public func displayName(forPhoneIdentifier recipientId: String?) -> String {
        return "Fake name"
    }

    public func displayName(forPhoneIdentifier recipientId: String?, transaction: YapDatabaseReadTransaction) -> String {
        return self.displayName(forPhoneIdentifier: recipientId)
    }

    public func signalAccounts() -> [SignalAccount] {
        return []
    }

    public func isSystemContact(_ recipientId: String) -> Bool {
        return true
    }

    public func isSystemContact(withSignalAccount recipientId: String) -> Bool {
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
