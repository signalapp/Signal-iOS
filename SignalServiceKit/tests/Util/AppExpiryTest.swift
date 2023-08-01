//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest
@testable import SignalServiceKit

final class AppExpiryTest: XCTestCase {
    private let appVersion = AppVersionImpl.shared
    private var date: Date!
    private var db: DB!
    private var keyValueStoreFactory: InMemoryKeyValueStoreFactory!
    private var keyValueStore: KeyValueStore!
    private var scheduler: TestScheduler!

    private var appExpiry: AppExpiryImpl!

    private var defaultExpiry: Date { appVersion.buildDate.addingTimeInterval(90 * kDayInterval) }

    private func loadPersistedExpirationDate() -> Date {
        let newAppExpiry = AppExpiryImpl(
            keyValueStoreFactory: keyValueStoreFactory,
            dateProvider: { self.date },
            appVersion: appVersion,
            schedulers: TestSchedulers(scheduler: scheduler)
        )
        db.read { newAppExpiry.warmCaches(with: $0) }
        return newAppExpiry.expirationDate
    }

    override func setUp() {
        date = appVersion.buildDate
        db = MockDB()
        keyValueStoreFactory = InMemoryKeyValueStoreFactory()
        keyValueStore = keyValueStoreFactory.keyValueStore(
            collection: AppExpiryImpl.keyValueCollection
        )
        scheduler = TestScheduler()

        appExpiry = AppExpiryImpl(
            keyValueStoreFactory: keyValueStoreFactory,
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
        XCTAssertNotEqual(appVersion.currentAppVersion4, "6.5.4.3", "Test version is unexpected")

        let savedJson = #"{"version4":"6.5.4.3","mode":"immediately"}"#.data(using: .utf8)!
        db.write { tx in
            keyValueStore.setData(savedJson, key: AppExpiryImpl.keyValueKey, transaction: tx)
        }

        db.read { self.appExpiry.warmCaches(with: $0) }

        XCTAssertEqual(appExpiry.expirationDate, defaultExpiry)
    }

    func testWarmCachesWithPersistedDefault() throws {
        let savedJson = try JSONEncoder().encode([
            "version4": appVersion.currentAppVersion4,
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
            "version4": appVersion.currentAppVersion4,
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
            "version4": "\(appVersion.currentAppVersion4)",
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

        XCTAssertEqual(loadPersistedExpirationDate(), expirationDate)
    }
}
