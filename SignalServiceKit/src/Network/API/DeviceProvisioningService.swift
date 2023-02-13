//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public protocol DeviceProvisioningService {
    func requestDeviceProvisioningCode() -> Promise<String>
    func provisionDevice(messageBody: Data, ephemeralDeviceId: String) -> Promise<Void>
}

public class DeviceProvisioningServiceImpl: DeviceProvisioningService {
    private let networkManager: NetworkManager
    private let schedulers: Schedulers

    public init(networkManager: NetworkManager, schedulers: Schedulers) {
        self.networkManager = networkManager
        self.schedulers = schedulers
    }

    public func requestDeviceProvisioningCode() -> Promise<String> {
        let request = OWSRequestFactory.deviceProvisioningCode()
        return firstly(on: schedulers.sharedUserInitiated) {
            self.networkManager.makePromise(request: request, canTryWebSocket: true)
        }.map(on: schedulers.sharedUserInitiated) { (httpResponse: HTTPResponse) -> String in
            guard let httpResponseData = httpResponse.responseBodyData else {
                throw OWSAssertionError("Missing responseBodyData.")
            }
            let response = try JSONDecoder().decode(DeviceProvisioningCodeResponse.self, from: httpResponseData)
            guard let nonEmptyVerificationCode = response.verificationCode.nilIfEmpty else {
                throw OWSAssertionError("Empty verificationCode.")
            }
            return nonEmptyVerificationCode
        }.recover(on: schedulers.sharedUserInitiated) { (error: Error) -> Promise<String> in
            throw DeviceLimitExceededError(error) ?? error
        }
    }

    private struct DeviceProvisioningCodeResponse: Decodable {
        var verificationCode: String
    }

    public func provisionDevice(messageBody: Data, ephemeralDeviceId: String) -> Promise<Void> {
        let request = OWSRequestFactory.provisionDevice(
            withMessageBody: messageBody,
            ephemeralDeviceId: ephemeralDeviceId
        )
        return firstly(on: schedulers.sharedUserInitiated) {
            self.networkManager.makePromise(request: request, canTryWebSocket: true)
                .asVoid(on: self.schedulers.sync)
        }.recover(on: schedulers.sharedUserInitiated) { (error: Error) -> Promise<Void> in
            owsFailDebugUnlessNetworkFailure(error)
            throw error
        }
    }
}
