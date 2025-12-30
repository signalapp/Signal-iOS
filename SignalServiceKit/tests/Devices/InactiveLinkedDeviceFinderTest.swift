//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class InactiveLinkedDeviceFinderTest: XCTestCase {
    private var mockDateProvider: DateProvider!
    private var mockDB: DB!
    private var mockDeviceStore: OWSDeviceStore!
    private var mockDevicesService: MockDevicesService!
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
        mockDevicesService = MockDevicesService()
        mockTSAccountManager = MockTSAccountManager()

        inactiveLinkedDeviceFinder = InactiveLinkedDeviceFinderImpl(
            dateProvider: { self.mockDateProvider() },
            db: mockDB,
            deviceService: mockDevicesService,
            deviceStore: mockDeviceStore,
            remoteConfigProvider: MockRemoteConfigProvider(),
            tsAccountManager: mockTSAccountManager,
        )
    }

    func testRefreshing() async throws {
        // Skip if linked device.
        mockTSAccountManager.registrationStateMock = { .provisioned }
        try await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
        XCTAssertEqual(mockDevicesService.refreshCount, 0)

        // Make a first attempt, failing to refresh.
        mockTSAccountManager.registrationStateMock = { .registered }
        mockDevicesService.shouldFail = true
        try? await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
        XCTAssertEqual(mockDevicesService.refreshCount, 1)

        // Make a second attempt, succeeding.
        mockTSAccountManager.registrationStateMock = { .registered }
        mockDevicesService.shouldFail = false
        try await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
        XCTAssertEqual(mockDevicesService.refreshCount, 2)
    }

    func testFetching() async throws {
        func findLeastActive() -> InactiveLinkedDevice? {
            return mockDB.read { inactiveLinkedDeviceFinder.findLeastActiveLinkedDevice(tx: $0) }
        }

        // Do a refresh...
        mockTSAccountManager.registrationStateMock = { .registered }
        try await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
        XCTAssertEqual(mockDevicesService.refreshCount, 1)

        // Only include inactive devices.
        mockTSAccountManager.registrationStateMock = { .registered }
        setMockDevices([
            .primary(),
            .fixture(name: "eye pad", lastSeenAt: inactiveLastSeenAt),
            .fixture(name: "lap top", lastSeenAt: activeLastSeenAt),
        ])
        XCTAssertEqual(
            findLeastActive()?.displayName,
            "eye pad",
        )

        // If multiple inactive devices, pick the "least active" one.
        mockTSAccountManager.registrationStateMock = { .registered }
        setMockDevices([
            .primary(),
            .fixture(name: "🏖️", lastSeenAt: inactiveLastSeenAt.addingTimeInterval(-.second)),
            .fixture(name: "🦩", lastSeenAt: inactiveLastSeenAt),
        ])
        XCTAssertEqual(
            findLeastActive()?.displayName,
            "🏖️",
        )

        // Nothing if no linked devices.
        mockTSAccountManager.registrationStateMock = { .registered }
        setMockDevices([.primary()])
        XCTAssertNil(findLeastActive())

        // Nothing if not a primary.
        mockTSAccountManager.registrationStateMock = { .provisioned }
        setMockDevices([
            .primary(),
            .fixture(name: "eye pad", lastSeenAt: inactiveLastSeenAt),
        ])
        XCTAssertNil(findLeastActive())
    }

    func testPermanentlyDisabling() async throws {
        mockTSAccountManager.registrationStateMock = { .registered }
        setMockDevices([
            .primary(),
            .fixture(name: "a sedentary device", lastSeenAt: inactiveLastSeenAt),
        ])

        mockDB.write { inactiveLinkedDeviceFinder.permanentlyDisableFinders(tx: $0) }
        try await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
        XCTAssertEqual(mockDevicesService.refreshCount, 0)
        XCTAssertFalse(mockDB.read { inactiveLinkedDeviceFinder.hasInactiveLinkedDevice(tx: $0) })

        // Re-enable (only available in tests) and run more tests, to prove the
        // disabling is why the first battery passed.
        mockDB.write { inactiveLinkedDeviceFinder.reenablePermanentlyDisabledFinders(tx: $0) }
        try await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
        XCTAssertEqual(mockDevicesService.refreshCount, 1)
        XCTAssertTrue(mockDB.read { inactiveLinkedDeviceFinder.hasInactiveLinkedDevice(tx: $0) })
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
        lastSeenAt: Date,
    ) -> OWSDevice {
        return OWSDevice(
            deviceId: DeviceId(validating: 24)!,
            createdAt: .distantPast,
            lastSeenAt: lastSeenAt,
            name: name,
        )
    }
}

// MARK: - Mocks

private class MockDevicesService: OWSDeviceService {
    var shouldFail: Bool = false
    var refreshCount: Int = 0

    func refreshDevices() async throws -> Bool {
        refreshCount += 1
        if shouldFail { throw OWSGenericError("") }

        return true
    }

    func unlinkDevice(deviceId: DeviceId) async throws {}

    func renameDevice(device: OWSDevice, newName: String) async throws {}
}
