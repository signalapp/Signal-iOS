//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Contacts
import XCTest

@testable import SignalMessaging

class ContactsManagerCacheTest: SignalBaseTest {

    func testSetContactsMaps() {
        let contactsManagerCache = ContactsManagerCacheInDatabase()

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

        let aliContact1 = Contact(systemContact: cnContact)
        write {
            contactsManagerCache.setContactsMaps(
                .build(contacts: [aliContact1, johnContact], localNumber: nil), localNumber: nil, transaction: $0
            )
        }

        read {
            XCTAssertEqual(aliContact1, contactsManagerCache.contact(forPhoneNumber: "+16505550100", transaction: $0))
            XCTAssertEqual(johnContact, contactsManagerCache.contact(forPhoneNumber: "+16505550198", transaction: $0))
            XCTAssertEqual(johnContact, contactsManagerCache.contact(forPhoneNumber: "+16505550199", transaction: $0))
            XCTAssertEqual(2, contactsManagerCache.allContacts(transaction: $0).count)
        }

        cnContact.phoneNumbers.removeAll()
        cnContact.phoneNumbers.append(
            CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: "+1 (650) 555-0101"))
        )

        let aliContact2 = Contact(systemContact: cnContact)
        write {
            contactsManagerCache.setContactsMaps(
                .build(contacts: [aliContact2, johnContact], localNumber: nil), localNumber: nil, transaction: $0
            )
        }

        read {
            XCTAssertNil(contactsManagerCache.contact(forPhoneNumber: "+16505550100", transaction: $0))
            XCTAssertEqual(aliContact2, contactsManagerCache.contact(forPhoneNumber: "+16505550101", transaction: $0))
            XCTAssertEqual(johnContact, contactsManagerCache.contact(forPhoneNumber: "+16505550198", transaction: $0))
            XCTAssertEqual(johnContact, contactsManagerCache.contact(forPhoneNumber: "+16505550199", transaction: $0))
            XCTAssertEqual(2, contactsManagerCache.allContacts(transaction: $0).count)
        }

        write {
            contactsManagerCache.setContactsMaps(
                .build(contacts: [johnContact], localNumber: nil), localNumber: nil, transaction: $0
            )
        }

        read {
            XCTAssertNil(contactsManagerCache.contact(forPhoneNumber: "+16505550100", transaction: $0))
            XCTAssertNil(contactsManagerCache.contact(forPhoneNumber: "+16505550101", transaction: $0))
            XCTAssertEqual(johnContact, contactsManagerCache.contact(forPhoneNumber: "+16505550198", transaction: $0))
            XCTAssertEqual(johnContact, contactsManagerCache.contact(forPhoneNumber: "+16505550199", transaction: $0))
            XCTAssertEqual(1, contactsManagerCache.allContacts(transaction: $0).count)
        }
    }
}
