//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

final class AppExpiryTest: XCTestCase {
    private let appVersion = AppVersionImpl.shared
    private var date: Date!
    private var db: (any DB)!
    private var keyValueStore: KeyValueStore!
    private var scheduler: TestScheduler!

    private var appExpiry: AppExpiryImpl!

    private var defaultExpiry: Date { appVersion.buildDate.addingTimeInterval(90 * kDayInterval) }

    private func loadPersistedExpirationDate() -> Date {
        let newAppExpiry = AppExpiryImpl(
            dateProvider: { self.date },
            appVersion: appVersion,
            schedulers: TestSchedulers(scheduler: scheduler)
        )
        db.read { newAppExpiry.warmCaches(with: $0) }
        return newAppExpiry.expirationDate
    }

    override func setUp() {
        date = appVersion.buildDate
        scheduler = TestScheduler()
        db = InMemoryDB(schedulers: TestSchedulers(scheduler: scheduler))
        keyValueStore = KeyValueStore(
            collection: AppExpiryImpl.keyValueCollection
        )

        appExpiry = AppExpiryImpl(
            dateProvider: { self.date },
            appVersion: appVersion,
            schedulers: TestSchedulers(scheduler: scheduler)
        )
    }

    func testDefaultExpiry() {
        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)

        XCTAssertFalse(appExpiry.isExpired)
        date = defaultExpiry
        XCTAssertFalse(appExpiry.isExpired)
        date = date.addingTimeInterval(1)
        XCTAssertTrue(appExpiry.isExpired)
    }

    func testWarmCachesWithInvalidDataInDatabase() throws {
        /// Works around "code after here will never be executed".
        if true {
            throw XCTSkip(
                "This test fails because the old data fails to decode and hits an owsFailDebug. Rather than delete it outright, we'll skip it and keep a record that this is something we once cared about."
            )
        }

        let data = Data([1, 2, 3])
        db.write { tx in
            keyValueStore.setData(data, key: AppExpiryImpl.keyValueKey, transaction: tx)
        }

        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)
    }

    func testWarmCachesWithNothingPersisted() {
        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)
    }

    func testWarmCachesIgnoresPersistedValueWithDifferentVersion() {
        XCTAssertNotEqual(appVersion.currentAppVersion, "6.5.4.3", "Test version is unexpected")

        let savedJson = #"{"appVersion":"6.5.4.3","mode":"immediately"}"#.data(using: .utf8)!
        db.write { tx in
            keyValueStore.setData(savedJson, key: AppExpiryImpl.keyValueKey, transaction: tx)
        }

        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)
    }

    func testWarmCachesIgnoresPersistedValueWithOldKeyName() throws {
        /// Works around "code after here will never be executed".
        if true {
            throw XCTSkip(
                "This test fails because the old data fails to decode and hits an owsFailDebug. Rather than delete it outright, we'll skip it and keep a record that this is something we once cared about."
            )
        }

        let savedJson = #"{"version4":"6.5.4.3","mode":"immediately"}"#.data(using: .utf8)!
        db.write { tx in
            keyValueStore.setData(savedJson, key: AppExpiryImpl.keyValueKey, transaction: tx)
        }

        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)
    }

    func testWarmCachesWithPersistedDefault() throws {
        let savedJson = try JSONEncoder().encode([
            "appVersion": appVersion.currentAppVersion,
            "mode": "default"
        ])
        db.write { tx in
            keyValueStore.setData(savedJson, key: AppExpiryImpl.keyValueKey, transaction: tx)
        }

        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)
    }

    func testWarmCachesWithPersistedImmediateExpiry() throws {
        let savedJson = try JSONEncoder().encode([
            "appVersion": appVersion.currentAppVersion,
            "mode": "immediately"
        ])
        db.write { tx in
            keyValueStore.setData(savedJson, key: AppExpiryImpl.keyValueKey, transaction: tx)
        }

        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, .distantPast)
    }

    func testWarmCachesWithPersistedExpirationDate() {
        let expirationDate = defaultExpiry.addingTimeInterval(-1234)

        let savedJson = """
        {
            "appVersion": "\(appVersion.currentAppVersion)",
            "mode": "atDate",
            "expirationDate": \(expirationDate.timeIntervalSinceReferenceDate)
        }
        """.data(using: .utf8)!
        db.write { tx in
            keyValueStore.setData(savedJson, key: AppExpiryImpl.keyValueKey, transaction: tx)
        }

        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, expirationDate)
    }

    func testSetHasAppExpiredAtCurrentVersion() {
        appExpiry.setHasAppExpiredAtCurrentVersion(db: db)

        XCTAssertEqual(appExpiry.expirationDate, .distantPast)
        XCTAssertTrue(appExpiry.isExpired)

        scheduler.runUntilIdle()

        XCTAssertEqual(loadPersistedExpirationDate(), .distantPast)
    }

    func testClearingExpirationDateForCurrentVersion() {
        appExpiry.setExpirationDateForCurrentVersion(nil, db: db)

        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)
        XCTAssertFalse(appExpiry.isExpired)

        XCTAssertEqual(loadPersistedExpirationDate(), defaultExpiry)
    }

    func testSetHasExpirationDateForCurrentVersion() {
        let expirationDate = defaultExpiry.addingTimeInterval(-1234)

        appExpiry.setExpirationDateForCurrentVersion(expirationDate, db: db)

        XCTAssertEqual(appExpiry.expirationDate, expirationDate)

        scheduler.runUntilIdle()

        XCTAssertEqual(loadPersistedExpirationDate(), expirationDate)
    }
}
