//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import XCTest

@testable import SignalServiceKit

final class InactiveLinkedDeviceFinderTest: XCTestCase {
    private var mockDateProvider: DateProvider!
    private var mockDB: (any DB)!
    private var mockDeviceNameDecrypter: MockDeviceNameDecrypter!
    private var mockDeviceStore: MockDeviceStore!
    private var mockDevicesService: MockDevicesService!
    private var mockTSAccountManager: MockTSAccountManager!

    private var inactiveLinkedDeviceFinder: InactiveLinkedDeviceFinderImpl!

    private var activeLastSeenAt: Date {
        return mockDateProvider()
            .addingTimeInterval(-kMinuteInterval)
    }

    private var inactiveLastSeenAt: Date {
        // The finder will consider anything not seen for (1 month - 1 week) to
        // be inactive, so we'll go back exactly that far and then go one more
        // hour back to avoid any boundary-time issues.
        return mockDateProvider()
            .addingTimeInterval(-45 * kDayInterval)
            .addingTimeInterval(kWeekInterval)
            .addingTimeInterval(-kHourInterval)
    }

    override func setUp() {
        // Use the same date for all usages of the date provider across a test.
        let nowDate = Date()
        mockDateProvider = { nowDate }

        mockDB = InMemoryDB()
        mockDeviceNameDecrypter = MockDeviceNameDecrypter()
        mockDeviceStore = MockDeviceStore()
        mockDevicesService = MockDevicesService()
        mockTSAccountManager = MockTSAccountManager()

        inactiveLinkedDeviceFinder = InactiveLinkedDeviceFinderImpl(
            dateProvider: { self.mockDateProvider() },
            db: mockDB,
            deviceNameDecrypter: mockDeviceNameDecrypter,
            deviceService: mockDevicesService,
            deviceStore: mockDeviceStore,
            remoteConfigProvider: MockRemoteConfigProvider(),
            tsAccountManager: mockTSAccountManager
        )
    }

    func testRefreshing() async {
        // Skip if linked device.
        mockTSAccountManager.registrationStateMock = { .provisioned }
        await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
        XCTAssertEqual(mockDevicesService.refreshCount, 0)

        // Make a first attempt, failing to refresh.
        mockTSAccountManager.registrationStateMock = { .registered }
        mockDevicesService.shouldFail = true
        await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
        XCTAssertEqual(mockDevicesService.refreshCount, 1)

        // Make a second attempt, succeeding.
        mockTSAccountManager.registrationStateMock = { .registered }
        mockDevicesService.shouldFail = false
        await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
        XCTAssertEqual(mockDevicesService.refreshCount, 2)

        // A third attempt should do nothing, because we just succeeded.
        await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
        XCTAssertEqual(mockDevicesService.refreshCount, 2)
    }

    func testFetching() async {
        func findLeastActive() -> InactiveLinkedDevice? {
            return mockDB.read { inactiveLinkedDeviceFinder.findLeastActiveLinkedDevice(tx: $0) }
        }

        // Nothing if never refreshed.
        mockTSAccountManager.registrationStateMock = { .registered }
        mockDeviceStore.devices = [
            .primary(),
            .fixture(name: "eye pad", lastSeenAt: inactiveLastSeenAt),
        ]
        XCTAssertNil(findLeastActive())

        // Do a refresh...
        mockTSAccountManager.registrationStateMock = { .registered }
        await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
        XCTAssertEqual(mockDevicesService.refreshCount, 1)

        // Only include inactive devices.
        mockTSAccountManager.registrationStateMock = { .registered }
        mockDeviceStore.devices = [
            .primary(),
            .fixture(name: "eye pad", lastSeenAt: inactiveLastSeenAt),
            .fixture(name: "lap top", lastSeenAt: activeLastSeenAt)
        ]
        XCTAssertEqual(
            findLeastActive(),
            InactiveLinkedDevice(
                displayName: "eye pad",
                expirationDate: inactiveLastSeenAt.addingTimeInterval(45 * kDayInterval)
            )
        )

        // If multiple inactive devices, pick the "least active" one.
        mockTSAccountManager.registrationStateMock = { .registered }
        mockDeviceStore.devices = [
            .primary(),
            .fixture(name: "🏖️", lastSeenAt: inactiveLastSeenAt.addingTimeInterval(-kSecondInterval)),
            .fixture(name: "🦩", lastSeenAt: inactiveLastSeenAt),
        ]
        XCTAssertEqual(
            findLeastActive(),
            InactiveLinkedDevice(
                displayName: "🏖️",
                expirationDate: inactiveLastSeenAt.addingTimeInterval(-kSecondInterval).addingTimeInterval(45 * kDayInterval)
            )
        )

        // Nothing if no linked devices.
        mockTSAccountManager.registrationStateMock = { .registered }
        mockDeviceStore.devices = [.primary()]
        XCTAssertNil(findLeastActive())

        // Nothing if not a primary.
        mockTSAccountManager.registrationStateMock = { .provisioned }
        mockDeviceStore.devices = [
            .primary(),
            .fixture(name: "eye pad", lastSeenAt: inactiveLastSeenAt),
        ]
        XCTAssertNil(findLeastActive())
    }

