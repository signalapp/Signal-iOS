//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

final class AppExpiryTest: XCTestCase {
    private var appVersion: AppVersionNumber4!
    private var buildDate: Date!
    private var db: (any DB)!
    private var keyValueStore: KeyValueStore!

    private var appExpiry: AppExpiry!

    private var defaultExpiry: Date { buildDate.addingTimeInterval(90 * .day) }

    private func loadPersistedExpirationDate() -> Date {
        let newAppExpiry = AppExpiry(appVersion: appVersion, buildDate: buildDate)
        db.read { newAppExpiry.warmCaches(with: $0) }
        return newAppExpiry.expirationDate
    }

    override func setUp() {
        appVersion = try! AppVersionNumber4(AppVersionNumber("1.2.3.4"))
        buildDate = Date()
        db = InMemoryDB()
        keyValueStore = KeyValueStore(
            collection: AppExpiry.keyValueCollection,
        )

        appExpiry = AppExpiry(appVersion: appVersion, buildDate: buildDate)
    }

    func testDefaultExpiry() {
        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)

        XCTAssertFalse(appExpiry.isExpired(now: buildDate))
        XCTAssertFalse(appExpiry.isExpired(now: defaultExpiry))
        XCTAssertTrue(appExpiry.isExpired(now: defaultExpiry.addingTimeInterval(1)))
    }

    func testWarmCachesWithInvalidDataInDatabase() throws {
        let data = Data([1, 2, 3])
        db.write { tx in
            keyValueStore.setData(data, key: AppExpiry.keyValueKey, transaction: tx)
        }

        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)
    }

    func testWarmCachesWithNothingPersisted() {
        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)
    }

    func testWarmCachesIgnoresPersistedValueWithDifferentVersion() {
        let savedJson = #"{"appVersion":"6.5.4.3","mode":"immediately"}"#.data(using: .utf8)!
        db.write { tx in
            keyValueStore.setData(savedJson, key: AppExpiry.keyValueKey, transaction: tx)
        }

        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)
    }

    func testWarmCachesIgnoresPersistedValueWithOldKeyName() throws {
        let savedJson = #"{"version4":"6.5.4.3","mode":"immediately"}"#.data(using: .utf8)!
        db.write { tx in
            keyValueStore.setData(savedJson, key: AppExpiry.keyValueKey, transaction: tx)
        }

        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)
    }

    func testWarmCachesWithPersistedDefault() throws {
        let savedJson = try JSONEncoder().encode([
            "appVersion": appVersion.wrappedValue.rawValue,
            "mode": "default",
        ])
        db.write { tx in
            keyValueStore.setData(savedJson, key: AppExpiry.keyValueKey, transaction: tx)
        }

        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)
    }

    func testWarmCachesWithPersistedImmediateExpiry() throws {
        let savedJson = try JSONEncoder().encode([
            "appVersion": appVersion.wrappedValue.rawValue,
            "mode": "immediately",
        ])
        db.write { tx in
            keyValueStore.setData(savedJson, key: AppExpiry.keyValueKey, transaction: tx)
        }

        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, .distantPast)
    }

    func testWarmCachesWithPersistedExpirationDate() {
        let expirationDate = defaultExpiry.addingTimeInterval(-1234)

        let savedJson = """
        {
            "appVersion": "\(appVersion.wrappedValue.rawValue)",
            "mode": "atDate",
            "expirationDate": \(expirationDate.timeIntervalSinceReferenceDate)
        }
        """.data(using: .utf8)!
        db.write { tx in
            keyValueStore.setData(savedJson, key: AppExpiry.keyValueKey, transaction: tx)
        }

        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, expirationDate)
    }

    func testSetHasAppExpiredAtCurrentVersion() async {
        await appExpiry.setHasAppExpiredAtCurrentVersion(db: db)

        XCTAssertEqual(appExpiry.expirationDate, .distantPast)
        XCTAssertTrue(appExpiry.isExpired(now: buildDate))

        XCTAssertEqual(loadPersistedExpirationDate(), .distantPast)
    }

    func testClearingExpirationDateForCurrentVersion() async {
        await appExpiry.setExpirationDateForCurrentVersion(nil, now: buildDate, db: db)

        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)
        XCTAssertFalse(appExpiry.isExpired(now: buildDate))

        XCTAssertEqual(loadPersistedExpirationDate(), defaultExpiry)
    }

    func testSetHasExpirationDateForCurrentVersion() async {
        let expirationDate = defaultExpiry.addingTimeInterval(-1234)

        await appExpiry.setExpirationDateForCurrentVersion(expirationDate, now: buildDate, db: db)

        XCTAssertEqual(appExpiry.expirationDate, expirationDate)

        XCTAssertEqual(loadPersistedExpirationDate(), expirationDate)
    }
}
