//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
import GRDB
@testable import SignalServiceKit

final class UsernameLookupRecordTest: XCTestCase {
    private var inMemoryDatabase: InMemoryDatabase!

    override func setUp() {
        inMemoryDatabase = InMemoryDatabase()
    }

    func testRoundTrip() throws {
        for (idx, (constant, _)) in UsernameLookupRecord.constants.enumerated() {
            inMemoryDatabase.write { db in
                try constant.insert(db)
            }

            let deserialized = inMemoryDatabase.read { db in
                return UsernameLookupRecord.fetchOne(
                    forAci: constant.aci,
                    database: db
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

            inMemoryDatabase.write { db in
                UsernameLookupRecord.deleteOne(forAci: constant.aci, database: db)
            }

            XCTAssertNil(inMemoryDatabase.read { db in
                return UsernameLookupRecord.fetchOne(forAci: constant.aci, database: db)
            })
        }
    }

    func testUpsert() throws {
        let aci1 = ServiceId(UUID())
        let aci2 = ServiceId(UUID())
        let username1 = "jango_fett.42"
        let username2 = "boba_fett.42"

        inMemoryDatabase.write { db in
            let recordsToUpsert: [UsernameLookupRecord] = [
                .init(aci: aci1, username: username1),
                .init(aci: aci2, username: username2),
                .init(aci: aci1, username: username2)
            ]

            for record in recordsToUpsert {
                record.upsert(database: db)
            }
        }

        let (record1, record2) = inMemoryDatabase.read { db in
            (
                UsernameLookupRecord.fetchOne(forAci: aci1, database: db),
                UsernameLookupRecord.fetchOne(forAci: aci2, database: db)
            )
        }

        guard let record1, let record2 else {
            XCTFail("Missing records!")
            return
        }

        XCTAssertEqual(record1.aci, aci1)
        XCTAssertEqual(record1.username, username2)

        XCTAssertEqual(record2.aci, aci2)
        XCTAssertEqual(record2.username, username2)
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
    static var constants: [(UsernameLookupRecord, base64JsonData: Data)] = [
        (
            UsernameLookupRecord(aci: ServiceId(uuidString: "effc880f-8b41-4985-9bf6-3c4f0231a959")!, username: "boba_fett.42"),
            Data(base64Encoded: "eyJhY2kiOiJFRkZDODgwRi04QjQxLTQ5ODUtOUJGNi0zQzRGMDIzMUE5NTkiLCJ1c2VybmFtZSI6ImJvYmFfZmV0dC40MiJ9")!
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
