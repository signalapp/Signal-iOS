//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import SignalServiceKit
import XCTest

@testable import SignalMessaging

class ProfileManagerTest: XCTestCase {
    func testNormalizeRecipientInProfileWhitelist() {
        let aci = Aci.constantForTesting("00000000-0000-4000-8000-000000000aaa")
        let phoneNumber = E164("+16505550100")!
        let pni = Pni.constantForTesting("PNI:00000000-0000-4000-8000-000000000bbb")

        let serviceIdStore = InMemoryKeyValueStore(collection: "")
        let phoneNumberStore = InMemoryKeyValueStore(collection: "")

        func normalizeRecipient(_ recipient: SignalRecipient) {
            MockDB().write { tx in
                OWSProfileManager.swift_normalizeRecipientInProfileWhitelist(
                    recipient,
                    serviceIdStore: serviceIdStore,
                    phoneNumberStore: phoneNumberStore,
                    tx: tx
                )
            }
        }

        // Don't add any values unless one is already present.
        MockDB().read { tx in
            normalizeRecipient(SignalRecipient(aci: aci, pni: pni, phoneNumber: phoneNumber))
            XCTAssertFalse(serviceIdStore.hasValue(aci.serviceIdUppercaseString, transaction: tx))
            XCTAssertFalse(phoneNumberStore.hasValue(phoneNumber.stringValue, transaction: tx))
            XCTAssertFalse(serviceIdStore.hasValue(pni.serviceIdUppercaseString, transaction: tx))
        }

        // Move the PNI identifier to the phone number.
        MockDB().write { tx in
            serviceIdStore.setBool(true, key: pni.serviceIdUppercaseString, transaction: tx)
            normalizeRecipient(SignalRecipient(aci: nil, pni: pni, phoneNumber: phoneNumber))
            XCTAssertFalse(serviceIdStore.hasValue(aci.serviceIdUppercaseString, transaction: tx))
            XCTAssertTrue(phoneNumberStore.hasValue(phoneNumber.stringValue, transaction: tx))
            XCTAssertFalse(serviceIdStore.hasValue(pni.serviceIdUppercaseString, transaction: tx))
        }

        // Clear lower priority identifiers when multiple are present.
        MockDB().write { tx in
            serviceIdStore.setBool(true, key: aci.serviceIdUppercaseString, transaction: tx)
            normalizeRecipient(SignalRecipient(aci: aci, pni: pni, phoneNumber: phoneNumber))
            XCTAssertTrue(serviceIdStore.hasValue(aci.serviceIdUppercaseString, transaction: tx))
            XCTAssertFalse(phoneNumberStore.hasValue(phoneNumber.stringValue, transaction: tx))
            XCTAssertFalse(serviceIdStore.hasValue(pni.serviceIdUppercaseString, transaction: tx))
        }

        // Keep the highest priority identifier if it's already present.
        MockDB().write { tx in
            normalizeRecipient(SignalRecipient(aci: aci, pni: pni, phoneNumber: phoneNumber))
            XCTAssertTrue(serviceIdStore.hasValue(aci.serviceIdUppercaseString, transaction: tx))
            XCTAssertFalse(phoneNumberStore.hasValue(phoneNumber.stringValue, transaction: tx))
            XCTAssertFalse(serviceIdStore.hasValue(pni.serviceIdUppercaseString, transaction: tx))
        }
    }
}
