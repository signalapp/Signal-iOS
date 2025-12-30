//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public protocol OWSDeviceService {
    /// Refresh the list of our linked devices.
    /// - Returns
    /// True if the list changed, and false otherwise.
    func refreshDevices() async throws -> Bool

    /// Unlink the given device.
    func unlinkDevice(deviceId: DeviceId) async throws

    /// Renames a device with the given encrypted name.
    func renameDevice(
        device: OWSDevice,
        newName: String,
    ) async throws
}

extension OWSDeviceService {
    public func unlinkDevice(_ device: OWSDevice) async throws {
        guard let deviceId = DeviceId(validating: device.deviceId) else {
            // If it's not valid, the device can't exist on the server.
            return
        }
        try await unlinkDevice(deviceId: deviceId)
    }
}

// MARK: -

struct OWSDeviceServiceImpl: OWSDeviceService {
    private let db: any DB
    private let deviceNameChangeSyncMessageSender: DeviceNameChangeSyncMessageSender
    private let deviceManager: OWSDeviceManager
    private let deviceStore: OWSDeviceStore
    private let identityManager: OWSIdentityManager
    private let networkManager: NetworkManager
    private let recipientFetcher: RecipientFetcher
    private let recipientManager: any SignalRecipientManager
    private let tsAccountManager: any TSAccountManager

    init(
        db: any DB,
        deviceManager: OWSDeviceManager,
        deviceStore: OWSDeviceStore,
        identityManager: OWSIdentityManager,
        messageSenderJobQueue: MessageSenderJobQueue,
        networkManager: NetworkManager,
        recipientFetcher: RecipientFetcher,
        recipientManager: any SignalRecipientManager,
        threadStore: ThreadStore,
        tsAccountManager: any TSAccountManager,
    ) {
        self.db = db
        self.deviceNameChangeSyncMessageSender = DeviceNameChangeSyncMessageSender(
            messageSenderJobQueue: messageSenderJobQueue,
            threadStore: threadStore,
        )
        self.deviceManager = deviceManager
        self.deviceStore = deviceStore
        self.identityManager = identityManager
        self.networkManager = networkManager
        self.recipientFetcher = recipientFetcher
        self.recipientManager = recipientManager
        self.tsAccountManager = tsAccountManager
    }

    // MARK: -

    private struct DeviceListResponse: Decodable {
        struct Device: Decodable {
            enum CodingKeys: String, CodingKey {
                case id
                case lastSeenAtMs = "lastSeen"
                case registrationId
                case createdAtCiphertext
                case nameCiphertext = "name"
            }

            let id: DeviceId
            let lastSeenAtMs: UInt64
            let registrationId: UInt32
            let createdAtCiphertext: Data
            let nameCiphertext: String?
        }

        let devices: [Device]
    }

    func refreshDevices() async throws -> Bool {
        guard
            let identityKeyPair = db.read(block: { tx in
                identityManager.identityKeyPair(for: .aci, tx: tx)?.keyPair
            })
        else {
            throw OWSAssertionError("Missing ACI identity key pair: will fail to refresh devices!")
        }

        let getDevicesResponse = try await networkManager.asyncRequest(.getDevices())

        let devices = try parseDeviceList(
            httpResponse: getDevicesResponse,
            identityKeyPair: identityKeyPair,
        )

        // TODO: This can't fail. Remove it once OWSDevice's deviceId is updated.
        let deviceIds = devices.compactMap { DeviceId(validating: $0.deviceId) }

        let didAddOrRemove = await db.awaitableWrite { tx in
            let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx)!
            var localRecipient = recipientFetcher.fetchOrCreate(serviceId: localIdentifiers.aci, tx: tx)
            recipientManager.modifyAndSave(
                &localRecipient,
                deviceIdsToAdd: Array(Set(deviceIds).subtracting(localRecipient.deviceIds)),
                deviceIdsToRemove: Array(Set(localRecipient.deviceIds).subtracting(deviceIds)),
                shouldUpdateStorageService: false,
                tx: tx,
            )

            return deviceStore.replaceAll(with: devices, tx: tx)
        }

