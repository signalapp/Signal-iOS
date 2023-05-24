//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

class SignalServiceAddressTest: XCTestCase {

    private lazy var cache = SignalServiceAddressCache()

    private func makeAddress(uuid: UUID? = nil, phoneNumber: String? = nil) -> SignalServiceAddress {
        SignalServiceAddress(
            uuid: uuid,
            phoneNumber: phoneNumber,
            cache: cache,
            cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
        )
    }

    private func makeHighTrustAddress(uuid: UUID? = nil, phoneNumber: String? = nil) -> SignalServiceAddress {
        cache.updateRecipient(SignalRecipient(serviceId: uuid.map { ServiceId($0) }, phoneNumber: phoneNumber.flatMap { E164($0) }))
        return makeAddress(uuid: uuid, phoneNumber: phoneNumber)
    }

    @discardableResult
    private func updateMapping(uuid: UUID, phoneNumber: String? = nil) -> SignalServiceAddress {
        return makeHighTrustAddress(uuid: uuid, phoneNumber: phoneNumber)
    }

    func test_isEqualPermissive() {
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"
        let uuid1 = UUID()
        let uuid2 = UUID()

        // Double match
        XCTAssertEqual(
            makeAddress(uuid: uuid1, phoneNumber: phoneNumber1),
            makeAddress(uuid: uuid1, phoneNumber: phoneNumber1)
        )

        updateMapping(uuid: uuid1, phoneNumber: phoneNumber1)

        // Single match works, ignores single missing.
        XCTAssertEqual(
            makeAddress(uuid: nil, phoneNumber: phoneNumber1),
            makeAddress(uuid: uuid1, phoneNumber: phoneNumber1)
        )
        XCTAssertEqual(
            makeAddress(uuid: uuid1),
            makeAddress(uuid: uuid1, phoneNumber: phoneNumber1)
        )
        XCTAssertEqual(
            makeAddress(uuid: uuid1, phoneNumber: phoneNumber1),
            makeAddress(uuid: nil, phoneNumber: phoneNumber1)
        )
        XCTAssertEqual(
            makeAddress(uuid: uuid1, phoneNumber: phoneNumber1),
            makeAddress(uuid: uuid1)
        )

        // Single match works, ignores double missing.
        XCTAssertEqual(
            makeAddress(uuid: nil, phoneNumber: phoneNumber1),
            makeAddress(uuid: nil, phoneNumber: phoneNumber1)
        )
        XCTAssertEqual(
            makeAddress(uuid: uuid1),
            makeAddress(uuid: uuid1)
        )

        // Ignores phone number when UUIDs match.
        XCTAssertEqual(
            makeAddress(uuid: uuid1, phoneNumber: phoneNumber1),
            makeAddress(uuid: uuid1, phoneNumber: phoneNumber2)
        )

        // Match fails if no common value.
        XCTAssertEqual(
            makeAddress(uuid: uuid1),
            makeAddress(uuid: nil, phoneNumber: phoneNumber1)
        )

        // Match fails if either value doesn't match.
        XCTAssertNotEqual(
            makeAddress(uuid: uuid1),
            makeAddress(uuid: uuid2)
        )
        XCTAssertNotEqual(
            makeAddress(uuid: nil, phoneNumber: phoneNumber1),
            makeAddress(uuid: nil, phoneNumber: phoneNumber2)
        )
        XCTAssertNotEqual(
            makeAddress(uuid: uuid1, phoneNumber: phoneNumber1),
            makeAddress(uuid: uuid2)
        )
        XCTAssertNotEqual(
            makeAddress(uuid: uuid1, phoneNumber: phoneNumber1),
            makeAddress(uuid: nil, phoneNumber: phoneNumber2)
        )
        XCTAssertNotEqual(
            makeAddress(uuid: uuid1, phoneNumber: phoneNumber1),
            makeAddress(uuid: uuid2, phoneNumber: phoneNumber1)
        )
        XCTAssertNotEqual(
            makeAddress(uuid: uuid1, phoneNumber: phoneNumber1),
            makeAddress(uuid: uuid2, phoneNumber: phoneNumber2)
        )
    }

    func test_mappingChanges() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"
        let phoneNumber3 = "+16505550102"

