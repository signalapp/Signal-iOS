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
    func unlinkDevice(deviceId: DeviceId, auth: ChatServiceAuth) async throws

    /// Renames a device with the given encrypted name.
    func renameDevice(
        device: OWSDevice,
        toEncryptedName encryptedName: String
    ) async throws
}

extension OWSDeviceService {

    public func unlinkDevice(deviceId: DeviceId) async throws {
        try await self.unlinkDevice(deviceId: deviceId, auth: .implicit())
    }

    public func unlinkDevice(_ device: OWSDevice, auth: ChatServiceAuth = .implicit()) async throws {
        guard let deviceId = DeviceId(validating: device.deviceId) else {
            // If it's not valid, the device can't exist on the server.
            return
        }
        try await unlinkDevice(deviceId: deviceId, auth: auth)
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
    private let recipientFetcher: any RecipientFetcher
    private let recipientManager: any SignalRecipientManager
    private let tsAccountManager: any TSAccountManager

    init(
        db: any DB,
        deviceManager: OWSDeviceManager,
        deviceStore: OWSDeviceStore,
        messageSenderJobQueue: MessageSenderJobQueue,
        networkManager: NetworkManager,
        recipientFetcher: any RecipientFetcher,
        recipientManager: any SignalRecipientManager,
        threadStore: ThreadStore,
        tsAccountManager: any TSAccountManager
    ) {
        self.db = db
        self.deviceNameChangeSyncMessageSender = DeviceNameChangeSyncMessageSender(
            messageSenderJobQueue: messageSenderJobQueue,
            threadStore: threadStore
        )
        self.deviceManager = deviceManager
        self.deviceStore = deviceStore
        self.networkManager = networkManager
        self.recipientFetcher = recipientFetcher
        self.recipientManager = recipientManager
        self.tsAccountManager = tsAccountManager
    }

    // MARK: -

    func refreshDevices() async throws -> Bool {
        let getDevicesResponse = try await networkManager.asyncRequest(
            .getDevices()
        )

        let devices = try Self.parseDeviceList(response: getDevicesResponse)

        // TODO: This can't fail. Remove it once OWSDevice's deviceId is updated.
        let deviceIds = devices.compactMap { DeviceId(validating: $0.deviceId) }

        let didAddOrRemove = await db.awaitableWrite { tx in
            let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)!
            let localRecipient = recipientFetcher.fetchOrCreate(serviceId: localIdentifiers.aci, tx: tx)
            recipientManager.modifyAndSave(
                localRecipient,
                deviceIdsToAdd: Array(Set(deviceIds).subtracting(localRecipient.deviceIds)),
                deviceIdsToRemove: Array(Set(localRecipient.deviceIds).subtracting(deviceIds)),
                shouldUpdateStorageService: false,
                tx: tx
            )

            return deviceStore.replaceAll(with: devices, tx: tx)
        }

        return didAddOrRemove
    }

    private static func parseDeviceList(response: HTTPResponse) throws -> [OWSDevice] {
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
                let id: DeviceId
                let encryptedName: String?
            }

            let devices: [Device]
        }

        let devicesResponse = try JSONDecoder().decode(DeviceListResponse.self, from: response.responseBodyData ?? Data())

        return devicesResponse.devices.map { device in
            return OWSDevice(
                deviceId: device.id,
                encryptedName: device.encryptedName,
                createdAt: Date(millisecondsSince1970: device.createdAtMs),
                lastSeenAt: Date(millisecondsSince1970: device.lastSeenAtMs)
            )
        }
    }

    // MARK: -

    func unlinkDevice(deviceId: DeviceId, auth: ChatServiceAuth) async throws {
        var request = TSRequest.deleteDevice(deviceId: deviceId)
        request.auth = .identified(auth)
        _ = try await networkManager.asyncRequest(request, canUseWebSocket: false)
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
            localThread: localThread,
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
        deviceId: DeviceId
    ) -> TSRequest {
        return TSRequest(
            url: URL(string: "v1/devices/\(deviceId)")!,
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
        var request = TSRequest(
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
