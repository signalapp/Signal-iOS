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
    public static let deviceListUpdateSucceeded = Notification.Name("CallServicePreferencesDidChange")
    @objc
    public static let deviceListUpdateFailed = Notification.Name("deviceListUpdateFailed")
    @objc
    public static let deviceListUpdateModifiedDeviceList = Notification.Name("deviceListUpdateModifiedDeviceList")

    @objc
    public static func refreshDevices() {
        firstly {
            Self.getDevices()
        }.done(on: .global()) { (devices: [OWSDevice]) in
            // If we have more than one device we may have a linked device.
            if !devices.isEmpty {
                // Setting this flag here shouldn't be necessary, but we do so
                // because the "cost" is low and it will improve robustness.
                Self.deviceManager.setMayHaveLinkedDevices()
            }

            let didAddOrRemove = Self.databaseStorage.write { transaction in
                OWSDevice.replaceAll(devices, transaction: transaction)
            }

            NotificationCenter.default.postNotificationNameAsync(Self.deviceListUpdateSucceeded, object: nil)

            if didAddOrRemove {
                NotificationCenter.default.postNotificationNameAsync(Self.deviceListUpdateModifiedDeviceList, object: nil)
            }
        }.catch(on: .global()) { error in
            owsFailDebugUnlessNetworkFailure(error)

            NotificationCenter.default.postNotificationNameAsync(Self.deviceListUpdateFailed, object: error)
        }
    }

    private static func getDevices() -> Promise<[OWSDevice]> {
        let request = OWSRequestFactory.getDevicesRequest()
        return firstly(on: .global()) {
            Self.networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
            Logger.verbose("Get devices request succeeded")

            guard let devices = Self.parseDeviceList(response: response) else {
                throw OWSAssertionError("Unable to parse devices response.")
            }
            return devices
        }
    }

    private static func parseDeviceList(response: HTTPResponse) -> [OWSDevice]? {
        guard let json = response.responseBodyJson as? [String: Any] else {
            owsFailDebug("Missing or invalid JSON.")
            return nil
        }
        guard let devicesAttributes = json["devices"] as? [[String: Any]] else {
            owsFailDebug("Missing or invalid devices.")
            return nil
        }
        return devicesAttributes.compactMap { deviceAttributes -> OWSDevice? in
            do {
                return try OWSDevice(fromJSONDictionary: deviceAttributes)
            } catch {
                owsFailDebug("Failed to build device from dictionary with error: \(error).")
                return nil
            }
        }
    }

    @objc
    public static func unlinkDevice(_ device: OWSDevice,
                                    success: @escaping () -> Void,
                                    failure: @escaping (Error) -> Void) {

        let request = OWSRequestFactory.deleteDeviceRequest(with: device)
        firstly {
            Self.networkManager.makePromise(request: request)
        }.map(on: .main) { _ in
            Logger.verbose("Delete device request succeeded")
            success()
        }.catch(on: .main) { error in
            owsFailDebugUnlessNetworkFailure(error)
            failure(error)
        }
    }
}
