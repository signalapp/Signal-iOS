//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public struct DeviceProvisioningTokenId {
    public let id: String

    fileprivate init(id: String) {
        self.id = id
    }
}

public struct DeviceProvisioningCodeResponse: Decodable {
    /// An opaque token to send to a new linked device that authorizes the
    /// new device to link itself to the account that requested this token.
    var verificationCode: String
    /// An opaque identifier for the generated token that the caller may use
    /// to watch for a new device to complete the linking process.
    var tokenIdentifier: String

    var tokenId: DeviceProvisioningTokenId { .init(id: tokenIdentifier) }
}

public protocol DeviceProvisioningService {
    func requestDeviceProvisioningCode() -> Promise<DeviceProvisioningCodeResponse>
    func provisionDevice(messageBody: Data, ephemeralDeviceId: String) -> Promise<Void>
}

public class DeviceProvisioningServiceImpl: DeviceProvisioningService {
    private let networkManager: NetworkManager
    private let schedulers: Schedulers

    public init(networkManager: NetworkManager, schedulers: Schedulers) {
        self.networkManager = networkManager
        self.schedulers = schedulers
    }

    public func requestDeviceProvisioningCode() -> Promise<DeviceProvisioningCodeResponse> {
        let request = OWSRequestFactory.deviceProvisioningCode()
        return firstly(on: schedulers.sharedUserInitiated) {
            self.networkManager.makePromise(request: request, canUseWebSocket: true)
        }.map(on: schedulers.sharedUserInitiated) { (httpResponse: HTTPResponse) -> DeviceProvisioningCodeResponse in
            guard let httpResponseData = httpResponse.responseBodyData else {
                throw OWSAssertionError("Missing responseBodyData.")
            }
            let response = try JSONDecoder().decode(DeviceProvisioningCodeResponse.self, from: httpResponseData)
            guard response.verificationCode.nilIfEmpty != nil else {
                throw OWSAssertionError("Empty verificationCode.")
            }
            return response
        }.recover(on: schedulers.sharedUserInitiated) { (error: Error) -> Promise<DeviceProvisioningCodeResponse> in
            throw DeviceLimitExceededError(error) ?? error
        }
    }

    public func provisionDevice(messageBody: Data, ephemeralDeviceId: String) -> Promise<Void> {
        let request = OWSRequestFactory.provisionDevice(
            withMessageBody: messageBody,
            ephemeralDeviceId: ephemeralDeviceId
        )
        return firstly(on: schedulers.sharedUserInitiated) {
            self.networkManager.makePromise(request: request, canUseWebSocket: true)
                .asVoid(on: self.schedulers.sync)
        }.recover(on: schedulers.sharedUserInitiated) { (error: Error) -> Promise<Void> in
            owsFailDebugUnlessNetworkFailure(error)
            throw error
        }
    }
}
