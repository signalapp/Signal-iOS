//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

@objc(OWSFakeContactsManager)
class FakeContactsManager: NSObject, ContactsManagerProtocol {
    func displayName(forPhoneIdentifier recipientId: String?) -> String {
        return "Fake name"
    }

    func displayName(forPhoneIdentifier recipientId: String?, transaction: YapDatabaseReadTransaction) -> String {
        return self.displayName(forPhoneIdentifier: recipientId)
    }

    func signalAccounts() -> [SignalAccount] {
        return []
    }

    func isSystemContact(_ recipientId: String) -> Bool {
        return true
    }

    func isSystemContact(withSignalAccount recipientId: String) -> Bool {
        return true
    }

    func compare(signalAccount left: SignalAccount, with right: SignalAccount) -> ComparisonResult {
        // If this method ends up being used by the tests, we should provide a better implementation.
        assertionFailure("TODO")
        return ComparisonResult.orderedAscending
    }

    func cnContact(withId contactId: String?) -> CNContact? {
        return nil
    }

    func avatarData(forCNContactId contactId: String?) -> Data? {
        return nil
    }

    func avatarImage(forCNContactId contactId: String?) -> UIImage? {
        return nil
    }
}
