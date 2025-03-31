//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit

public class QuickRestoreManager {
    public typealias RestoreMethodToken = String

    public enum Error: Swift.Error {
        case errorWaitingForNewDevice
        case invalidRegistrationMessage
        case unsupportedRestoreMethod
        case missingRestoreInformation
        case unknown
    }

    private let accountKeyStore: AccountKeyStore
    private let db: any DB
    private let deviceProvisioningService: DeviceProvisioningService
    private let networkManager: NetworkManager
    private let tsAccountManager: TSAccountManager
    private let twoFAManager: OWS2FAManager

    init(
        accountKeyStore: AccountKeyStore,
        db: any DB,
        deviceProvisioningService: DeviceProvisioningService,
        networkManager: NetworkManager,
        tsAccountManager: TSAccountManager,
        twoFAManager: OWS2FAManager
    ) {
        self.accountKeyStore = accountKeyStore
        self.db = db
        self.deviceProvisioningService = deviceProvisioningService
        self.networkManager = networkManager
        self.tsAccountManager = tsAccountManager
        self.twoFAManager = twoFAManager
    }

    public func register(deviceProvisioningUrl: DeviceProvisioningURL) async throws -> RestoreMethodToken {
        let (localIdentifiers, accountEntropyPool, pinCode) = try db.read { tx in
            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                owsFailDebug("Can't quick restore without local identifiers")
                throw Error.missingRestoreInformation
            }
            guard let accountEntropyPool = accountKeyStore.getAccountEntropyPool(tx: tx) else {
                // This should be impossible; the only times you don't have
                // a AEP are during registration.
                owsFailDebug("Can't quick restore without AccountEntropyPool")
                throw Error.missingRestoreInformation
            }
            let pinCode = SSKEnvironment.shared.ows2FAManagerRef.pinCode(transaction: tx)
            return (localIdentifiers, accountEntropyPool, pinCode)
        }

        let myAci = localIdentifiers.aci
        guard let myPhoneNumber = E164(localIdentifiers.phoneNumber) else {
            owsFailDebug("Can't quick restore without e164")
            throw Error.missingRestoreInformation
        }

        let restoreMethodToken = UUID().uuidString

        // TODO: [Backups] Source existing backup information
        let registrationMessage = RegistrationProvisioningMessage(
            accountEntropyPool: accountEntropyPool,
            aci: myAci,
            phoneNumber: myPhoneNumber,
            pin: pinCode,
            tier: nil,
            backupTimestamp: nil,
            backupSizeBytes: nil,
            restoreMethodToken: restoreMethodToken
        )

        let theirPublicKey = deviceProvisioningUrl.publicKey
        let messageBody = try registrationMessage.buildEncryptedMessageBody(theirPublicKey: theirPublicKey)
        try await deviceProvisioningService.provisionDevice(
            messageBody: messageBody,
            ephemeralDeviceId: deviceProvisioningUrl.ephemeralDeviceId
        )

        return restoreMethodToken
    }

    public enum RestoreMethodType {
        case remoteBackup
        case localBackup
        case deviceTransfer(String)
        case decline

        fileprivate init?(response: Requests.WaitForDeviceToRegister.Response) {
            switch response.method {
            case .decline: self = .decline
            case .localBackup: self = .localBackup
            case .remoteBackup: self = .remoteBackup
            case .deviceTransfer:
                self = .deviceTransfer(response.deviceTransferBootstrap)
            }
        }
    }

    public func waitForNewDeviceToRegister(restoreMethodToken: RestoreMethodToken) async throws -> RestoreMethodType {
        whileLoop: while true {
            do {
                // TODO: this cannot use websocket until the websocket implementation
                // supports cooperative cancellation; we need this to be cancellable.
                let response = try await networkManager.asyncRequest(
                    Requests.WaitForDeviceToRegister.buildRequest(token: restoreMethodToken),
                    canUseWebSocket: false
                )
                switch response.responseStatusCode {
                case 200:
                    guard
                        let data = response.responseBodyData,
                        let response = try? JSONDecoder().decode(
                            Requests.WaitForDeviceToRegister.Response.self,
                            from: data
                        )
                    else {
                        throw Error.errorWaitingForNewDevice
                    }

                    guard let responseType = RestoreMethodType(response: response) else {
                        throw Error.unsupportedRestoreMethod
                    }
                    return responseType
                case 400:
                    throw Error.invalidRegistrationMessage
                case 204:
                    /// The timeout elapsed without the device linking; clients can request again.
                    continue whileLoop
                case 429:
                    try await Task.sleep(
                        nanoseconds: HTTPUtils.retryDelayNanoSeconds(response, defaultRetryTime: Constants.defaultRetryTime)
                    )
                    continue whileLoop
                default:
                    owsFailDebug("Unexpected response")
                    throw Error.unknown
                }
            } catch {
                owsFailDebug("Unexpected exception")
                throw Error.unknown
            }
        }
    }

    private enum Constants {
        static let longPollRequestTimeoutSeconds: UInt32 = 60 * 5
        static let defaultRetryTime: TimeInterval = 15
    }

    fileprivate enum Requests {
        enum WaitForDeviceToRegister {
            struct Response: Codable {
                enum Method: String, Codable {
                    case remoteBackup = "REMOTE_BACKUP"
                    case localBackup = "LOCAL_BACKUP"
                    case deviceTransfer = "DEVICE_TRANSFER"
                    case decline = "DECLINE"
                }

                /// The method of restore chosen by the new device
                let method: Method
                /// Additional data used to bootstrap device transfer
                let deviceTransferBootstrap: String
            }

            static func buildRequest(token: RestoreMethodToken) -> TSRequest {
                var urlComponents = URLComponents(string: "v1/devices/restore_account/\(token)")!
                urlComponents.queryItems = [URLQueryItem(
                    name: "timeout",
                    value: "\(Constants.longPollRequestTimeoutSeconds)"
                )]
                let request = TSRequest(
                    url: urlComponents.url!,
                    method: "GET",
                    parameters: nil
                )

                request.auth = .identified(.implicit())
                request.applyRedactionStrategy(.redactURLForSuccessResponses())
                // The timeout is server side; apply wiggle room for our local clock.
                request.timeoutInterval = 10 + TimeInterval(Constants.longPollRequestTimeoutSeconds)
                return request
            }
        }
    }
}
