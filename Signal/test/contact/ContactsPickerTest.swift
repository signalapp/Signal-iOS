//
// Copyright 2016 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import Contacts
@testable import Signal

final class ContactsPickerTest: SignalBaseTest {
    private var prevLang: Any?

    override func setUp() {
        super.setUp()

        prevLang = getLang()
    }

    override func tearDown() {
        super.tearDown()

        if let prevLang = prevLang {
            setLang(value: prevLang)
        }
    }

    func testContactSectionMatchesEmailFirstLetterWhenOnlyEmailContact() {
        setLangEN()

        let emailOnlyContactB = CNMutableContact()
        emailOnlyContactB.emailAddresses.append(CNLabeledValue(label: nil, value: "bla@bla.com"))

        let emailOnlyContactD = CNMutableContact()
        emailOnlyContactD.emailAddresses.append(CNLabeledValue(label: nil, value: "dude@bla.com"))

        let contactsPicker = ContactsPicker(allowsMultipleSelection: false, subtitleCellType: .phoneNumber)
        let collatedContacts = contactsPicker.collatedContacts([emailOnlyContactB, emailOnlyContactD])

        let sectionTitles = contactsPicker.collationForTests.sectionTitles
        if let bIndex = sectionTitles.firstIndex(of: "B") {
            let bSectionContacts = collatedContacts[bIndex]
            XCTAssertEqual(bSectionContacts.first, emailOnlyContactB)
        }

        if let dIndex = sectionTitles.firstIndex(of: "D") {
            let dSectionContacts = collatedContacts[dIndex]
            XCTAssertEqual(dSectionContacts.first, emailOnlyContactD)
        }
    }

    func testContactSectionMatchesNameFirstLetterWhenNameExistsInContact() {
        setLangEN()

        let nameAndEmailContact = CNMutableContact()
        nameAndEmailContact.givenName = "Alice"
        nameAndEmailContact.emailAddresses.append(CNLabeledValue(label: nil, value: "nameAndEmail@bla.com"))

        let contactsPicker = ContactsPicker(allowsMultipleSelection: false, subtitleCellType: .phoneNumber)
        let collatedContacts = contactsPicker.collatedContacts([nameAndEmailContact])

        let sectionTitles = contactsPicker.collationForTests.sectionTitles
        if let aIndex = sectionTitles.firstIndex(of: "A") {
            let aSectionContacts = collatedContacts[aIndex]
            XCTAssertEqual(aSectionContacts.first, nameAndEmailContact)
        }
    }

    private func setLangEN() {
        setLang(value: "en")
    }

    private func setLang(value: Any) {
        UserDefaults.standard.set(value, forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
    }

    private func setLang(value: String) {
        setLang(value: [value])
    }

    private func getLang() -> Any? {
        return UserDefaults.standard.value(forKey: "AppleLanguages")
    }
}
