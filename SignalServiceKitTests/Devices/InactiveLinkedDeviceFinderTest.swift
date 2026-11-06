//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
import XCTest

@testable import SignalServiceKit

final class InactiveLinkedDeviceFinderTest: XCTestCase {
    private var mockDateProvider: DateProvider!
    private var mockDB: DB!
    private var mockDeviceStore: OWSDeviceStore!
    private var mockLocalIdentifiers: LocalIdentifiers = .forUnitTests
    private var mockTSAccountManager: MockTSAccountManager!

    private var inactiveLinkedDeviceFinder: InactiveLinkedDeviceFinderImpl!

    private var activeLastSeenAt: Date {
        return mockDateProvider()
            .addingTimeInterval(-.minute)
    }

    private var inactiveLastSeenAt: Date {
        // The finder will consider anything not seen for (1 month - 1 week) to
        // be inactive, so we'll go back exactly that far and then go one more
        // hour back to avoid any boundary-time issues.
        return mockDateProvider()
            .addingTimeInterval(-45 * .day)
            .addingTimeInterval(.week)
            .addingTimeInterval(-.hour)
    }

    override func setUp() {
        // Use the same date for all usages of the date provider across a test.
        let nowDate = Date()
        mockDateProvider = { nowDate }

        mockDB = InMemoryDB()
        mockDeviceStore = OWSDeviceStore()
        mockTSAccountManager = MockTSAccountManager()
        mockTSAccountManager.localIdentifiersMock = { [mockLocalIdentifiers] in mockLocalIdentifiers }

        inactiveLinkedDeviceFinder = InactiveLinkedDeviceFinderImpl(
            dateProvider: { self.mockDateProvider() },
            db: mockDB,
            deviceStore: mockDeviceStore,
            remoteConfigProvider: MockRemoteConfigProvider(),
            tsAccountManager: mockTSAccountManager,
        )
    }

    func testFetching() {
        func findLeastActive() -> InactiveLinkedDevice? {
            return mockDB.read { inactiveLinkedDeviceFinder.findLeastActiveLinkedDevice(tx: $0) }
        }

        // Only include inactive devices.
        mockTSAccountManager.registrationStateMock = { [mockLocalIdentifiers] in .registered(mockLocalIdentifiers) }
        setMockDevices([
            .primary(),
            .fixture(name: "eye pad", deviceId: 2, lastSeenAt: inactiveLastSeenAt),
            .fixture(name: "lap top", deviceId: 3, lastSeenAt: activeLastSeenAt),
        ])
        XCTAssertEqual(
            findLeastActive()?.displayName,
            "eye pad",
        )

        // If multiple inactive devices, pick the "least active" one.
        mockTSAccountManager.registrationStateMock = { [mockLocalIdentifiers] in .registered(mockLocalIdentifiers) }
        setMockDevices([
            .primary(),
            .fixture(name: "🏖️", deviceId: 4, lastSeenAt: inactiveLastSeenAt.addingTimeInterval(-.second)),
            .fixture(name: "🦩", deviceId: 5, lastSeenAt: inactiveLastSeenAt),
        ])
        XCTAssertEqual(
            findLeastActive()?.displayName,
            "🏖️",
        )

        // Nothing if no linked devices.
        mockTSAccountManager.registrationStateMock = { [mockLocalIdentifiers] in .registered(mockLocalIdentifiers) }
        setMockDevices([.primary()])
        XCTAssertNil(findLeastActive())

        // Nothing if not a primary.
        mockTSAccountManager.registrationStateMock = { [mockLocalIdentifiers] in .provisioned(mockLocalIdentifiers) }
        setMockDevices([
            .primary(),
            .fixture(name: "eye pad", deviceId: 6, lastSeenAt: inactiveLastSeenAt),
        ])
        XCTAssertNil(findLeastActive())
    }

    func testPermanentlyDisabling() {
        mockTSAccountManager.registrationStateMock = { [mockLocalIdentifiers] in .registered(mockLocalIdentifiers) }
        setMockDevices([
            .primary(),
            .fixture(name: "a sedentary device", deviceId: 7, lastSeenAt: inactiveLastSeenAt),
        ])

        mockDB.write { inactiveLinkedDeviceFinder.permanentlyDisableFinders(tx: $0) }
        XCTAssertFalse(mockDB.read { inactiveLinkedDeviceFinder.findLeastActiveLinkedDevice(tx: $0) != nil })

        // Re-enable (only available in tests) and run more tests, to prove the
        // disabling is why the first battery passed.
        mockDB.write { inactiveLinkedDeviceFinder.reenablePermanentlyDisabledFinders(tx: $0) }
        XCTAssertTrue(mockDB.read { inactiveLinkedDeviceFinder.findLeastActiveLinkedDevice(tx: $0) != nil })
    }

    private func setMockDevices(_ devices: [OWSDevice]) {
        mockDB.write { tx in
            _ = mockDeviceStore.replaceAll(with: devices, tx: tx)
        }
    }
}

private extension OWSDevice {
    static func primary() -> OWSDevice {
        return OWSDevice(
            deviceId: .primary,
            createdAt: .distantPast,
            lastSeenAt: Date(),
            name: nil,
        )
    }

    static func fixture(
        name: String,
        deviceId: Int8,
        lastSeenAt: Date,
    ) -> OWSDevice {
        return OWSDevice(
            deviceId: DeviceId(validating: deviceId)!,
            createdAt: .distantPast,
            lastSeenAt: lastSeenAt,
            name: name,
        )
    }
}
