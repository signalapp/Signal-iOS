//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public struct EphemeralBackupKey {
    public let data: Data

    fileprivate init(_ data: Data) {
        self.data = data
    }
}

/// Link'n'Sync errors thrown on the primary device.
public enum PrimaryLinkNSyncError: Error {
    case timedOutWaitingForLinkedDevice
    case errorWaitingForLinkedDevice
    case errorGeneratingBackup
    case errorUploadingBackup
    case networkError
}

/// Link'n'Sync errors thrown on the secondary device.
public enum SecondaryLinkNSyncError: Error {
    case timedOutWaitingForBackup
    case errorWaitingForBackup
    case errorDownloadingBackup
    case errorRestoringBackup
    case networkError
}

public protocol LinkAndSyncManager {

    /// **Call this on the primary device!**
    /// Generate an ephemeral backup key on a primary device to be used to link'n'sync a new linked device.
    /// This key should be included in the provisioning message and then used to encrypt the backup proto we send.
    ///
    /// - returns The ephemeral key to use, or nil if link'n'sync should not be used.
    func generateEphemeralBackupKey() -> EphemeralBackupKey?

    /// **Call this on the primary device!**
    /// Once the primary sends the provisioning message to the linked device, call this method
    /// to wait on the linked device to link, generate a backup, and upload it. Once this method returns,
    /// the primary's role is complete and the user can exit.
    func waitForLinkingAndUploadBackup(
        ephemeralBackupKey: EphemeralBackupKey,
        tokenId: DeviceProvisioningTokenId
    ) async throws(PrimaryLinkNSyncError)

    /// **Call this on the secondary/linked device!**
    /// Once the secondary links on the server, call this method to wait on the primary
    /// to upload a backup, download that backup, and restore data from it.
    /// Once this method returns, provisioning can continue and finish.
    func waitForBackupAndRestore(
        ephemeralBackupKey: EphemeralBackupKey
    ) async throws(SecondaryLinkNSyncError)
}

public class LinkAndSyncManagerImpl: LinkAndSyncManager {

    private let attachmentDownloadManager: AttachmentDownloadManager
    private let attachmentUploadManager: AttachmentUploadManager
    private let db: any DB
    private let messageBackupManager: MessageBackupManager
    private let networkManager: NetworkManager
    private let tsAccountManager: TSAccountManager

    public init(
        attachmentDownloadManager: AttachmentDownloadManager,
        attachmentUploadManager: AttachmentUploadManager,
        db: any DB,
        messageBackupManager: MessageBackupManager,
        networkManager: NetworkManager,
        tsAccountManager: TSAccountManager
    ) {
        self.attachmentDownloadManager = attachmentDownloadManager
        self.attachmentUploadManager = attachmentUploadManager
        self.db = db
        self.messageBackupManager = messageBackupManager
        self.networkManager = networkManager
        self.tsAccountManager = tsAccountManager
    }

    public func generateEphemeralBackupKey() -> EphemeralBackupKey? {
        guard FeatureFlags.linkAndSync else {
            return nil
        }
        owsAssertDebug(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true)
        return EphemeralBackupKey(Randomness.generateRandomBytes(UInt(SVR.DerivedKey.backupKeyLength)))
    }

    public func waitForLinkingAndUploadBackup(
        ephemeralBackupKey: EphemeralBackupKey,
        tokenId: DeviceProvisioningTokenId
    ) async throws(PrimaryLinkNSyncError) {
        guard FeatureFlags.linkAndSync else {
            owsFailDebug("link'n'sync not available")
            return
        }
        owsAssertDebug(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true)
        // TODO: [link'n'sync] wait for the secondary to link.
        // TODO: [link'n'sync] generate a backup with the ephemeral key.
        // TODO: [link'n'sync] upload the backup.
        // TODO: [link'n'sync] mark the backup as uploaded on the server.
    }

