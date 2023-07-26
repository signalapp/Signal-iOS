//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

class SignalServiceAddressTest: XCTestCase {

    private lazy var cache = SignalServiceAddressCache()

    private func makeAddress(serviceId: ServiceId? = nil, phoneNumber: String? = nil) -> SignalServiceAddress {
        SignalServiceAddress(
            serviceId: serviceId,
            phoneNumber: phoneNumber,
            cache: cache,
            cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
        )
    }

    private func makeHighTrustAddress(aci: FutureAci? = nil, phoneNumber: String? = nil) -> SignalServiceAddress {
        cache.updateRecipient(SignalRecipient(serviceId: aci, phoneNumber: phoneNumber.flatMap { E164($0) }))
        return makeAddress(serviceId: aci, phoneNumber: phoneNumber)
    }

    @discardableResult
    private func updateMapping(aci: FutureAci, phoneNumber: String? = nil) -> SignalServiceAddress {
        return makeHighTrustAddress(aci: aci, phoneNumber: phoneNumber)
    }

    func test_isEqualPermissive() {
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"
        let aci1 = Aci.randomForTesting()
        let aci2 = Aci.randomForTesting()

        // Double match
        XCTAssertEqual(
            makeAddress(serviceId: aci1, phoneNumber: phoneNumber1),
            makeAddress(serviceId: aci1, phoneNumber: phoneNumber1)
        )

        updateMapping(aci: aci1, phoneNumber: phoneNumber1)

        // Single match works, ignores single missing.
        XCTAssertEqual(
            makeAddress(serviceId: nil, phoneNumber: phoneNumber1),
            makeAddress(serviceId: aci1, phoneNumber: phoneNumber1)
        )
        XCTAssertEqual(
            makeAddress(serviceId: aci1),
            makeAddress(serviceId: aci1, phoneNumber: phoneNumber1)
        )
        XCTAssertEqual(
            makeAddress(serviceId: aci1, phoneNumber: phoneNumber1),
            makeAddress(serviceId: nil, phoneNumber: phoneNumber1)
        )
        XCTAssertEqual(
            makeAddress(serviceId: aci1, phoneNumber: phoneNumber1),
            makeAddress(serviceId: aci1)
        )

        // Single match works, ignores double missing.
        XCTAssertEqual(
            makeAddress(serviceId: nil, phoneNumber: phoneNumber1),
            makeAddress(serviceId: nil, phoneNumber: phoneNumber1)
        )
        XCTAssertEqual(
            makeAddress(serviceId: aci1),
            makeAddress(serviceId: aci1)
        )

        // Ignores phone number when UUIDs match.
        XCTAssertEqual(
            makeAddress(serviceId: aci1, phoneNumber: phoneNumber1),
            makeAddress(serviceId: aci1, phoneNumber: phoneNumber2)
        )

        // Match fails if no common value.
        XCTAssertEqual(
            makeAddress(serviceId: aci1),
            makeAddress(serviceId: nil, phoneNumber: phoneNumber1)
        )

        // Match fails if either value doesn't match.
        XCTAssertNotEqual(
            makeAddress(serviceId: aci1),
            makeAddress(serviceId: aci2)
        )
        XCTAssertNotEqual(
            makeAddress(serviceId: nil, phoneNumber: phoneNumber1),
            makeAddress(serviceId: nil, phoneNumber: phoneNumber2)
        )
        XCTAssertNotEqual(
            makeAddress(serviceId: aci1, phoneNumber: phoneNumber1),
            makeAddress(serviceId: aci2)
        )
        XCTAssertNotEqual(
            makeAddress(serviceId: aci1, phoneNumber: phoneNumber1),
            makeAddress(serviceId: nil, phoneNumber: phoneNumber2)
        )
        XCTAssertNotEqual(
            makeAddress(serviceId: aci1, phoneNumber: phoneNumber1),
            makeAddress(serviceId: aci2, phoneNumber: phoneNumber1)
        )
        XCTAssertNotEqual(
            makeAddress(serviceId: aci1, phoneNumber: phoneNumber1),
            makeAddress(serviceId: aci2, phoneNumber: phoneNumber2)
        )
    }