        let address1a = makeAddress(uuid: uuid1, phoneNumber: nil)
        let address1b = makeAddress(uuid: uuid1, phoneNumber: nil)
        let address1c = makeAddress(uuid: uuid1, phoneNumber: phoneNumber1)
        let address1d = makeAddress(uuid: nil, phoneNumber: phoneNumber1)
        let address2a = makeAddress(uuid: uuid2, phoneNumber: nil)
        let address2b = makeAddress(uuid: uuid2, phoneNumber: phoneNumber2)
        let address3a = makeAddress(uuid: nil, phoneNumber: phoneNumber3)

        // Make sure nothing has been resolved about these addresses other than
        // what was explicitly provided as part of the initializer.

        XCTAssertEqual(address1a.uuid, uuid1)
        XCTAssertNil(address1a.phoneNumber)
        XCTAssertEqual(address1b.uuid, uuid1)
        XCTAssertNil(address1b.phoneNumber)
        XCTAssertEqual(address1c.uuid, uuid1)
        XCTAssertEqual(address1c.phoneNumber, phoneNumber1)
        XCTAssertNil(address1d.uuid)
        XCTAssertEqual(address1d.phoneNumber, phoneNumber1)
        XCTAssertEqual(address2a.uuid, uuid2)
        XCTAssertNil(address2a.phoneNumber)
        XCTAssertEqual(address2b.uuid, uuid2)
        XCTAssertEqual(address2b.phoneNumber, phoneNumber2)
        XCTAssertNil(address3a.uuid)
        XCTAssertEqual(address3a.phoneNumber, phoneNumber3)

        // High-trust with phoneNumber1.

        updateMapping(uuid: uuid1, phoneNumber: phoneNumber1)

        XCTAssertEqual(address1a.uuid, uuid1)
        XCTAssertEqual(address1a.phoneNumber, phoneNumber1)
        XCTAssertEqual(address1b.uuid, uuid1)
        XCTAssertEqual(address1b.phoneNumber, phoneNumber1)
        XCTAssertEqual(address1c.uuid, uuid1)
        XCTAssertEqual(address1c.phoneNumber, phoneNumber1)
        XCTAssertEqual(address1d.uuid, uuid1)
        XCTAssertEqual(address1d.phoneNumber, phoneNumber1)
        XCTAssertEqual(address2a.uuid, uuid2)
        XCTAssertNil(address2a.phoneNumber)
        XCTAssertEqual(address2b.uuid, uuid2)
        XCTAssertEqual(address2b.phoneNumber, phoneNumber2)
        XCTAssertNil(address3a.uuid)
        XCTAssertEqual(address3a.phoneNumber, phoneNumber3)

        // High-trust with phoneNumber3.

        updateMapping(uuid: uuid1, phoneNumber: phoneNumber3)

