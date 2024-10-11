//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
open class OWSDevicesService: NSObject {

    @available(*, unavailable, message: "Do not instantiate this class.")
    private override init() {}

    @objc
    public static let deviceListUpdateSucceeded = Notification.Name("deviceListUpdateSucceeded")
    @objc
    public static let deviceListUpdateFailed = Notification.Name("deviceListUpdateFailed")
    @objc
    public static let deviceListUpdateModifiedDeviceList = Notification.Name("deviceListUpdateModifiedDeviceList")

    @discardableResult
    public static func refreshDevices() -> Promise<Void> {
        return firstly {
            Self.getDevices()
        }.done(on: DispatchQueue.global()) { (devices: [OWSDevice]) in
            let didAddOrRemove = SSKEnvironment.shared.databaseStorageRef.write { transaction in
                // If we have more than one device we may have a linked device.
                // Setting this flag here shouldn't be necessary, but we do so
                // because the "cost" is low and it will improve robustness.
                if !devices.isEmpty {
                    DependenciesBridge.shared.deviceManager.setMightHaveUnknownLinkedDevice(
                        true,
                        transaction: transaction.asV2Write
                    )
                }

                return OWSDevice.replaceAll(with: devices, transaction: transaction)
            }

            NotificationCenter.default.postNotificationNameAsync(Self.deviceListUpdateSucceeded, object: nil)

            if didAddOrRemove {
                NotificationCenter.default.postNotificationNameAsync(Self.deviceListUpdateModifiedDeviceList, object: nil)
            }
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebugUnlessNetworkFailure(error)

            NotificationCenter.default.postNotificationNameAsync(Self.deviceListUpdateFailed, object: error)
        }
    }

    private static func getDevices() -> Promise<[OWSDevice]> {
        let request = OWSRequestFactory.getDevicesRequest()
        return firstly(on: DispatchQueue.global()) {
            SSKEnvironment.shared.networkManagerRef.makePromise(request: request, canUseWebSocket: true)
        }.map(on: DispatchQueue.global()) { response in
            guard let devices = Self.parseDeviceList(response: response) else {
                throw OWSAssertionError("Unable to parse devices response.")
            }
            return devices
        }
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

    public static func unlinkDevice(
        _ device: OWSDevice,
        success: @escaping () -> Void,
        failure: @escaping (Error) -> Void
    ) {
        let request = OWSRequestFactory.deleteDeviceRequest(device)

        firstly {
            SSKEnvironment.shared.networkManagerRef.makePromise(request: request)
        }.map(on: DispatchQueue.main) { _ in
            success()
        }.catch(on: DispatchQueue.main) { error in
            owsFailDebugUnlessNetworkFailure(error)
            failure(error)
        }
    }
}