        return didAddOrRemove
    }

    private func parseDeviceList(
        httpResponse: HTTPResponse,
        identityKeyPair: IdentityKeyPair,
    ) throws -> [OWSDevice] {
        guard let responseBodyData = httpResponse.responseBodyData else {
            throw OWSAssertionError("Missing body data in getDevices response!")
        }

        let devicesResponse = try JSONDecoder().decode(DeviceListResponse.self, from: responseBodyData)

        return try devicesResponse.devices.map {
            try parseOWSDevice(from: $0, identityKeyPair: identityKeyPair)
        }
    }

    private func parseOWSDevice(
        from fetchedDevice: DeviceListResponse.Device,
        identityKeyPair: IdentityKeyPair,
    ) throws(OWSAssertionError) -> OWSDevice {
        let name: String?
        if let nameCiphertext = fetchedDevice.nameCiphertext?.strippedOrNil {
            do {
                name = try OWSDeviceNames.decryptDeviceName(
                    base64String: nameCiphertext,
                    identityKeyPair: identityKeyPair,
                )
            } catch {
                owsFailDebug("Failed to decrypt device name! Is this a legacy device name? \(error)")
                name = nameCiphertext
            }
        } else {
            name = nil
        }

        let createdAtMs: UInt64
        do {
            // The createdAtCiphertext is an Int64, encrypted using the identity
            // key PrivateKey with associated data (deviceId || registrationId).
            //
            // Note that the server does everything big-endian, whereas iOS uses
            // little-endian by default.

            var associatedData = Data()
            associatedData.append(contentsOf: withUnsafeBytes(of: fetchedDevice.id.rawValue.bigEndian) { Array($0) })
            associatedData.append(contentsOf: withUnsafeBytes(of: fetchedDevice.registrationId.bigEndian) { Array($0) })

            let createdAtData: Data = try identityKeyPair.privateKey.open(
                fetchedDevice.createdAtCiphertext,
                info: "deviceCreatedAt",
                associatedData: associatedData,
            )

            let createdAtMsInt = withUnsafeBytes(of: createdAtData) {
                $0.load(as: Int64.self).bigEndian
            }

            createdAtMs = UInt64(createdAtMsInt)
        } catch {
            throw OWSAssertionError("Failed to decrypt device createdAt! \(error)")
        }

        return OWSDevice(
            deviceId: fetchedDevice.id,
            createdAt: Date(millisecondsSince1970: createdAtMs),
            lastSeenAt: Date(millisecondsSince1970: fetchedDevice.lastSeenAtMs),
            name: name,
        )
    }

    // MARK: -

    func unlinkDevice(deviceId: DeviceId) async throws {
        _ = try await networkManager.asyncRequest(TSRequest.deleteDevice(deviceId: deviceId))
    }

    func renameDevice(
        device: OWSDevice,
        newName: String,
    ) async throws {
        guard
            let identityKeyPair = db.read(block: { tx in
                identityManager.identityKeyPair(for: .aci, tx: tx)
            })
        else {
            throw OWSAssertionError("can't rename device without identity key")
        }

        let newNameEncrypted = try OWSDeviceNames.encryptDeviceName(
            plaintext: newName,
            identityKeyPair: identityKeyPair.keyPair,
        ).base64EncodedString()

        let response = try await self.networkManager.asyncRequest(
            .renameDevice(device: device, encryptedName: newNameEncrypted),
        )

        guard response.responseStatusCode == 204 else {
            throw response.asError()
        }

        await db.awaitableWrite { tx in
            deviceStore.setName(newName, for: device, tx: tx)

            guard let deviceId = UInt32(exactly: device.deviceId) else {
                owsFailDebug("Failed to coerce device ID into UInt32!")
                return
            }

            deviceNameChangeSyncMessageSender.enqueueDeviceNameChangeSyncMessage(
                forDeviceId: deviceId,
                tx: tx,
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
        tx: DBWriteTransaction,
    ) {
        guard let localThread = threadStore.getOrCreateLocalThread(tx: tx) else {
            owsFailDebug("Failed to create local thread!")
            return
        }

        let outgoingSyncMessage = OutgoingDeviceNameChangeSyncMessage(
            deviceId: deviceId,
            localThread: localThread,
            tx: tx,
        )

        messageSenderJobQueue.add(
            message: .preprepared(transientMessageWithoutAttachments: outgoingSyncMessage),
            transaction: tx,
        )
    }
}

// MARK: -

extension TSRequest {
    fileprivate static func getDevices() -> TSRequest {
        return TSRequest(
            url: URL(string: "v1/devices")!,
            method: "GET",
            parameters: [:],
        )
    }

    public static func deleteDevice(
        deviceId: DeviceId,
    ) -> TSRequest {
        return TSRequest(
            url: URL(string: "v1/devices/\(deviceId)")!,
            method: "DELETE",
            parameters: nil,
        )
    }

    fileprivate static func renameDevice(
        device: OWSDevice,
        encryptedName: String,
    ) -> TSRequest {
        var urlComponents = URLComponents(string: "v1/accounts/name")!
        urlComponents.queryItems = [URLQueryItem(
            name: "deviceId",
            value: "\(device.deviceId)",
        )]
        var request = TSRequest(
            url: urlComponents.url!,
            method: "PUT",
            parameters: [
                "deviceName": encryptedName,
            ],
        )
        request.applyRedactionStrategy(.redactURL())
        return request
    }
}