    func test_mappingChanges() {
        let aci1 = Aci.randomForTesting()
        let aci2 = Aci.randomForTesting()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"
        let phoneNumber3 = "+16505550102"

        let address1a = makeAddress(serviceId: aci1, phoneNumber: nil)
        let address1b = makeAddress(serviceId: aci1, phoneNumber: nil)
        let address1c = makeAddress(serviceId: aci1, phoneNumber: phoneNumber1)
        let address1d = makeAddress(serviceId: nil, phoneNumber: phoneNumber1)
        let address2a = makeAddress(serviceId: aci2, phoneNumber: nil)
        let address2b = makeAddress(serviceId: aci2, phoneNumber: phoneNumber2)
        let address3a = makeAddress(serviceId: nil, phoneNumber: phoneNumber3)

        // Make sure nothing has been resolved about these addresses other than
        // what was explicitly provided as part of the initializer.

        XCTAssertEqual(address1a.serviceId, aci1)
        XCTAssertNil(address1a.phoneNumber)
        XCTAssertEqual(address1b.serviceId, aci1)
        XCTAssertNil(address1b.phoneNumber)
        XCTAssertEqual(address1c.serviceId, aci1)
        XCTAssertEqual(address1c.phoneNumber, phoneNumber1)
        XCTAssertNil(address1d.serviceId)
        XCTAssertEqual(address1d.phoneNumber, phoneNumber1)
        XCTAssertEqual(address2a.serviceId, aci2)
        XCTAssertNil(address2a.phoneNumber)
        XCTAssertEqual(address2b.serviceId, aci2)
        XCTAssertEqual(address2b.phoneNumber, phoneNumber2)
        XCTAssertNil(address3a.serviceId)
        XCTAssertEqual(address3a.phoneNumber, phoneNumber3)

        // High-trust with phoneNumber1.

        updateMapping(aci: aci1, phoneNumber: phoneNumber1)

        XCTAssertEqual(address1a.serviceId, aci1)
        XCTAssertEqual(address1a.phoneNumber, phoneNumber1)
        XCTAssertEqual(address1b.serviceId, aci1)
        XCTAssertEqual(address1b.phoneNumber, phoneNumber1)
        XCTAssertEqual(address1c.serviceId, aci1)
        XCTAssertEqual(address1c.phoneNumber, phoneNumber1)
        XCTAssertEqual(address1d.serviceId, aci1)
        XCTAssertEqual(address1d.phoneNumber, phoneNumber1)
        XCTAssertEqual(address2a.serviceId, aci2)
        XCTAssertNil(address2a.phoneNumber)
        XCTAssertEqual(address2b.serviceId, aci2)
        XCTAssertEqual(address2b.phoneNumber, phoneNumber2)
        XCTAssertNil(address3a.serviceId)
        XCTAssertEqual(address3a.phoneNumber, phoneNumber3)

        // High-trust with phoneNumber3.

        updateMapping(aci: aci1, phoneNumber: phoneNumber3)

        XCTAssertEqual(address1a.serviceId, aci1)
        XCTAssertEqual(address1a.phoneNumber, phoneNumber3)
        XCTAssertEqual(address1b.serviceId, aci1)
        XCTAssertEqual(address1b.phoneNumber, phoneNumber3)
        XCTAssertEqual(address1c.serviceId, aci1)
        XCTAssertEqual(address1c.phoneNumber, phoneNumber3)
        XCTAssertEqual(address1d.serviceId, aci1)
        XCTAssertEqual(address1d.phoneNumber, phoneNumber3)
        XCTAssertEqual(address2a.serviceId, aci2)
        XCTAssertNil(address2a.phoneNumber)
        XCTAssertEqual(address2b.serviceId, aci2)
        XCTAssertEqual(address2b.phoneNumber, phoneNumber2)
        XCTAssertEqual(address3a.serviceId, aci1)
        XCTAssertEqual(address3a.phoneNumber, phoneNumber3)
    }

