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
    private let backupSettingsStore: BackupSettingsStore
    private let db: any DB
    private let deviceProvisioningService: DeviceProvisioningService
    private let identityManager: OWSIdentityManager
    private let networkManager: NetworkManager
    private let tsAccountManager: TSAccountManager

    init(
        accountKeyStore: AccountKeyStore,
        backupSettingsStore: BackupSettingsStore,
        db: any DB,
        deviceProvisioningService: DeviceProvisioningService,
        identityManager: OWSIdentityManager,
        networkManager: NetworkManager,
        tsAccountManager: TSAccountManager
    ) {
        self.accountKeyStore = accountKeyStore
        self.backupSettingsStore = backupSettingsStore
        self.db = db
        self.deviceProvisioningService = deviceProvisioningService
        self.identityManager = identityManager
        self.networkManager = networkManager
        self.tsAccountManager = tsAccountManager
    }

    public func register(deviceProvisioningUrl: DeviceProvisioningURL) async throws -> RestoreMethodToken {
        let (
            localIdentifiers,
            accountEntropyPool,
            aciIdentityKeyPair,
            pniIdentityKeyPair,
            pinCode,
            backupTier,
            lastBackupDate,
            lastBackupSizeBytes
        ) = try db.read { tx in
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
            guard let aciIdentityKeyPair = identityManager.identityKeyPair(for: .aci, tx: tx) else {
                owsFailDebug("Can't quick restore without local identity key")
                throw Error.missingRestoreInformation
            }
            guard let pniIdentityKeyPair = identityManager.identityKeyPair(for: .pni, tx: tx) else {
                owsFailDebug("Can't quick restore without local identity key")
                throw Error.missingRestoreInformation
            }
            let pinCode = SSKEnvironment.shared.ows2FAManagerRef.pinCode(transaction: tx)

            let backupTier: RegistrationProvisioningMessage.BackupTier? = switch backupSettingsStore.backupPlan(tx: tx) {
            case .free: .free
            case .paid, .paidExpiringSoon, .paidAsTester: .paid
            case .disabled, .disabling: nil
            }

            let lastBackupTime = backupSettingsStore.lastBackupDate(tx: tx)?.ows_millisecondsSince1970
            let lastBackupSizeBytes = backupSettingsStore.lastBackupSizeBytes(tx: tx)

            return (
                localIdentifiers,
                accountEntropyPool,
                aciIdentityKeyPair,
                pniIdentityKeyPair,
                pinCode,
                backupTier,
                lastBackupTime,
                lastBackupSizeBytes
            )
        }

        let myAci = localIdentifiers.aci
        guard let myPhoneNumber = E164(localIdentifiers.phoneNumber) else {
            owsFailDebug("Can't quick restore without e164")
            throw Error.missingRestoreInformation
        }

        let restoreMethodToken = UUID().uuidString

        let registrationMessage = RegistrationProvisioningMessage(
            accountEntropyPool: accountEntropyPool,
            aci: myAci,
            aciIdentityKeyPair: aciIdentityKeyPair.identityKeyPair,
            pniIdentityKeyPair: pniIdentityKeyPair.identityKeyPair,
            phoneNumber: myPhoneNumber,
            pin: pinCode,
            tier: backupTier,
            backupVersion: BackupArchiveManagerImpl.Constants.supportedBackupVersion,
            backupTimestamp: lastBackupDate,
            backupSizeBytes: lastBackupSizeBytes,
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

        fileprivate init?(response: Requests.WaitForRestoreMethodChoice.Response) {
            switch response.method {
            case .decline: self = .decline
            case .localBackup: self = .localBackup
            case .remoteBackup: self = .remoteBackup
            case .deviceTransfer:
                guard let bootstrapData = response.deviceTransferBootstrap else { return nil }
                self = .deviceTransfer(bootstrapData)
            }
        }
    }

    public func reportRestoreMethodChoice(method: RestoreMethodType, restoreMethodToken: RestoreMethodToken) async throws {
        whileLoop: while true {
            let response = try await networkManager.asyncRequest(
                Requests.ChooseRestoreMethod.buildRequest(
                    token: restoreMethodToken,
                    method: method
                ),
                canUseWebSocket: false
            )
            switch response.responseStatusCode {
            case 200, 204:
                return
            case 429:
                try await Task.sleep(
                    nanoseconds: HTTPUtils.retryDelayNanoSeconds(response, defaultRetryTime: Constants.defaultRetryTime)
                )
                continue whileLoop
            default:
                owsFailDebug("Unexpected response")
                throw Error.unknown
            }
        }
    }

    public func waitForRestoreMethodChoice(restoreMethodToken: RestoreMethodToken) async throws -> RestoreMethodType {
        whileLoop: while true {
            do {
                // TODO: this cannot use websocket until the websocket implementation
                // supports cooperative cancellation; we need this to be cancellable.
                let response = try await networkManager.asyncRequest(
                    Requests.WaitForRestoreMethodChoice.buildRequest(token: restoreMethodToken),
                    canUseWebSocket: false
                )
                switch response.responseStatusCode {
                case 200:
                    guard
                        let data = response.responseBodyData,
                        let response = try? JSONDecoder().decode(
                            Requests.WaitForRestoreMethodChoice.Response.self,
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
        enum RestoreMethod: String, Codable {
            case remoteBackup = "REMOTE_BACKUP"
            case localBackup = "LOCAL_BACKUP"
            case deviceTransfer = "DEVICE_TRANSFER"
            case decline = "DECLINE"
        }

        enum WaitForRestoreMethodChoice {
            struct Response: Codable {
                /// The method of restore chosen by the new device
                let method: RestoreMethod
                /// Additional data used to bootstrap device transfer
                let deviceTransferBootstrap: String?
            }

            static func buildRequest(token: RestoreMethodToken) -> TSRequest {
                var urlComponents = URLComponents(string: "v1/devices/restore_account/\(token)")!
                urlComponents.queryItems = [URLQueryItem(
                    name: "timeout",
                    value: "\(Constants.longPollRequestTimeoutSeconds)"
                )]
                var request = TSRequest(
                    url: urlComponents.url!,
                    method: "GET",
                    parameters: nil
                )

                request.auth = .anonymous
                request.applyRedactionStrategy(.redactURLForSuccessResponses())
                // The timeout is server side; apply wiggle room for our local clock.
                request.timeoutInterval = 10 + TimeInterval(Constants.longPollRequestTimeoutSeconds)
                return request
            }
        }

        enum ChooseRestoreMethod {
            static func buildRequest(token: RestoreMethodToken, method: RestoreMethodType) -> TSRequest {
                var deviceTransferBootstrap: String?
                let method: RestoreMethod = {
                    switch method {
                    case .decline: return .decline
                    case .deviceTransfer(let data):
                        deviceTransferBootstrap = data
                        return .deviceTransfer
                    case .remoteBackup:
                        return .remoteBackup
                    case .localBackup:
                        return .localBackup
                    }
                }()

                var parameters: [String: Any] = [ "method": method.rawValue ]
                // `deviceTransferBootstrap` contains unpadded base64 encoded data that is used by
                // the other device to initiate device transfer. Note that server enforces a
                // 4096 bytes limit on this field.
                deviceTransferBootstrap.map { parameters["deviceTransferBootstrap"] = $0 }

                let urlComponents = URLComponents(string: "v1/devices/restore_account/\(token)")!
                var request = TSRequest(
                    url: urlComponents.url!,
                    method: "PUT",
                    parameters: parameters
                )

                request.auth = .anonymous
                request.applyRedactionStrategy(.redactURLForSuccessResponses())
                return request
            }
        }
    }
}