    func testPermanentlyDisabling() async {
        mockTSAccountManager.registrationStateMock = { .registered }
        mockDeviceStore.devices = [
            .primary(),
            .fixture(name: "a sedentary device", lastSeenAt: inactiveLastSeenAt),
        ]

        mockDB.write { inactiveLinkedDeviceFinder.permanentlyDisableFinders(tx: $0) }
        await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
        XCTAssertEqual(mockDevicesService.refreshCount, 0)
        XCTAssertFalse(mockDB.read { inactiveLinkedDeviceFinder.hasInactiveLinkedDevice(tx: $0) })

        // Re-enable (only available in tests) and run more tests, to prove the
        // disabling is why the first battery passed.
        mockDB.write { inactiveLinkedDeviceFinder.reenablePermanentlyDisabledFinders(tx: $0) }
        await inactiveLinkedDeviceFinder.refreshLinkedDeviceStateIfNecessary()
        XCTAssertEqual(mockDevicesService.refreshCount, 1)
        XCTAssertTrue(mockDB.read { inactiveLinkedDeviceFinder.hasInactiveLinkedDevice(tx: $0) })
    }
}

private extension OWSDevice {
    static func primary() -> OWSDevice {
        return OWSDevice(
            deviceId: Int(OWSDevice.primaryDeviceId),
            encryptedName: nil,
            createdAt: .distantPast,
            lastSeenAt: Date()
        )
    }

    static func fixture(
        name: String,
        lastSeenAt: Date
    ) -> OWSDevice {
        return OWSDevice(
            deviceId: 24,
            encryptedName: name,
            createdAt: .distantPast,
            lastSeenAt: lastSeenAt
        )
    }
}

// MARK: - Mocks

private class MockDeviceNameDecrypter: InactiveLinkedDeviceFinderImpl.Shims.OWSDeviceNameDecrypter {
    func decryptName(device: OWSDevice, tx: DBReadTransaction) -> String {
        return device.encryptedName!
    }
}

private class MockDeviceStore: OWSDeviceStore {
    var devices: [OWSDevice] = []

    func fetchAll(tx: DBReadTransaction) -> [OWSDevice] {
        return devices
    }

    func replaceAll(with newDevices: [OWSDevice], tx: any DBWriteTransaction) -> Bool {
        let isChanging = devices.count == newDevices.count
        devices = newDevices
        return isChanging
    }

    func remove(_ device: OWSDevice, tx: any DBWriteTransaction) {
        devices.removeAll { _device in
            device.deviceId == _device.deviceId
        }
    }

    func setEncryptedName(_ encryptedName: String, for device: OWSDevice, tx: any DBWriteTransaction) {
        device.encryptedName = encryptedName
    }
}

private class MockDevicesService: OWSDeviceService {
    var shouldFail: Bool = false
    var refreshCount: Int = 0

    func refreshDevices() async throws -> Bool {
        refreshCount += 1
        if shouldFail { throw OWSGenericError("") }

        return true
    }

    func unlinkDevice(deviceId: Int) async throws {}

    func renameDevice(device: OWSDevice, toEncryptedName encryptedName: String) async throws {}
}
