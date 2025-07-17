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
    public var verificationCode: String
    /// An opaque identifier for the generated token that the caller may use
    /// to watch for a new device to complete the linking process.
    var tokenIdentifier: String

    public var tokenId: DeviceProvisioningTokenId { .init(id: tokenIdentifier) }
}

public protocol DeviceProvisioningService {
    func requestDeviceProvisioningCode() async throws -> DeviceProvisioningCodeResponse
    func provisionDevice(messageBody: Data, ephemeralDeviceId: String) async throws
}

public class DeviceProvisioningServiceImpl: DeviceProvisioningService {
    private let networkManager: NetworkManager

    public init(networkManager: NetworkManager) {
        self.networkManager = networkManager
    }

    public func requestDeviceProvisioningCode() async throws -> DeviceProvisioningCodeResponse {
        do {
            let request = OWSRequestFactory.deviceProvisioningCode()
            let httpResponse = try await networkManager.asyncRequest(request)
            guard let httpResponseData = httpResponse.responseBodyData else {
                throw OWSAssertionError("Missing responseBodyData.")
            }
            let response = try JSONDecoder().decode(DeviceProvisioningCodeResponse.self, from: httpResponseData)
            guard response.verificationCode.nilIfEmpty != nil else {
                throw OWSAssertionError("Empty verificationCode.")
            }
            return response
        } catch {
            throw DeviceLimitExceededError(error) ?? error
        }
    }

    public func provisionDevice(messageBody: Data, ephemeralDeviceId: String) async throws {
        let request = OWSRequestFactory.provisionDevice(
            withMessageBody: messageBody,
            ephemeralDeviceId: ephemeralDeviceId
        )
        do {
            _ = try await networkManager.asyncRequest(request)
        } catch {
            owsFailDebugUnlessNetworkFailure(error)
            throw error
        }
    }
}