        XCTAssertEqual(address1a.uuid, uuid1)
        XCTAssertEqual(address1a.phoneNumber, phoneNumber3)
        XCTAssertEqual(address1b.uuid, uuid1)
        XCTAssertEqual(address1b.phoneNumber, phoneNumber3)
        XCTAssertEqual(address1c.uuid, uuid1)
        XCTAssertEqual(address1c.phoneNumber, phoneNumber3)
        XCTAssertEqual(address1d.uuid, uuid1)
        XCTAssertEqual(address1d.phoneNumber, phoneNumber3)
        XCTAssertEqual(address2a.uuid, uuid2)
        XCTAssertNil(address2a.phoneNumber)
        XCTAssertEqual(address2b.uuid, uuid2)
        XCTAssertEqual(address2b.phoneNumber, phoneNumber2)
        XCTAssertEqual(address3a.uuid, uuid1)
        XCTAssertEqual(address3a.phoneNumber, phoneNumber3)
    }

    // A new address "takes" a uuid component a pre-existing address.
    func test_mappingChanges1a() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        // uuid1, phoneNumber1 -> phoneNumber2
        let hash2 = makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for uuid1, since the uuid remains the same.
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertNil(makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid1, makeAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)

        // uuid2, phoneNumber1
        let hash3 = makeHighTrustAddress(uuid: uuid2, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for uuid2, even though the uuid has changed.
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertEqual(hash2, hash3)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash3, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash3, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid1, makeAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" a uuid component a pre-existing address.
    func test_mappingChanges1b() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        // uuid1, phoneNumber1 -> phoneNumber2
        let hash2 = updateMapping(uuid: uuid1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for uuid1, since the uuid remains the same.
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertNil(makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid1, makeAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)

        // uuid2, phoneNumber1
        let hash3 = updateMapping(uuid: uuid2, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for uuid2, even though the uuid has changed.
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertEqual(hash2, hash3)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash3, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash3, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid1, makeAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" a phone number component a pre-existing address.
    func test_mappingChanges2a() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        // uuid1 -> uuid2, phoneNumber1
        _ = makeAddress(uuid: uuid2)
        let hash2 = makeHighTrustAddress(uuid: uuid2, phoneNumber: phoneNumber1).hash

        // There should not be hash continuity for uuid2 since the phone number was
        // transferred to a UUID that already existed.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertNil(makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)

        // uuid1, phoneNumber2
        let hash3 = makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for uuid1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid1, makeAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" a phone number component a pre-existing address.
    func test_mappingChanges2b() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        // uuid1 -> uuid2, phoneNumber1
        _ = makeAddress(uuid: uuid2)
        let hash2 = updateMapping(uuid: uuid2, phoneNumber: phoneNumber1).hash

        // There should not be hash continuity for uuid2 since the phone number was
        // transferred to a UUID that already existed.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertNil(makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)

        // uuid1, phoneNumber2
        let hash3 = updateMapping(uuid: uuid1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for uuid1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid1, makeAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "combines" 2 pre-existing addresses.
    func test_mappingChanges3a() {
        let uuid1 = UUID()
        let phoneNumber1 = "+16505550100"

        let hash1 = makeHighTrustAddress(uuid: uuid1, phoneNumber: nil).hash
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)

        let hash2 = makeHighTrustAddress(uuid: nil, phoneNumber: phoneNumber1).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)

        // Associate uuid1, phoneNumber1
        let hash3 = makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for the uuid, not the phone number.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid1, makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
    }

    // A new address "combines" 2 pre-existing addresses.
    func test_mappingChanges3b() {
        let uuid1 = UUID()
        let phoneNumber1 = "+16505550100"

        let hash1 = makeHighTrustAddress(uuid: uuid1, phoneNumber: nil).hash
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)

        let hash2 = makeHighTrustAddress(uuid: nil, phoneNumber: phoneNumber1).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)

        // Associate uuid1, phoneNumber1
        let hash3 = updateMapping(uuid: uuid1, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for the uuid, not the phone number.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid1, makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
    }

    // A new address "takes" 1 component each from 2 pre-existing addresses.
    func test_mappingChanges4a() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        let hash2 = makeHighTrustAddress(uuid: uuid2, phoneNumber: phoneNumber2).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        // Associate uuid1, phoneNumber2
        let hash3 = makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for uuid1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertNil(makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(uuid: uuid2).uuid)
        XCTAssertNil(makeAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid1, makeAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component each from 2 pre-existing addresses.
    func test_mappingChanges4b() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        let hash2 = makeHighTrustAddress(uuid: uuid2, phoneNumber: phoneNumber2).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        // Associate uuid1, phoneNumber2
        let hash3 = updateMapping(uuid: uuid1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for uuid1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertNil(makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(uuid: uuid2).uuid)
        XCTAssertNil(makeAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid1, makeAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component from a pre-existing address for a pre-existing uuid.
    func test_mappingChanges5a() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(uuid: uuid1, phoneNumber: nil).hash
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)

        let hash2 = makeHighTrustAddress(uuid: uuid2, phoneNumber: phoneNumber2).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        // Associate uuid1, phoneNumber2
        let hash3 = makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for uuid1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(uuid: uuid2).uuid)
        XCTAssertNil(makeAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid1, makeAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component from a pre-existing address for a pre-existing uuid.
    func test_mappingChanges5b() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(uuid: uuid1, phoneNumber: nil).hash
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)

        let hash2 = makeHighTrustAddress(uuid: uuid2, phoneNumber: phoneNumber2).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        // Associate uuid1, phoneNumber2
        let hash3 = updateMapping(uuid: uuid1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for uuid1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, makeAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, makeAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(uuid: uuid2).uuid)
        XCTAssertNil(makeAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid1, makeAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component from a pre-existing address for a pre-existing phone number.
    func test_mappingChanges6a() {
        let uuid2 = UUID()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(uuid: nil, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        let hash2 = makeHighTrustAddress(uuid: uuid2, phoneNumber: phoneNumber2).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        // Associate uuid2, phoneNumber1
        let hash3 = makeHighTrustAddress(uuid: uuid2, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for uuid2.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertNotEqual(hash1, hash3)
        XCTAssertEqual(hash2, hash3)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertNotEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid2, makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(uuid: uuid2).phoneNumber)
        XCTAssertNil(makeAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component from a pre-existing address for a pre-existing phone number.
    func test_mappingChanges6b() {
        let uuid2 = UUID()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash1 = makeHighTrustAddress(uuid: nil, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)

        let hash2 = makeHighTrustAddress(uuid: uuid2, phoneNumber: phoneNumber2).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash1, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber2).hash)

        // Associate uuid2, phoneNumber1
        let hash3 = updateMapping(uuid: uuid2, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for uuid2.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertNotEqual(hash1, hash3)
        XCTAssertEqual(hash2, hash3)
        XCTAssertEqual(hash2, makeAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, makeAddress(uuid: uuid2).hash)
        XCTAssertNotEqual(hash1, makeAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid2, makeAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid2, makeAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, makeAddress(uuid: uuid2).phoneNumber)
        XCTAssertNil(makeAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, makeAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    func test_hashStability1() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = "+16505550100"
        let phoneNumber2 = "+16505550101"

        let hash_u1 = makeAddress(uuid: uuid1, phoneNumber: nil).hash
        XCTAssertEqual(hash_u1, makeAddress(uuid: uuid1, phoneNumber: nil).hash)

        XCTAssertEqual(hash_u1, makeAddress(uuid: uuid1, phoneNumber: phoneNumber1).hash)
        // hash_u1 is now also associated with p1.
        XCTAssertEqual(hash_u1, makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash_u1, makeAddress(uuid: nil, phoneNumber: phoneNumber1).hash)

        let hash_u2 = makeAddress(uuid: uuid2, phoneNumber: nil).hash
        XCTAssertEqual(hash_u2, makeAddress(uuid: uuid2, phoneNumber: nil).hash)
        XCTAssertNotEqual(hash_u2, hash_u1)

        // hash_u2 is now also associated with p2.
        XCTAssertEqual(hash_u2, makeAddress(uuid: uuid2, phoneNumber: phoneNumber2).hash)
        XCTAssertEqual(hash_u2, makeHighTrustAddress(uuid: uuid2, phoneNumber: phoneNumber2).hash)
        XCTAssertEqual(hash_u2, makeAddress(uuid: nil, phoneNumber: phoneNumber2).hash)

        // We now re-map p2 to u1.
        XCTAssertEqual(hash_u1, makeAddress(uuid: uuid1, phoneNumber: phoneNumber2).hash)
        XCTAssertEqual(hash_u1, makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber2).hash)
        XCTAssertEqual(hash_u1, makeAddress(uuid: uuid1, phoneNumber: nil).hash)
        XCTAssertEqual(hash_u2, makeAddress(uuid: uuid2, phoneNumber: nil).hash)
        XCTAssertEqual(hash_u1, makeAddress(uuid: nil, phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash_u1, makeAddress(uuid: nil, phoneNumber: phoneNumber2).hash)
    }

    func test_hashStability2() {
        let uuid1 = UUID()
        let phoneNumber1 = "+16505550100"

        let hash_u1 = makeAddress(uuid: uuid1, phoneNumber: nil).hash
        XCTAssertEqual(hash_u1, makeAddress(uuid: uuid1, phoneNumber: nil).hash)

        let hash_p1 = makeAddress(uuid: nil, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash_p1, makeAddress(uuid: nil, phoneNumber: phoneNumber1).hash)
        XCTAssertNotEqual(hash_u1, hash_p1)

        let address_u1 = makeAddress(uuid: uuid1, phoneNumber: nil)
        let address_p1 = makeAddress(uuid: nil, phoneNumber: phoneNumber1)

        // We now map p1 to u1.
        XCTAssertEqual(hash_u1, makeHighTrustAddress(uuid: uuid1, phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash_u1, makeAddress(uuid: uuid1, phoneNumber: nil).hash)
        XCTAssertEqual(hash_u1, makeAddress(uuid: nil, phoneNumber: phoneNumber1).hash)

        // New u1 addresses are equal to old u1 addresses and have the same hash.
        XCTAssertEqual(address_u1, makeAddress(uuid: uuid1, phoneNumber: nil))
        XCTAssertEqual(address_u1.hash, makeAddress(uuid: uuid1, phoneNumber: nil).hash)

        // New p1 addresses are equal to old p1 addresses BUT DO NOT have the same hash.
        // This degenerate case is unfortunately unavoidable without large changes where
        // the cure is probably worse than the disease.
        XCTAssertEqual(address_p1, makeAddress(uuid: nil, phoneNumber: phoneNumber1))
        XCTAssertNotEqual(address_p1.hash, makeAddress(uuid: nil, phoneNumber: phoneNumber1).hash)
    }

    func testInitializers() {
        let sid_a = ServiceId(uuidString: "00000000-0000-4000-8000-00000000000A")!
        let pn_a = E164("+16505550101")!
        let pn_b = E164("+16505550102")!

        cache.updateRecipient(SignalRecipient(serviceId: sid_a, phoneNumber: pn_a))

        let address1 = SignalServiceAddress(
            uuid: sid_a.uuidValue,
            phoneNumber: nil,
            cache: cache,
            cachePolicy: .preferCachedPhoneNumberAndListenForUpdates
        )
        let address2 = SignalServiceAddress(
            uuid: sid_a.uuidValue,
            phoneNumber: pn_a.stringValue,
            cache: cache,
            cachePolicy: .preferCachedPhoneNumberAndListenForUpdates
        )
        let address3 = SignalServiceAddress(
            uuid: sid_a.uuidValue,
            phoneNumber: pn_b.stringValue,
            cache: cache,
            cachePolicy: .preferCachedPhoneNumberAndListenForUpdates
        )

        XCTAssertEqual(address1.e164, pn_a)
        XCTAssertEqual(address2.e164, pn_a)
        XCTAssertEqual(address3.e164, pn_a)

        let address4 = SignalServiceAddress(
            uuid: sid_a.uuidValue,
            phoneNumber: nil,
            cache: cache,
            cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
        )
        let address5 = SignalServiceAddress(
            uuid: sid_a.uuidValue,
            phoneNumber: pn_a.stringValue,
            cache: cache,
            cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
        )
        let address6 = SignalServiceAddress(
            uuid: sid_a.uuidValue,
            phoneNumber: pn_b.stringValue,
            cache: cache,
            cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
        )

        XCTAssertEqual(address4.e164, pn_a)
        XCTAssertEqual(address5.e164, pn_a)
        XCTAssertEqual(address6.e164, pn_b)

        let address7 = SignalServiceAddress(
            uuid: sid_a.uuidValue,
            phoneNumber: nil,
            cache: cache,
            cachePolicy: .ignoreCache
        )
        let address8 = SignalServiceAddress(
            uuid: sid_a.uuidValue,
            phoneNumber: pn_a.stringValue,
            cache: cache,
            cachePolicy: .ignoreCache
        )
        let address9 = SignalServiceAddress(
            uuid: sid_a.uuidValue,
            phoneNumber: pn_b.stringValue,
            cache: cache,
            cachePolicy: .ignoreCache
        )

        XCTAssertEqual(address7.e164, nil)
        XCTAssertEqual(address8.e164, pn_a)
        XCTAssertEqual(address9.e164, pn_b)

        cache.updateRecipient(SignalRecipient(serviceId: sid_a, phoneNumber: pn_b))

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

        let serviceId = ServiceId(uuidString: "00000000-0000-4000-8000-00000000000A")!
        let phoneNumber = E164("+16505550101")!

        cache.updateRecipient(SignalRecipient(serviceId: serviceId, phoneNumber: phoneNumber))

        var addresses = [SignalServiceAddress]()
        addresses.reserveCapacity(iterations)

        for _ in 0..<iterations {
            addresses.append(SignalServiceAddress(
                uuid: serviceId.uuidValue,
                phoneNumber: phoneNumber.stringValue,
                cache: cache,
                cachePolicy: .preferInitialPhoneNumberAndListenForUpdates
            ))
        }

        XCTAssertEqual(addresses.count, iterations)
    }
}
