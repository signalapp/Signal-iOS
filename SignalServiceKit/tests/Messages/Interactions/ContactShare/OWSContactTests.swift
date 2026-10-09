//
// Copyright 2026 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import Testing

@testable import SignalServiceKit

struct OWSContactTests {
    @Test
    func nameOnlyContactIsValid() {
        #expect(OWSContact(name: OWSContactName(givenName: "Alice")).isValid)
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

    @Test
    func displayNamePrefersTheFullNameOverTheNickname() {
        let name = OWSContactName(givenName: "Ada", familyName: "Lovelace", nickname: "Countess")
        #expect(name.displayName == "Ada Lovelace")
    }

    @Test
    func displayNameFallsBackToTheNickname() {
        let name = OWSContactName(nickname: "Countess")
        #expect(name.displayName == "Countess")
    }
}
