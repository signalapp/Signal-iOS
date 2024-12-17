//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public protocol OWSDeviceService {
    /// Refresh the list of our linked devices.
    /// - Returns
    /// True if the list changed, and false otherwise.
    func refreshDevices() async throws -> Bool

    /// Unlink the given device.
    func unlinkDevice(deviceId: Int) async throws

    /// Renames a device with the given encrypted name.
    func renameDevice(
        device: OWSDevice,
        toEncryptedName encryptedName: String
    ) async throws
}

extension OWSDeviceService {

    public func unlinkDevice(_ device: OWSDevice) async throws {
        try await unlinkDevice(deviceId: device.deviceId)
    }
}

public enum DeviceRenameError: Error {
    case encryptionFailed
    case unspecified
}

// MARK: -

struct OWSDeviceServiceImpl: OWSDeviceService {
    private let db: any DB
    private let deviceNameChangeSyncMessageSender: DeviceNameChangeSyncMessageSender
    private let deviceManager: OWSDeviceManager
    private let deviceStore: OWSDeviceStore
    private let networkManager: NetworkManager

    init(
        db: any DB,
        deviceManager: OWSDeviceManager,
        deviceStore: OWSDeviceStore,
        messageSenderJobQueue: MessageSenderJobQueue,
        networkManager: NetworkManager,
        threadStore: ThreadStore
    ) {
        self.db = db
        self.deviceNameChangeSyncMessageSender = DeviceNameChangeSyncMessageSender(
            messageSenderJobQueue: messageSenderJobQueue,
            threadStore: threadStore
        )
        self.deviceManager = deviceManager
        self.deviceStore = deviceStore
        self.networkManager = networkManager
    }

    // MARK: -

    func refreshDevices() async throws -> Bool {
        let getDevicesResponse = try await networkManager.asyncRequest(
            .getDevices(),
            canUseWebSocket: true
        )

        guard let devices = Self.parseDeviceList(response: getDevicesResponse) else {
            throw OWSAssertionError("Unable to parse devices response.")
        }

        let didAddOrRemove = await db.awaitableWrite { tx in
            // If we have more than one device we may have a linked device.
            // Setting this flag here shouldn't be necessary, but we do so
            // because the "cost" is low and it will improve robustness.
            if !devices.isEmpty {
                deviceManager.setMightHaveUnknownLinkedDevice(
                    true,
                    transaction: tx
                )
            }

            return deviceStore.replaceAll(with: devices, tx: tx)
        }

        return didAddOrRemove
    }

    private static func parseDeviceList(response: HTTPResponse) -> [OWSDevice]? {
        struct DeviceListResponse: Decodable {
            struct Device: Decodable {
                enum CodingKeys: String, CodingKey {
                    case createdAtMs = "created"
                    case lastSeenAtMs = "lastSeen"
                    case id
                    case encryptedName = "name"
                }

                let createdAtMs: UInt64
                let lastSeenAtMs: UInt64
                let id: Int
                let encryptedName: String?
            }

            let devices: [Device]
        }

        guard
            let devicesJsonData = response.responseBodyData,
            let devicesResponse = try? JSONDecoder().decode(DeviceListResponse.self, from: devicesJsonData)
        else {
            owsFailDebug("Missing or invalid devices response!")
            return nil
        }

        return devicesResponse.devices.compactMap { device in
            guard device.id >= OWSDevice.primaryDeviceId else {
                owsFailBeta("Invalid device ID: \(device.id)!")
                return nil
            }

            return OWSDevice(
                deviceId: device.id,
                encryptedName: device.encryptedName,
                createdAt: Date(millisecondsSince1970: device.createdAtMs),
                lastSeenAt: Date(millisecondsSince1970: device.lastSeenAtMs)
            )
        }
    }

    // MARK: -

    func unlinkDevice(deviceId: Int) async throws {
        _ = try await networkManager.asyncRequest(
            .deleteDevice(deviceId: deviceId)
        )
    }

    func renameDevice(
        device: OWSDevice,
        toEncryptedName encryptedName: String
    ) async throws {
        let response = try await self.networkManager.asyncRequest(
            .renameDevice(device: device, encryptedName: encryptedName)
        )

        guard response.responseStatusCode == 204 else {
            throw DeviceRenameError.unspecified
        }

        await db.awaitableWrite { tx in
            deviceStore.setEncryptedName(
                encryptedName,
                for: device,
                tx: tx
            )

            guard let deviceId = UInt32(exactly: device.deviceId) else {
                owsFailDebug("Failed to coerce device ID into UInt32!")
                return
            }

            deviceNameChangeSyncMessageSender.enqueueDeviceNameChangeSyncMessage(
                forDeviceId: deviceId,
                tx: tx
            )
        }
    }
}

// MARK: -

private struct DeviceNameChangeSyncMessageSender {
    private let messageSenderJobQueue: MessageSenderJobQueue
    private let threadStore: ThreadStore

    init(messageSenderJobQueue: MessageSenderJobQueue, threadStore: ThreadStore) {
        self.messageSenderJobQueue = messageSenderJobQueue
        self.threadStore = threadStore
    }

    func enqueueDeviceNameChangeSyncMessage(
        forDeviceId deviceId: UInt32,
        tx: DBWriteTransaction
    ) {
        let sdsTx = SDSDB.shimOnlyBridge(tx)

        guard let localThread = threadStore.getOrCreateLocalThread(tx: tx) else {
            owsFailDebug("Failed to create local thread!")
            return
        }

        let outgoingSyncMessage = OutgoingDeviceNameChangeSyncMessage(
            deviceId: deviceId,
            thread: localThread,
            tx: sdsTx
        )

        messageSenderJobQueue.add(
            message: .preprepared(transientMessageWithoutAttachments: outgoingSyncMessage),
            transaction: sdsTx
        )
    }
}

// MARK: -

private extension TSRequest {
    static func getDevices() -> TSRequest {
        return TSRequest(
            url: URL(string: "v1/devices")!,
            method: "GET",
            parameters: [:]
        )
    }

    static func deleteDevice(
        deviceId: Int
    ) -> TSRequest {
        return TSRequest(
            url: URL(string: "/v1/devices/\(deviceId)")!,
            method: "DELETE",
            parameters: nil
        )
    }

    static func renameDevice(
        device: OWSDevice,
        encryptedName: String
    ) -> TSRequest {
        var urlComponents = URLComponents(string: "v1/accounts/name")!
        urlComponents.queryItems = [URLQueryItem(
            name: "deviceId",
            value: "\(device.deviceId)"
        )]
        let request = TSRequest(
            url: urlComponents.url!,
            method: "PUT",
            parameters: [
                "deviceName": encryptedName,
            ]
        )
        request.applyRedactionStrategy(.redactURLForSuccessResponses())
        return request
    }
}