    public func waitForBackupAndRestore(
        ephemeralBackupKey: EphemeralBackupKey
    ) async throws(SecondaryLinkNSyncError) {
        guard FeatureFlags.linkAndSync else {
            owsFailDebug("link'n'sync not available")
            return
        }
        owsAssertDebug(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice != true)
        // TODO: [link'n'sync] wait for the primary to upload the backup.
        // TODO: [link'n'sync] download the backup.
        // TODO: [link'n'sync] restore from the backup.
    }

    fileprivate enum Constants {
        static let waitForDeviceLinkTimeoutSeconds: UInt32 = 60
        static let waitForBackupUploadTimeoutSeconds: UInt32 = 60
    }

    // MARK: -

    private enum Requests {

        struct WaitForDeviceToLinkResponse: Codable {
            /// The deviceId of the linked device
            let id: Int64
            /// Thename of the linked device.
            let name: String
            /// The timestamp the linked device was last seen on the server.
            let lastSeen: UInt64
            /// The timestamp the linked device was created on the server.
            let created: UInt64
        }

        enum WaitForDeviceToLinkResponseCodes: Int {
            case success = 200
            /// The timeout elapsed without the device linking; clients can request again.
            case timeout = 204
            case invalidParameters = 400
            case rateLimited = 429
        }

        static func waitForDeviceToLink(
            tokenId: DeviceProvisioningTokenId
        ) -> TSRequest {
            var urlComponents = URLComponents(string: "v1/devices/wait_for_linked_device/\(tokenId.id)")!
            urlComponents.queryItems = [URLQueryItem(
                name: "timeout",
                value: "\(LinkAndSyncManagerImpl.Constants.waitForDeviceLinkTimeoutSeconds)"
            )]
            let request = TSRequest(
                url: urlComponents.url!,
                method: "GET",
                parameters: nil
            )
            request.shouldHaveAuthorizationHeaders = true
            request.applyRedactionStrategy(.redactURLForSuccessResponses())
            // The timeout is server side; apply wiggle room for our local clock.
            request.timeoutInterval = 30 + TimeInterval(Constants.waitForDeviceLinkTimeoutSeconds)
            return request
        }

        static func markLinkNSyncBackupUploaded(
            waitForDeviceToLinkResponse: WaitForDeviceToLinkResponse,
            cdnNumber: UInt32,
            cdnKey: String
        ) -> TSRequest {
            let request = TSRequest(
                url: URL(string: "v1/devices/transfer_archive")!,
                method: "PUT",
                parameters: [
                    "destinationDeviceId": waitForDeviceToLinkResponse.id,
                    "destinationDeviceCreated": waitForDeviceToLinkResponse.created,
                    "transferArchive": [
                        "cdn": cdnNumber,
                        "key": cdnKey
                    ]
                ]
            )
            request.shouldHaveAuthorizationHeaders = true
            request.applyRedactionStrategy(.redactURLForSuccessResponses())
            return request
        }

        struct WaitForLinkNSyncBackupUploadResponse: Codable {
            /// The cdn number
            let cdn: UInt32
            /// The cdn key
            let key: String
        }

        enum WaitForLinkNSyncBackupUploadResponseCodes: Int {
            case success = 200
            /// The timeout elapsed without any upload; clients can request again.
            case timeout = 204
            case invalidParameters = 400
            case rateLimited = 429
        }

        static func waitForLinkNSyncBackupUpload(
            tokenId: DeviceProvisioningTokenId
        ) -> TSRequest {
            var urlComponents = URLComponents(string: "v1/devices/transfer_archive")!
            urlComponents.queryItems = [URLQueryItem(
                name: "timeout",
                value: "\(Constants.waitForBackupUploadTimeoutSeconds)"
            )]
            let request = TSRequest(
                url: urlComponents.url!,
                method: "GET",
                parameters: nil
            )
            request.shouldHaveAuthorizationHeaders = true
            request.applyRedactionStrategy(.redactURLForSuccessResponses())
            // The timeout is server side; apply wiggle room for our local clock.
            request.timeoutInterval = 30 + TimeInterval(Constants.waitForBackupUploadTimeoutSeconds)
            return request
        }
    }
}
