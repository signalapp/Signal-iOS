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
}
