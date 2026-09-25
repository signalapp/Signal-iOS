//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import Testing

@testable import SignalServiceKit

struct OWSContactTests {
    private func isValid(
        name: OWSContactName = OWSContactName(givenName: "Alice"),
        phoneNumbers: [OWSContactPhoneNumber] = [],
        aci: Aci? = nil,
    ) -> Bool {
        return OWSContact.isValid(name: name, phoneNumbers: phoneNumbers, emails: [], addresses: [], aci: aci)
    }

    @Test
    func aciOnlyContactIsValid() {
        #expect(isValid(aci: .randomForTesting()))
    }

    @Test
    func phoneNumberOnlyContactIsValid() {
        #expect(isValid(phoneNumbers: [OWSContactPhoneNumber(type: .mobile, phoneNumber: "+16505550100")]))
    }

    @Test
    func contactWithNothingToShareIsInvalid() {
        #expect(!isValid())
    }

    @Test
    func nicknameAndNoteSurviveArchiving() throws {
        var nickname = PersonNameComponents()
        nickname.givenName = "Ali"
        nickname.familyName = "Cat"
        let contact = OWSContact(
            name: OWSContactName(givenName: "Alice"),
            phoneNumbers: [],
            emails: [],
            addresses: [],
            aci: .randomForTesting(),
            nickname: nickname,
            note: "Met at the conference",
        )
        let data = try NSKeyedArchiver.archivedData(withRootObject: contact, requiringSecureCoding: true)
        let decoded = try #require(try NSKeyedUnarchiver.unarchivedObject(ofClass: OWSContact.self, from: data))
        #expect(decoded.nickname == nickname)
        #expect(decoded.note == "Met at the conference")
        #expect(decoded == contact)
    }
}
