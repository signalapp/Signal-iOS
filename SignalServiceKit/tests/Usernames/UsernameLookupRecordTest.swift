//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class UsernameLookupRecordTest: XCTestCase {
    private var inMemoryDB: InMemoryDB!

    override func setUp() {
        super.setUp()
        inMemoryDB = InMemoryDB()
    }

    func testRoundTrip() throws {
        let store = UsernameLookupRecordStoreImpl()
        for (idx, (constant, _)) in UsernameLookupRecord.constants.enumerated() {
            inMemoryDB.insert(record: constant)

            let deserialized = inMemoryDB.read { tx in
                return store.fetchOne(
                    forAci: Aci(fromUUID: constant.aci),
                    tx: tx
                )
            }

            guard let deserialized else {
                XCTFail("Failed to fetch constant \(idx)!")
                continue
            }

            do {
                try deserialized.validate(against: constant)
            } catch ValidatableModelError.failedToValidate {
                XCTFail("Failed to validate constant \(idx)!")
            } catch {
                XCTFail("Unexpected error while validating constant \(idx)!")
            }

            inMemoryDB.write { tx in
                store.deleteOne(
                    forAci: Aci(fromUUID: constant.aci),
                    tx: tx
                )
            }

            XCTAssertNil(inMemoryDB.read { tx in
                return store.fetchOne(
                    forAci: Aci(fromUUID: constant.aci),
                    tx: tx
                )
            })
        }
    }

    // MARK: - Hardcoded constant data

    enum HardcodedDataTestMode {
        case runTest
        case printStrings

        /// Toggle this to use ``testHardcodedJsonDataDecodes()`` to print
        /// hardcoded strings, for example when adding new constants.
        static let mode: Self = .runTest
    }

    func testHardcodedJsonDataDecodes() {
        switch HardcodedDataTestMode.mode {
        case .printStrings:
            UsernameLookupRecord.printHardcodedJsonDataForConstants()
        case .runTest:
            for (idx, (constant, jsonData)) in UsernameLookupRecord.constants.enumerated() {
                do {
                    let decoded = try JSONDecoder().decode(UsernameLookupRecord.self, from: jsonData)
                    try constant.validate(against: decoded)
                } catch let error where error is DecodingError {
                    XCTFail("Failed to decode JSON model for constant \(idx): \(error)")
                } catch ValidatableModelError.failedToValidate {
                    XCTFail("Failed to validate JSON-decoded model for constant \(idx)")
                } catch {
                    XCTFail("Unexpected error for constant \(idx)")
                }
            }
        }
    }
}

extension UsernameLookupRecord: ValidatableModel {
    static var constants: [(UsernameLookupRecord, jsonData: Data)] = [
        (
            UsernameLookupRecord(aci: Aci.constantForTesting("effc880f-8b41-4985-9bf6-3c4f0231a959"), username: "boba_fett.42"),
            Data(#"{"aci":"EFFC880F-8B41-4985-9BF6-3C4F0231A959","username":"boba_fett.42"}"#.utf8)
        )
    ]

    func validate(against: UsernameLookupRecord) throws {
        guard
            aci == against.aci,
            username == against.username
        else {
            throw ValidatableModelError.failedToValidate
        }
    }
}
