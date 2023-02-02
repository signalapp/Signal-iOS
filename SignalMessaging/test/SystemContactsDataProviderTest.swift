//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import XCTest

@testable import SignalMessaging

class SystemContactsDataProviderTest: SignalBaseTest {

    func testPrimaryDeviceDataProvider() {
        let dataProvider = PrimaryDeviceSystemContactsDataProvider()

        var oldContactsMaps: ContactsMaps = .build(contacts: [], localNumber: nil)
        func setContacts(_ contacts: [Contact], transaction: SDSAnyWriteTransaction) {
            let newContactsMaps: ContactsMaps = .build(contacts: contacts, localNumber: nil)
            dataProvider.setContactsMaps(
                newContactsMaps,
                oldContactsMaps: { oldContactsMaps },
                localNumber: nil,
                transaction: transaction
            )
            oldContactsMaps = newContactsMaps
        }

        let cnContact = CNMutableContact()
        cnContact.givenName = "Alice"
        cnContact.familyName = "Johnson"
        cnContact.nickname = "Ali"
        cnContact.phoneNumbers.append(
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+1 (650) 555-0100"))
        )
        cnContact.emailAddresses.append(
            CNLabeledValue(label: CNLabelHome, value: "someone@example.com")
        )

        let johnContact = {
            let contact = CNMutableContact()
            contact.givenName = "John"
            contact.phoneNumbers.append(
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+1 (650) 555-0199"))
            )
            contact.phoneNumbers.append(
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+1 (650) 555-0198"))
            )
            return Contact(systemContact: contact)
        }()

        // Step 1: Save two contacts & fetch both of them via both methods.

        let aliContact1 = Contact(systemContact: cnContact)
        write {
            setContacts([aliContact1, johnContact], transaction: $0)
        }

        read {
            XCTAssertEqual(aliContact1, dataProvider.fetchSystemContact(for: "+16505550100", transaction: $0))
            XCTAssertEqual(johnContact, dataProvider.fetchSystemContact(for: "+16505550198", transaction: $0))
            XCTAssertEqual(johnContact, dataProvider.fetchSystemContact(for: "+16505550199", transaction: $0))
            XCTAssertEqual(2, dataProvider.fetchAllSystemContacts(transaction: $0).count)
        }

        // Step 2: Replace a phone number & ensure the new one is fetchable but the
        // old one isn't.

        cnContact.phoneNumbers.removeAll()
        cnContact.phoneNumbers.append(
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+1 (650) 555-0101"))
        )

        let aliContact2 = Contact(systemContact: cnContact)
        write {
            setContacts([aliContact2, johnContact], transaction: $0)
        }

        read {
            XCTAssertNil(dataProvider.fetchSystemContact(for: "+16505550100", transaction: $0))
            XCTAssertEqual(aliContact2, dataProvider.fetchSystemContact(for: "+16505550101", transaction: $0))
            XCTAssertEqual(johnContact, dataProvider.fetchSystemContact(for: "+16505550198", transaction: $0))
            XCTAssertEqual(johnContact, dataProvider.fetchSystemContact(for: "+16505550199", transaction: $0))
            XCTAssertEqual(2, dataProvider.fetchAllSystemContacts(transaction: $0).count)
        }

        // Step 3: Remove a contact entirely & ensure it can't be fetched.

        write {
            setContacts([johnContact], transaction: $0)
        }

        read {
            XCTAssertNil(dataProvider.fetchSystemContact(for: "+16505550100", transaction: $0))
            XCTAssertNil(dataProvider.fetchSystemContact(for: "+16505550101", transaction: $0))
            XCTAssertEqual(johnContact, dataProvider.fetchSystemContact(for: "+16505550198", transaction: $0))
            XCTAssertEqual(johnContact, dataProvider.fetchSystemContact(for: "+16505550199", transaction: $0))
            XCTAssertEqual(1, dataProvider.fetchAllSystemContacts(transaction: $0).count)
        }
    }
}
