//
// Copyright 2018 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import Contacts

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
                if let signalAccount = mockSignalAccounts[phoneNumber.stringValue] {
                    var nameComponents = PersonNameComponents()
                    nameComponents.givenName = signalAccount.givenName
                    nameComponents.familyName = signalAccount.familyName
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
        return displayName(for: address, tx: transaction).resolvedValue(config: DisplayName.Config(shouldUseSystemContactNicknames: false))
    }

    public func shortDisplayNameString(for address: SignalServiceAddress, transaction: SDSAnyReadTransaction) -> String {
        return displayNameString(for: address, transaction: transaction)
    }

    public func cnContactId(for phoneNumber: String) -> String? {
        return nil
    }

    public func cnContact(withId contactId: String?) -> CNContact? {
        return nil
    }
}

#endif
