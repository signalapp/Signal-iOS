//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
@testable import SignalServiceKit
import XCTest

class SignalServiceAddressTest: SSKBaseTestSwift {
    var cache: SignalServiceAddressCache {
        return Self.signalServiceAddressCache
    }

    func test_isEqualPermissive() {
        let phoneNumber1 = "+13213214321"
        let phoneNumber2 = "+13213214322"
        let uuid1 = UUID()
        let uuid2 = UUID()

        // Double match
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                       SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1))

        // Single match works, ignores single missing.
        //
        // SignalServiceAddress's getters use a cache to fill in the blanks.
        cache.updateMapping(uuid: uuid1, phoneNumber: phoneNumber1)

        XCTAssertEqual(SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1),
                       SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1))
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1),
                       SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1))
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                       SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1))
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                       SignalServiceAddress(uuid: uuid1))

        // Single match works, ignores double missing.
        XCTAssertEqual(SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1),
                       SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1))
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1),
                       SignalServiceAddress(uuid: uuid1))

        // Ignores phone number when UUIDs match.
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                       SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber2))

        // Match fails if no common value.
        XCTAssertEqual(SignalServiceAddress(uuid: uuid1),
                       SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1))

        // Match fails if either value doesn't match.
        XCTAssertNotEqual(SignalServiceAddress(uuid: uuid1),
                          SignalServiceAddress(uuid: uuid2))
        XCTAssertNotEqual(SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1),
                          SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber2))
        XCTAssertNotEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                          SignalServiceAddress(uuid: uuid2))
        XCTAssertNotEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                          SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber2))
        XCTAssertNotEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                          SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber1))
        XCTAssertNotEqual(SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1),
                          SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2))
    }

    func test_mappingChanges() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = "+13213214321"
        let phoneNumber2 = "+13213214322"
        let phoneNumber3 = "+13213214323"

        autoreleasepool {
            let address1a = SignalServiceAddress(uuid: uuid1, phoneNumber: nil)
            let address1b = SignalServiceAddress(uuid: uuid1, phoneNumber: nil)
            let address1c = SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1)
            let address2a = SignalServiceAddress(uuid: uuid2, phoneNumber: nil)
            let address2b = SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2)

            // We use the "unresolved" accessors unresolvedUuid(), unresolvedPhoneNumber()
            // to avoid filling in the backing values.

            XCTAssertEqual(address1a.unresolvedUuid, uuid1)
            XCTAssertNil(address1a.unresolvedPhoneNumber)
            XCTAssertEqual(address1b.unresolvedUuid, uuid1)
            XCTAssertNil(address1b.unresolvedPhoneNumber)
            XCTAssertEqual(address1c.unresolvedUuid, uuid1)
            XCTAssertEqual(address1c.unresolvedPhoneNumber, phoneNumber1)
            XCTAssertEqual(address2a.unresolvedUuid, uuid2)
            XCTAssertNil(address2a.unresolvedPhoneNumber)
            XCTAssertEqual(address2b.unresolvedUuid, uuid2)
            XCTAssertEqual(address2b.unresolvedPhoneNumber, phoneNumber2)

            Self.signalServiceAddressCache.updateMapping(uuid: uuid1, phoneNumber: phoneNumber1)

            XCTAssertEqual(address1a.unresolvedUuid, uuid1)
            XCTAssertEqual(address1a.unresolvedPhoneNumber, phoneNumber1)
            XCTAssertEqual(address1b.unresolvedUuid, uuid1)
            XCTAssertEqual(address1b.unresolvedPhoneNumber, phoneNumber1)
            XCTAssertEqual(address1c.unresolvedUuid, uuid1)
            XCTAssertEqual(address1c.unresolvedPhoneNumber, phoneNumber1)
            XCTAssertEqual(address2a.unresolvedUuid, uuid2)
            XCTAssertNil(address2a.unresolvedPhoneNumber)
            XCTAssertEqual(address2b.unresolvedUuid, uuid2)
            XCTAssertEqual(address2b.unresolvedPhoneNumber, phoneNumber2)

            Self.signalServiceAddressCache.updateMapping(uuid: uuid1, phoneNumber: phoneNumber3)

            XCTAssertEqual(address1a.unresolvedUuid, uuid1)
            XCTAssertEqual(address1a.unresolvedPhoneNumber, phoneNumber3)
            XCTAssertEqual(address1b.unresolvedUuid, uuid1)
            XCTAssertEqual(address1b.unresolvedPhoneNumber, phoneNumber3)
            XCTAssertEqual(address1c.unresolvedUuid, uuid1)
            XCTAssertEqual(address1c.unresolvedPhoneNumber, phoneNumber3)
            XCTAssertEqual(address2a.unresolvedUuid, uuid2)
            XCTAssertNil(address2a.unresolvedPhoneNumber)
            XCTAssertEqual(address2b.unresolvedUuid, uuid2)
            XCTAssertEqual(address2b.unresolvedPhoneNumber, phoneNumber2)

            // MARK: - Resolved values

            XCTAssertEqual(address1a.uuid, uuid1)
            XCTAssertEqual(address1a.phoneNumber, phoneNumber3)
            XCTAssertEqual(address1b.uuid, uuid1)
            XCTAssertEqual(address1b.phoneNumber, phoneNumber3)
            XCTAssertEqual(address1c.uuid, uuid1)
            XCTAssertEqual(address1c.phoneNumber, phoneNumber3)
            XCTAssertEqual(address2a.uuid, uuid2)
            XCTAssertNil(address2a.phoneNumber)
            XCTAssertEqual(address2b.uuid, uuid2)
            XCTAssertEqual(address2b.phoneNumber, phoneNumber2)
        }
    }

    private static var mockPhoneNumberCounter = AtomicUInt(13333333333)

    private func mockPhoneNumber() -> String {
        // e.g. "+13213214321"
        return "+\(Self.mockPhoneNumberCounter.increment())"
    }

    // A new address "takes" a uuid component a pre-existing address.
    func test_mappingChanges1a() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = mockPhoneNumber()
        let phoneNumber2 = mockPhoneNumber()

        let hash1 = SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1, trustLevel: .high).hash
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        // uuid1, phoneNumber1 -> phoneNumber2
        let hash2 = SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber2, trustLevel: .high).hash

        // There should be hash continuity for uuid1, since the uuid remains the same.
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertNil(SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid1, SignalServiceAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(phoneNumber: phoneNumber2).phoneNumber)

        // uuid2, phoneNumber1
        let hash3 = SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber1, trustLevel: .high).hash

        // There should be hash continuity for uuid2, even though the uuid has changed.
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertEqual(hash2, hash3)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash3, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash3, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid1, SignalServiceAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" a uuid component a pre-existing address.
    func test_mappingChanges1b() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = mockPhoneNumber()
        let phoneNumber2 = mockPhoneNumber()

        let hash1 = SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1, trustLevel: .high).hash
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        // uuid1, phoneNumber1 -> phoneNumber2
        let hash2 = Self.signalServiceAddressCache.updateMapping(uuid: uuid1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for uuid1, since the uuid remains the same.
        XCTAssertEqual(hash1, hash2)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertNil(SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid1, SignalServiceAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(phoneNumber: phoneNumber2).phoneNumber)

        // uuid2, phoneNumber1
        let hash3 = Self.signalServiceAddressCache.updateMapping(uuid: uuid2, phoneNumber: phoneNumber1).hash

        // There should not be hash continuity for uuid2, since the uuid has changed.
        XCTAssertEqual(hash1, hash2)
        XCTAssertNotEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash3, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash3, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid1, SignalServiceAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" a phone number component a pre-existing address.
    func test_mappingChanges2a() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = mockPhoneNumber()
        let phoneNumber2 = mockPhoneNumber()

        let hash1 = SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1, trustLevel: .high).hash
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        // uuid1 -> uuid2, phoneNumber1
        let hash2 = SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber1, trustLevel: .high).hash

        // There should not be hash continuity for uuid2, since the phone number has been transferred between two uuids.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertNil(SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)

        // uuid1, phoneNumber2
        let hash3 = SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber2, trustLevel: .high).hash

        // There should be hash continuity for uuid1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid1, SignalServiceAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" a phone number component a pre-existing address.
    func test_mappingChanges2b() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = mockPhoneNumber()
        let phoneNumber2 = mockPhoneNumber()

        let hash1 = SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1, trustLevel: .high).hash
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        // uuid1 -> uuid2, phoneNumber1
        let hash2 = Self.signalServiceAddressCache.updateMapping(uuid: uuid2, phoneNumber: phoneNumber1).hash

        // There should not be hash continuity for uuid2, since the phone number has been transferred between two uuids.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertNil(SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)

        // uuid1, phoneNumber2
        let hash3 = Self.signalServiceAddressCache.updateMapping(uuid: uuid1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for uuid1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid1, SignalServiceAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "combines" 2 pre-existing addresses.
    func test_mappingChanges3a() {
        let uuid1 = UUID()
        let phoneNumber1 = mockPhoneNumber()

        let hash1 = SignalServiceAddress(uuid: uuid1, phoneNumber: nil, trustLevel: .high).hash
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)

        let hash2 = SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1, trustLevel: .high).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        // Associate uuid1, phoneNumber1
        let hash3 = SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1, trustLevel: .high).hash

        // There should be hash continuity for the uuid, not the phone number.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid1, SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)
    }

    // A new address "combines" 2 pre-existing addresses.
    func test_mappingChanges3b() {
        let uuid1 = UUID()
        let phoneNumber1 = mockPhoneNumber()

        let hash1 = SignalServiceAddress(uuid: uuid1, phoneNumber: nil, trustLevel: .high).hash
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)

        let hash2 = SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1, trustLevel: .high).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        // Associate uuid1, phoneNumber1
        let hash3 = Self.signalServiceAddressCache.updateMapping(uuid: uuid1, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for the uuid, not the phone number.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid1, SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)
    }

    // A new address "takes" 1 component each from 2 pre-existing addresses.
    func test_mappingChanges4a() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = mockPhoneNumber()
        let phoneNumber2 = mockPhoneNumber()

        let hash1 = SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1, trustLevel: .high).hash
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        let hash2 = SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2, trustLevel: .high).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        // Associate uuid1, phoneNumber2
        let hash3 = SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber2, trustLevel: .high).hash

        // There should be hash continuity for uuid1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertNil(SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(uuid: uuid2).uuid)
        XCTAssertNil(SignalServiceAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid1, SignalServiceAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component each from 2 pre-existing addresses.
    func test_mappingChanges4b() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = mockPhoneNumber()
        let phoneNumber2 = mockPhoneNumber()

        let hash1 = SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1, trustLevel: .high).hash
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        let hash2 = SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2, trustLevel: .high).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        // Associate uuid1, phoneNumber2
        let hash3 = Self.signalServiceAddressCache.updateMapping(uuid: uuid1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for uuid1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertNil(SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(uuid: uuid2).uuid)
        XCTAssertNil(SignalServiceAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid1, SignalServiceAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component from a pre-existing address for a pre-existing uuid.
    func test_mappingChanges5a() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber2 = mockPhoneNumber()

        let hash1 = SignalServiceAddress(uuid: uuid1, phoneNumber: nil, trustLevel: .high).hash
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)

        let hash2 = SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2, trustLevel: .high).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        // Associate uuid1, phoneNumber2
        let hash3 = SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber2, trustLevel: .high).hash

        // There should be hash continuity for uuid1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(uuid: uuid2).uuid)
        XCTAssertNil(SignalServiceAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid1, SignalServiceAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component from a pre-existing address for a pre-existing uuid.
    func test_mappingChanges5b() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber2 = mockPhoneNumber()

        let hash1 = SignalServiceAddress(uuid: uuid1, phoneNumber: nil, trustLevel: .high).hash
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)

        let hash2 = SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2, trustLevel: .high).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        // Associate uuid1, phoneNumber2
        let hash3 = Self.signalServiceAddressCache.updateMapping(uuid: uuid1, phoneNumber: phoneNumber2).hash

        // There should be hash continuity for uuid1.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash1, hash3)
        XCTAssertNotEqual(hash2, hash3)
        XCTAssertEqual(hash1, SignalServiceAddress(uuid: uuid1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid1, SignalServiceAddress(uuid: uuid1).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(uuid: uuid1).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(uuid: uuid2).uuid)
        XCTAssertNil(SignalServiceAddress(uuid: uuid2).phoneNumber)
        XCTAssertEqual(uuid1, SignalServiceAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component from a pre-existing address for a pre-existing phone number.
    func test_mappingChanges6a() {
        let uuid2 = UUID()
        let phoneNumber1 = mockPhoneNumber()
        let phoneNumber2 = mockPhoneNumber()

        let hash1 = SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1, trustLevel: .high).hash
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        let hash2 = SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2, trustLevel: .high).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        // Associate uuid1, phoneNumber2
        let hash3 = SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber1, trustLevel: .high).hash

        // There should be hash continuity for uuid2.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertNotEqual(hash1, hash3)
        XCTAssertEqual(hash2, hash3)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertNotEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid2, SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(uuid: uuid2).phoneNumber)
        XCTAssertNil(SignalServiceAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    // A new address "takes" 1 component from a pre-existing address for a pre-existing phone number.
    func test_mappingChanges6b() {
        let uuid2 = UUID()
        let phoneNumber1 = mockPhoneNumber()
        let phoneNumber2 = mockPhoneNumber()

        let hash1 = SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1, trustLevel: .high).hash
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)

        let hash2 = SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2, trustLevel: .high).hash

        // There should not be hash continuity; the two addresses have nothing in common.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        // Associate uuid1, phoneNumber2
        let hash3 = Self.signalServiceAddressCache.updateMapping(uuid: uuid2, phoneNumber: phoneNumber1).hash

        // There should be hash continuity for uuid2.
        XCTAssertNotEqual(hash1, hash2)
        XCTAssertNotEqual(hash1, hash3)
        XCTAssertEqual(hash2, hash3)
        XCTAssertEqual(hash2, SignalServiceAddress(phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash2, SignalServiceAddress(uuid: uuid2).hash)
        XCTAssertNotEqual(hash1, SignalServiceAddress(phoneNumber: phoneNumber2).hash)

        XCTAssertEqual(uuid2, SignalServiceAddress(phoneNumber: phoneNumber1).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(phoneNumber: phoneNumber1).phoneNumber)
        XCTAssertEqual(uuid2, SignalServiceAddress(uuid: uuid2).uuid)
        XCTAssertEqual(phoneNumber1, SignalServiceAddress(uuid: uuid2).phoneNumber)
        XCTAssertNil(SignalServiceAddress(phoneNumber: phoneNumber2).uuid)
        XCTAssertEqual(phoneNumber2, SignalServiceAddress(phoneNumber: phoneNumber2).phoneNumber)
    }

    func test_hashStability1() {
        let uuid1 = UUID()
        let uuid2 = UUID()
        let phoneNumber1 = mockPhoneNumber()
        let phoneNumber2 = mockPhoneNumber()

        let hash_u1 = SignalServiceAddress(uuid: uuid1, phoneNumber: nil).hash
        XCTAssertEqual(hash_u1, SignalServiceAddress(uuid: uuid1, phoneNumber: nil).hash)

        XCTAssertEqual(hash_u1, SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1, trustLevel: .low).hash)
        // hash_u1 is now also associated with p1.
        XCTAssertEqual(hash_u1, SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1, trustLevel: .high).hash)
        XCTAssertEqual(hash_u1, SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1).hash)

        let hash_u2 = SignalServiceAddress(uuid: uuid2, phoneNumber: nil).hash
        XCTAssertEqual(hash_u2, SignalServiceAddress(uuid: uuid2, phoneNumber: nil).hash)
        XCTAssertNotEqual(hash_u2, hash_u1)

        // hash_u2 is now also associated with p2.
        XCTAssertEqual(hash_u2, SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2, trustLevel: .low).hash)
        XCTAssertEqual(hash_u2, SignalServiceAddress(uuid: uuid2, phoneNumber: phoneNumber2, trustLevel: .high).hash)
        XCTAssertEqual(hash_u2, SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber2).hash)

        // We now re-map p2 to u1.
        XCTAssertEqual(hash_u1, SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber2, trustLevel: .low).hash)
        XCTAssertEqual(hash_u1, SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber2, trustLevel: .high).hash)
        XCTAssertEqual(hash_u1, SignalServiceAddress(uuid: uuid1, phoneNumber: nil).hash)
        XCTAssertEqual(hash_u2, SignalServiceAddress(uuid: uuid2, phoneNumber: nil).hash)
        XCTAssertEqual(hash_u1, SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1).hash)
        XCTAssertEqual(hash_u1, SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber2).hash)
    }

    func test_hashStability2() {
        let uuid1 = UUID()
        let phoneNumber1 = mockPhoneNumber()

        let hash_u1 = SignalServiceAddress(uuid: uuid1, phoneNumber: nil).hash
        XCTAssertEqual(hash_u1, SignalServiceAddress(uuid: uuid1, phoneNumber: nil).hash)

        let hash_p1 = SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1).hash
        XCTAssertEqual(hash_p1, SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1).hash)
        XCTAssertNotEqual(hash_u1, hash_p1)

        let address_u1 = SignalServiceAddress(uuid: uuid1, phoneNumber: nil)
        let address_p1 = SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1)

        // We now map p1 to u1.
        XCTAssertEqual(hash_u1, SignalServiceAddress(uuid: uuid1, phoneNumber: phoneNumber1, trustLevel: .high).hash)
        XCTAssertEqual(hash_u1, SignalServiceAddress(uuid: uuid1, phoneNumber: nil).hash)
        XCTAssertEqual(hash_u1, SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1).hash)

        // New u1 addresses are equal to old u1 addresses and have the same hash.
        XCTAssertEqual(address_u1, SignalServiceAddress(uuid: uuid1, phoneNumber: nil))
        XCTAssertEqual(address_u1.hash, SignalServiceAddress(uuid: uuid1, phoneNumber: nil).hash)

        // New p1 addresses are equal to old p1 addresses BUT DO NOT have the same hash.
        // This degenerate case is unfortunately unavoidable without large changes where
        // the cure is probably worse than the disease.
        XCTAssertEqual(address_p1, SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1))
        XCTAssertNotEqual(address_p1.hash, SignalServiceAddress(uuid: nil, phoneNumber: phoneNumber1).hash)
    }
}