    // A new address "takes" a uuid component a pre-existing address.
    func test_mappingChanges1a() {
        let aci1 = Aci.randomForTesting()
        let aci2 = Aci.randomForTesting()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        // aci1, phoneNumber1 -> phoneNumber2
        let hash2 = makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for aci1, since the uuid remains the same.
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertNil(makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(aci1, makeAddress(phoneNumber: phoneNumber2).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)

        // aci2, phoneNumber1
        let hash3 = makeHighTrustAddress(aci: aci2, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for aci2, even though the uuid has changed.
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertEqual(hash2, hash3)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash3, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash3, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(serviceId: aci2).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(serviceId: aci2).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(aci1, makeAddress(phoneNumber: phoneNumber2).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" a uuid component a pre-existing address.
    func test_mappingChanges1b() {
        let aci1 = Aci.randomForTesting()
        let aci2 = Aci.randomForTesting()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        // aci1, phoneNumber1 -> phoneNumber2
        let hash2 = updateMapping(aci: aci1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for aci1, since the uuid remains the same.
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertNil(makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(aci1, makeAddress(phoneNumber: phoneNumber2).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)

        // aci2, phoneNumber1
        let hash3 = updateMapping(aci: aci2, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for aci2, even though the uuid has changed.
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertEqual(hash2, hash3)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash3, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash3, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(serviceId: aci2).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(serviceId: aci2).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(aci1, makeAddress(phoneNumber: phoneNumber2).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" a phone number component a pre-existing address.
    func test_mappingChanges2a() {
        let aci1 = Aci.randomForTesting()
        let aci2 = Aci.randomForTesting()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        // aci1 -> aci2, phoneNumber1
        _ = makeAddress(serviceId: aci2)
        let hash2 = makeHighTrustAddress(aci: aci2, phoneNumber: phoneNumber1).hash

        // There should not be hash continuity for aci2 since the phone number was
        // transferred to a UUID that already existed.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertNil(makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(serviceId: aci2).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(serviceId: aci2).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)

        // aci1, phoneNumber2
        let hash3 = makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for aci1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(serviceId: aci2).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(serviceId: aci2).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(aci1, makeAddress(phoneNumber: phoneNumber2).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" a phone number component a pre-existing address.
    func test_mappingChanges2b() {
        let aci1 = Aci.randomForTesting()
        let aci2 = Aci.randomForTesting()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        // aci1 -> aci2, phoneNumber1
        _ = makeAddress(serviceId: aci2)
        let hash2 = updateMapping(aci: aci2, phoneNumber: phoneNumber1).hash

        // There should not be hash continuity for aci2 since the phone number was
        // transferred to a UUID that already existed.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertNil(makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(serviceId: aci2).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(serviceId: aci2).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)

        // aci1, phoneNumber2
        let hash3 = updateMapping(aci: aci1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for aci1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(serviceId: aci2).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(serviceId: aci2).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(aci1, makeAddress(phoneNumber: phoneNumber2).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "combines" 2 pre-existing addresses.
    func test_mappingChanges3a() {
        let aci1 = Aci.randomForTesting()
        let phoneNumber1 = "+16505550100"

        let hash1 = makeHighTrustAddress(aci: aci1, phoneNumber: nil).hash
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)

        let hash2 = makeHighTrustAddress(aci: nil, phoneNumber: phoneNumber1).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)

        // Associate aci1, phoneNumber1
        let hash3 = makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for the uuid, not the phone number.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertEqual(aci1, makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
    }

    // A new address "combines" 2 pre-existing addresses.
    func test_mappingChanges3b() {
        let aci1 = Aci.randomForTesting()
        let phoneNumber1 = "+16505550100"

        let hash1 = makeHighTrustAddress(aci: aci1, phoneNumber: nil).hash
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)

        let hash2 = makeHighTrustAddress(aci: nil, phoneNumber: phoneNumber1).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)

        // Associate aci1, phoneNumber1
        let hash3 = updateMapping(aci: aci1, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for the uuid, not the phone number.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertEqual(aci1, makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
    }

    // A new address "takes" 1 component each from 2 pre-existing addresses.
    func test_mappingChanges4a() {
        let aci1 = Aci.randomForTesting()
        let aci2 = Aci.randomForTesting()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        let hash2 = makeHighTrustAddress(aci: aci2, phoneNumber: phoneNumber2).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        // Associate aci1, phoneNumber2
        let hash3 = makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for aci1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertNil(makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(serviceId: aci2).serviceId)
        XCTAssertNil(makeAddress(serviceId: aci2).phoneNumber)
        XCTAssertEqual(aci1, makeAddress(phoneNumber: phoneNumber2).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component each from 2 pre-existing addresses.
    func test_mappingChanges4b() {
        let aci1 = Aci.randomForTesting()
        let aci2 = Aci.randomForTesting()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        let hash2 = makeHighTrustAddress(aci: aci2, phoneNumber: phoneNumber2).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        // Associate aci1, phoneNumber2
        let hash3 = updateMapping(aci: aci1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for aci1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertNil(makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(serviceId: aci2).serviceId)
        XCTAssertNil(makeAddress(serviceId: aci2).phoneNumber)
        XCTAssertEqual(aci1, makeAddress(phoneNumber: phoneNumber2).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component from a pre-existing address for a pre-existing uuid.
    func test_mappingChanges5a() {
        let aci1 = Aci.randomForTesting()
        let aci2 = Aci.randomForTesting()
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(aci: aci1, phoneNumber: nil).hash
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)

        let hash2 = makeHighTrustAddress(aci: aci2, phoneNumber: phoneNumber2).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        // Associate aci1, phoneNumber2
        let hash3 = makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for aci1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(serviceId: aci2).serviceId)
        XCTAssertNil(makeAddress(serviceId: aci2).phoneNumber)
        XCTAssertEqual(aci1, makeAddress(phoneNumber: phoneNumber2).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component from a pre-existing address for a pre-existing uuid.
    func test_mappingChanges5b() {
        let aci1 = Aci.randomForTesting()
        let aci2 = Aci.randomForTesting()
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(aci: aci1, phoneNumber: nil).hash
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)

        let hash2 = makeHighTrustAddress(aci: aci2, phoneNumber: phoneNumber2).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        // Associate aci1, phoneNumber2
        let hash3 = updateMapping(aci: aci1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for aci1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(serviceId: aci1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(aci1, makeAddress(serviceId: aci1).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(serviceId: aci1).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(serviceId: aci2).serviceId)
        XCTAssertNil(makeAddress(serviceId: aci2).phoneNumber)
        XCTAssertEqual(aci1, makeAddress(phoneNumber: phoneNumber2).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component from a pre-existing address for a pre-existing phone number.
    func test_mappingChanges6a() {
        let aci2 = Aci.randomForTesting()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(aci: nil, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        let hash2 = makeHighTrustAddress(aci: aci2, phoneNumber: phoneNumber2).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        // Associate aci2, phoneNumber1
        let hash3 = makeHighTrustAddress(aci: aci2, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for aci2.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertNotEqual(hash1, hash3)
        XCTAssertEqual(hash2, hash3)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertNotEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(aci2, makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(serviceId: aci2).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(serviceId: aci2).phoneNumber)
        XCTAssertNil(makeAddress(phoneNumber: phoneNumber2).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component from a pre-existing address for a pre-existing phone number.
    func test_mappingChanges6b() {
        let aci2 = Aci.randomForTesting()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(aci: nil, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        let hash2 = makeHighTrustAddress(aci: aci2, phoneNumber: phoneNumber2).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        // Associate aci2, phoneNumber1
        let hash3 = updateMapping(aci: aci2, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for aci2.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertNotEqual(hash1, hash3)
        XCTAssertEqual(hash2, hash3)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(serviceId: aci2).hash)
        XCTAssertNotEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(aci2, makeAddress(phoneNumber: phoneNumber1).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(aci2, makeAddress(serviceId: aci2).serviceId)
        XCTAssertEqual(phoneNumber1, makeAddress(serviceId: aci2).phoneNumber)
        XCTAssertNil(makeAddress(phoneNumber: phoneNumber2).serviceId)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    func test_hashStability1() {
        let aci1 = Aci.randomForTesting()
        let aci2 = Aci.randomForTesting()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash_u1 = makeAddress(serviceId: aci1, phoneNumber: nil).hash
        XCTAssertEqual(hash_u1, makeAddress(serviceId: aci1, phoneNumber: nil).hash)

        XCTAssertEqual(hash_u1, makeAddress(serviceId: aci1, phoneNumber: phoneNumber1).hash)
        // hash_u1 is now also associated with p1.
        XCTAssertEqual(hash_u1, makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash_u1, makeAddress(serviceId: nil, phoneNumber: phoneNumber1).hash)

        let hash_u2 = makeAddress(serviceId: aci2, phoneNumber: nil).hash
        XCTAssertEqual(hash_u2, makeAddress(serviceId: aci2, phoneNumber: nil).hash)
        XCTAssertNotEqual(hash_u2, hash_u1)

        // hash_u2 is now also associated with p2.
        XCTAssertEqual(hash_u2, makeAddress(serviceId: aci2, phoneNumber: phoneNumber2).hash)
        XCTAssertEqual(hash_u2, makeHighTrustAddress(aci: aci2, phoneNumber: phoneNumber2).hash)
        XCTAssertEqual(hash_u2, makeAddress(serviceId: nil, phoneNumber: phoneNumber2).hash)

        // We now re-map p2 to u1.
        XCTAssertEqual(hash_u1, makeAddress(serviceId: aci1, phoneNumber: phoneNumber2).hash)
        XCTAssertEqual(hash_u1, makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber2).hash)
        XCTAssertEqual(hash_u1, makeAddress(serviceId: aci1, phoneNumber: nil).hash)
        XCTAssertEqual(hash_u2, makeAddress(serviceId: aci2, phoneNumber: nil).hash)
        XCTAssertEqual(hash_u1, makeAddress(serviceId: nil, phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash_u1, makeAddress(serviceId: nil, phoneNumber: phoneNumber2).hash)
    }

    func test_hashStability2() {
        let aci1 = Aci.randomForTesting()
        let phoneNumber1 = "+16505550100"

        let hash_u1 = makeAddress(serviceId: aci1, phoneNumber: nil).hash
        XCTAssertEqual(hash_u1, makeAddress(serviceId: aci1, phoneNumber: nil).hash)

        let hash_p1 = makeAddress(serviceId: nil, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash_p1, makeAddress(serviceId: nil, phoneNumber: phoneNumber1).hash)
        XCTAssertNotEqual(hash_u1, hash_p1)

        let address_u1 = makeAddress(serviceId: aci1, phoneNumber: nil)
        let address_p1 = makeAddress(serviceId: nil, phoneNumber: phoneNumber1)

        // We now map p1 to u1.
        XCTAssertEqual(hash_u1, makeHighTrustAddress(aci: aci1, phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash_u1, makeAddress(serviceId: aci1, phoneNumber: nil).hash)
        XCTAssertEqual(hash_u1, makeAddress(serviceId: nil, phoneNumber: phoneNumber1).hash)

        // New u1 addresses are equal to old u1 addresses and have the same hash.
        XCTAssertEqual(address_u1, makeAddress(serviceId: aci1, phoneNumber: nil))
        XCTAssertEqual(address_u1.hash, makeAddress(serviceId: aci1, phoneNumber: nil).hash)

        // New p1 addresses are equal to old p1 addresses BUT DO NOT have the same hash.
        // This degenerate case is unfortunately unavoidable without large changes where
        // the cure is probably worse than the disease.
        XCTAssertEqual(address_p1, makeAddress(serviceId: nil, phoneNumber: phoneNumber1))
        XCTAssertNotEqual(address_p1.hash, makeAddress(serviceId: nil, phoneNumber: phoneNumber1).hash)
    }

    func testInitializers() {
        let aci = Aci.constantForTesting("00000000-0000-4000-8000-00000000000A")
        let pn_a = E164("+16505550101")!
        let pn_b = E164("+16505550102")!

        cache.updateRecipient(SignalRecipient(serviceId: aci, phoneNumber: pn_a))

        let address1 = SignalServiceAddress(
            serviceId: aci,
            phoneNumber: nil,
            cache: cache,
            cachePolicy: .preferCachedPhoneNumberAndListenForUpdates
        )
        let address2 = SignalServiceAddress(
            serviceId: aci,
            phoneNumber: pn_a.stringValue,
            cache: cache,
            cachePolicy: .preferCachedPhoneNumberAndListenForUpdates
        )
        let address3 = SignalServiceAddress(
            serviceId: aci,
            phoneNumber: pn_b.stringValue,
            cache: cache,
            cachePolicy: .preferCachedPhoneNumberAndListenForUpdates
        )

        XCTAssertEqual(address1.e164, pn_a)
        XCTAssertEqual(address2.e164, pn_a)
        XCTAssertEqual(address3.e164, pn_a)

        let address4 = SignalServiceAddress(
            serviceId: aci,
            phoneNumber: nil,
            cache: cache,
            cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
        )
        let address5 = SignalServiceAddress(
            serviceId: aci,
            phoneNumber: pn_a.stringValue,
            cache: cache,
            cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
        )
        let address6 = SignalServiceAddress(
            serviceId: aci,
            phoneNumber: pn_b.stringValue,
            cache: cache,
            cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
        )

        XCTAssertEqual(address4.e164, pn_a)
        XCTAssertEqual(address5.e164, pn_a)
        XCTAssertEqual(address6.e164, pn_b)

        let address7 = SignalServiceAddress(
            serviceId: aci,
            phoneNumber: nil,
            cache: cache,
            cachePolicy: .ignoreCache
        )
        let address8 = SignalServiceAddress(
            serviceId: aci,
            phoneNumber: pn_a.stringValue,
            cache: cache,
            cachePolicy: .ignoreCache
        )
        let address9 = SignalServiceAddress(
            serviceId: aci,
            phoneNumber: pn_b.stringValue,
            cache: cache,
            cachePolicy: .ignoreCache
        )

        XCTAssertEqual(address7.e164, nil)
        XCTAssertEqual(address8.e164, pn_a)
        XCTAssertEqual(address9.e164, pn_b)

        cache.updateRecipient(SignalRecipient(serviceId: aci, phoneNumber: pn_b))

        XCTAssertEqual(address1.e164, pn_b)
        XCTAssertEqual(address2.e164, pn_b)
        XCTAssertEqual(address3.e164, pn_b)
        XCTAssertEqual(address4.e164, pn_b)
        XCTAssertEqual(address5.e164, pn_b)
        XCTAssertEqual(address6.e164, pn_b)
        XCTAssertEqual(address7.e164, nil)
        XCTAssertEqual(address8.e164, pn_a)
        XCTAssertEqual(address9.e164, pn_b)
    }

    func testInitializerPerformance() {
        let iterations = 15_000

        let serviceId = Aci.constantForTesting("00000000-0000-4000-8000-00000000000A")
        let phoneNumber = E164("+16505550101")!

        cache.updateRecipient(SignalRecipient(serviceId: serviceId, phoneNumber: phoneNumber))

        var addresses = [SignalServiceAddress]()
        addresses.reserveCapacity(iterations)

        for _ in 0..<iterations {
            addresses.append(SignalServiceAddress(
                serviceId: serviceId,
                phoneNumber: phoneNumber.stringValue,
                cache: cache,
                cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
            ))
        }

        XCTAssertEqual(addresses.count, iterations)
    }
}
