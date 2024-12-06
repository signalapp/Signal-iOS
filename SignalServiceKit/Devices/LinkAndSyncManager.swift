//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import LibSignalClient

extension BackupKey {
    public convenience init?(provisioningMessage: ProvisionMessage) {
        guard let data = provisioningMessage.ephemeralBackupKey else {
            return nil
        }
        try? self.init(contents: Array(data))
    }

    #if TESTABLE_BUILD
    public static func forTesting() -> BackupKey {
        return try! BackupKey(contents: Array(Randomness.generateRandomBytes(UInt(SVR.DerivedKey.backupKeyLength))))
    }
    #endif
}

/// Link'n'Sync errors thrown on the primary device.
public enum PrimaryLinkNSyncError: Error {
    case timedOutWaitingForLinkedDevice
    case errorWaitingForLinkedDevice
    case errorGeneratingBackup
    case errorUploadingBackup
    case networkError
}

/// Used as the label for OWSProgress.
public enum PrimaryLinkNSyncProgressPhase: String {
    case waitingForLinking
    case exportingBackup
    case uploadingBackup
    case finishing

    var percentOfTotalProgress: UInt32 {
        return switch self {
        case .waitingForLinking: 20
        case .exportingBackup: 35
        case .uploadingBackup: 35
        case .finishing: 10
        }
    }
}

/// Link'n'Sync errors thrown on the secondary device.
public enum SecondaryLinkNSyncError: Error {
    case timedOutWaitingForBackup
    case errorWaitingForBackup
    case errorDownloadingBackup
    case errorRestoringBackup
    case networkError
}

/// Used as the label for OWSProgress.
public enum SecondaryLinkNSyncProgressPhase: String {
    case waitingForBackup
    case downloadingBackup
    case importingBackup

    var percentOfTotalProgress: UInt32 {
        return switch self {
        case .waitingForBackup: 20
        case .downloadingBackup: 40
        case .importingBackup: 40
        }
    }
}

public protocol LinkAndSyncManager {

    /// **Call this on the primary device!**
    /// Generate an ephemeral backup key on a primary device to be used to link'n'sync a new linked device.
    /// This key should be included in the provisioning message and then used to encrypt the backup proto we send.
    ///
    /// - returns The ephemeral key to use, or nil if link'n'sync should not be used.
    func generateEphemeralBackupKey() -> BackupKey

    /// **Call this on the primary device!**
    /// Once the primary sends the provisioning message to the linked device, call this method
    /// to wait on the linked device to link, generate a backup, and upload it. Once this method returns,
    /// the primary's role is complete and the user can exit.
    func waitForLinkingAndUploadBackup(
        ephemeralBackupKey: BackupKey,
        tokenId: DeviceProvisioningTokenId,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError)

    /// **Call this on the secondary/linked device!**
    /// Once the secondary links on the server, call this method to wait on the primary
    /// to upload a backup, download that backup, and restore data from it.
    /// Once this method returns, provisioning can continue and finish.
    func waitForBackupAndRestore(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth,
        ephemeralBackupKey: BackupKey,
        progress: OWSProgressSink
    ) async throws(SecondaryLinkNSyncError)
}

public class LinkAndSyncManagerImpl: LinkAndSyncManager {

    private let attachmentDownloadManager: AttachmentDownloadManager
    private let attachmentUploadManager: AttachmentUploadManager
    private let db: any DB
    private let kvStore: KeyValueStore
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
        self.kvStore = KeyValueStore(collection: "LinkAndSyncManagerImpl")
        self.messageBackupManager = messageBackupManager
        self.networkManager = networkManager
        self.tsAccountManager = tsAccountManager
    }

    public func generateEphemeralBackupKey() -> BackupKey {
        owsAssertDebug(FeatureFlags.linkAndSync)
        owsAssertDebug(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice == true)
        return try! BackupKey(contents: Array(Randomness.generateRandomBytes(UInt(SVR.DerivedKey.backupKeyLength))))
    }

    public func waitForLinkingAndUploadBackup(
        ephemeralBackupKey: BackupKey,
        tokenId: DeviceProvisioningTokenId,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) {
        guard FeatureFlags.linkAndSync else {
            owsFailDebug("link'n'sync not available")
            return
        }
        let (localIdentifiers, registrationState) = db.read { tx in
            return (
                tsAccountManager.localIdentifiers(tx: tx),
                tsAccountManager.registrationState(tx: tx)
            )
        }
        guard let localIdentifiers else {
            owsFailDebug("Not registered!")
            return
        }
        guard registrationState.isPrimaryDevice == true else {
            owsFailDebug("Non-primary device waiting for secondary linking")
            return
        }

        // Proportion progress percentages up front.
        let waitForLinkingProgress = await progress.addChild(
            withLabel: PrimaryLinkNSyncProgressPhase.waitingForLinking.rawValue,
            unitCount: PrimaryLinkNSyncProgressPhase.waitingForLinking.percentOfTotalProgress
        )
        let exportingBackupProgress = await progress.addChild(
            withLabel: PrimaryLinkNSyncProgressPhase.exportingBackup.rawValue,
            unitCount: PrimaryLinkNSyncProgressPhase.exportingBackup.percentOfTotalProgress
        )
        let uploadingBackupProgress = await progress.addChild(
            withLabel: PrimaryLinkNSyncProgressPhase.uploadingBackup.rawValue,
            unitCount: PrimaryLinkNSyncProgressPhase.uploadingBackup.percentOfTotalProgress
        )
        let markUploadedProgress = await progress.addChild(
            withLabel: PrimaryLinkNSyncProgressPhase.finishing.rawValue,
            unitCount: PrimaryLinkNSyncProgressPhase.finishing.percentOfTotalProgress
        )

        let waitForLinkResponse = try await waitForDeviceToLink(tokenId: tokenId, progress: waitForLinkingProgress)
        let backupMetadata = try await generateBackup(
            ephemeralBackupKey: ephemeralBackupKey,
            localIdentifiers: localIdentifiers,
            progress: exportingBackupProgress
        )
        let uploadResult = try await uploadEphemeralBackup(
            metadata: backupMetadata,
            progress: uploadingBackupProgress
        )
        try await markEphemeralBackupUploaded(
            waitForDeviceToLinkResponse: waitForLinkResponse,
            metadata: uploadResult,
            progress: markUploadedProgress
        )
    }

    public func waitForBackupAndRestore(
        localIdentifiers: LocalIdentifiers,
        auth: ChatServiceAuth,
        ephemeralBackupKey: BackupKey,
        progress: OWSProgressSink
    ) async throws(SecondaryLinkNSyncError) {
        guard FeatureFlags.linkAndSync else {
            owsFailDebug("link'n'sync not available")
            return
        }
        owsAssertDebug(tsAccountManager.registrationStateWithMaybeSneakyTransaction.isPrimaryDevice != true)

        // Proportion progress percentages up front.
        let waitForBackupProgress = await progress.addChild(
            withLabel: SecondaryLinkNSyncProgressPhase.waitingForBackup.rawValue,
            unitCount: SecondaryLinkNSyncProgressPhase.waitingForBackup.percentOfTotalProgress
        )
        let downloadBackupProgress = await progress.addChild(
            withLabel: SecondaryLinkNSyncProgressPhase.downloadingBackup.rawValue,
            unitCount: SecondaryLinkNSyncProgressPhase.downloadingBackup.percentOfTotalProgress
        )
        let importBackupProgress = await progress.addChild(
            withLabel: SecondaryLinkNSyncProgressPhase.importingBackup.rawValue,
            unitCount: SecondaryLinkNSyncProgressPhase.importingBackup.percentOfTotalProgress
        )

        let backupUploadResponse = try await waitForPrimaryToUploadBackup(
            auth: auth,
            progress: waitForBackupProgress
        )
        let downloadedFileUrl = try await downloadEphemeralBackup(
            waitForBackupResponse: backupUploadResponse,
            ephemeralBackupKey: ephemeralBackupKey,
            progress: downloadBackupProgress
        )
        try await restoreEphemeralBackup(
            fileUrl: downloadedFileUrl,
            localIdentifiers: localIdentifiers,
            ephemeralBackupKey: ephemeralBackupKey,
            progress: importBackupProgress
        )
    }

    // MARK: Primary device steps

    private func waitForDeviceToLink(
        tokenId: DeviceProvisioningTokenId,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) -> Requests.WaitForDeviceToLinkResponse {
        let progressSource = await progress.addSource(
            withLabel: PrimaryLinkNSyncProgressPhase.waitingForLinking.rawValue,
            // Unit count is irrelevant as there's just one child source and we use a timer.
            unitCount: 100
        )
        return try await progressSource.updatePeriodically(
            estimatedTimeToCompletion: 5,
            work: { () async throws(PrimaryLinkNSyncError) -> Requests.WaitForDeviceToLinkResponse in
                try await self._waitForDeviceToLink(tokenId: tokenId)
            }
        )
    }

    private func _waitForDeviceToLink(
        tokenId: DeviceProvisioningTokenId
    ) async throws(PrimaryLinkNSyncError) -> Requests.WaitForDeviceToLinkResponse {
        let response: HTTPResponse
        do {
            response = try await networkManager.asyncRequest(
                Requests.waitForDeviceToLink(tokenId: tokenId)
            )
        } catch {
            throw PrimaryLinkNSyncError.networkError
        }

        switch Requests.WaitForDeviceToLinkResponseCodes(rawValue: response.responseStatusCode) {
        case .success:
            guard
                let data = response.responseBodyData,
                let response = try? JSONDecoder().decode(
                    Requests.WaitForDeviceToLinkResponse.self,
                    from: data
                )
            else {
                throw PrimaryLinkNSyncError.errorWaitingForLinkedDevice
            }
            return response
        case .timeout:
            throw PrimaryLinkNSyncError.timedOutWaitingForLinkedDevice
        case .invalidParameters, .rateLimited:
            throw PrimaryLinkNSyncError.errorWaitingForLinkedDevice
        case nil:
            owsFailDebug("Unexpected response")
            throw PrimaryLinkNSyncError.errorWaitingForLinkedDevice
        }
    }

    private func generateBackup(
        ephemeralBackupKey: BackupKey,
        localIdentifiers: LocalIdentifiers,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) -> Upload.EncryptedBackupUploadMetadata {
        do {
            let metadata = try await messageBackupManager.exportEncryptedBackup(
                localIdentifiers: localIdentifiers,
                backupKey: ephemeralBackupKey,
                backupPurpose: .deviceTransfer,
                progress: progress
            )
            try await messageBackupManager.validateEncryptedBackup(
                fileUrl: metadata.fileUrl,
                localIdentifiers: localIdentifiers,
                backupKey: ephemeralBackupKey,
                backupPurpose: .deviceTransfer
            )
            return metadata
        } catch let error {
            owsFailDebug("Unable to generate link'n'sync backup: \(error)")
            throw PrimaryLinkNSyncError.errorGeneratingBackup
        }
    }

    private func uploadEphemeralBackup(
        metadata: Upload.EncryptedBackupUploadMetadata,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) -> Upload.Result<Upload.LinkNSyncUploadMetadata> {
        // TODO: hook into AttachmentUploadManager progress reporting
        let progressSource = await progress.addSource(
            withLabel: PrimaryLinkNSyncProgressPhase.uploadingBackup.rawValue,
            // Unit count is irrelevant as there's just one child source and we use a timer.
            unitCount: 100
        )
        return try await progressSource.updatePeriodically(
            estimatedTimeToCompletion: 10,
            work: { () async throws(PrimaryLinkNSyncError) -> Upload.Result<Upload.LinkNSyncUploadMetadata> in
                try await self._uploadEphemeralBackup(metadata: metadata)
            }
        )
    }

    private func _uploadEphemeralBackup(
        metadata: Upload.EncryptedBackupUploadMetadata
    ) async throws(PrimaryLinkNSyncError) -> Upload.Result<Upload.LinkNSyncUploadMetadata> {
        do {
            return try await attachmentUploadManager.uploadLinkNSyncAttachment(
                dataSource: try DataSourcePath(
                    fileUrl: metadata.fileUrl,
                    shouldDeleteOnDeallocation: true
                )
            )
        } catch {
            if error.isNetworkFailureOrTimeout {
                throw PrimaryLinkNSyncError.networkError
            } else {
                throw PrimaryLinkNSyncError.errorUploadingBackup
            }
        }
    }

    private func markEphemeralBackupUploaded(
        waitForDeviceToLinkResponse: Requests.WaitForDeviceToLinkResponse,
        metadata: Upload.Result<Upload.LinkNSyncUploadMetadata>,
        progress: OWSProgressSink
    ) async throws(PrimaryLinkNSyncError) -> Void {
        let progressSource = await progress.addSource(
            withLabel: PrimaryLinkNSyncProgressPhase.finishing.rawValue,
            // Unit count is irrelevant as there's just one child source and we use a timer.
            unitCount: 100
        )
        return try await progressSource.updatePeriodically(
            estimatedTimeToCompletion: 1,
            work: { () async throws(PrimaryLinkNSyncError) -> Void in
                try await self._markEphemeralBackupUploaded(
                    waitForDeviceToLinkResponse: waitForDeviceToLinkResponse,
                    metadata: metadata
                )
            }
        )
    }

    private func _markEphemeralBackupUploaded(
        waitForDeviceToLinkResponse: Requests.WaitForDeviceToLinkResponse,
        metadata: Upload.Result<Upload.LinkNSyncUploadMetadata>
    ) async throws(PrimaryLinkNSyncError) -> Void {
        do {
            let response = try await networkManager.asyncRequest(
                Requests.markLinkNSyncBackupUploaded(
                    waitForDeviceToLinkResponse: waitForDeviceToLinkResponse,
                    cdnNumber: metadata.cdnNumber,
                    cdnKey: metadata.cdnKey
                )
            )

            guard response.responseStatusCode == 204 || response.responseStatusCode == 200 else {
                throw PrimaryLinkNSyncError.errorUploadingBackup
            }
        } catch let error {
            if error.isNetworkFailureOrTimeout {
                throw PrimaryLinkNSyncError.networkError
            } else {
                throw PrimaryLinkNSyncError.errorUploadingBackup
            }
        }
    }

    // MARK: Linked device steps

    private func waitForPrimaryToUploadBackup(
        auth: ChatServiceAuth,
        progress: OWSProgressSink
    ) async throws(SecondaryLinkNSyncError) -> Requests.WaitForLinkNSyncBackupUploadResponse {
        let progressSource = await progress.addSource(
            withLabel: SecondaryLinkNSyncProgressPhase.waitingForBackup.rawValue,
            // Unit count is irrelevant as there's just one child source and we use a timer.
            unitCount: 100
        )
        return try await progressSource.updatePeriodically(
            estimatedTimeToCompletion: 20,
            work: { () async throws(SecondaryLinkNSyncError) -> Requests.WaitForLinkNSyncBackupUploadResponse in
                try await self._waitForPrimaryToUploadBackup(auth: auth)
            }
        )
    }

    private func _waitForPrimaryToUploadBackup(
        auth: ChatServiceAuth
    ) async throws(SecondaryLinkNSyncError) -> Requests.WaitForLinkNSyncBackupUploadResponse {
        let response: HTTPResponse
        do {
            response = try await networkManager.asyncRequest(
                Requests.waitForLinkNSyncBackupUpload(auth: auth)
            )
        } catch {
            throw SecondaryLinkNSyncError.networkError
        }

        switch Requests.WaitForLinkNSyncBackupUploadResponseCodes(rawValue: response.responseStatusCode) {
        case .success:
            guard
                let data = response.responseBodyData,
                let response = try? JSONDecoder().decode(
                    Requests.WaitForLinkNSyncBackupUploadResponse.self,
                    from: data
                )
            else {
                throw SecondaryLinkNSyncError.errorWaitingForBackup
            }
            return response
        case .timeout:
            throw SecondaryLinkNSyncError.timedOutWaitingForBackup
        case .invalidParameters, .rateLimited:
            throw SecondaryLinkNSyncError.errorWaitingForBackup
        case nil:
            owsFailDebug("Unexpected response")
            throw SecondaryLinkNSyncError.errorWaitingForBackup
        }
    }

    private func downloadEphemeralBackup(
        waitForBackupResponse: Requests.WaitForLinkNSyncBackupUploadResponse,
        ephemeralBackupKey: BackupKey,
        progress: OWSProgressSink
    ) async throws(SecondaryLinkNSyncError) -> URL {
        // TODO: hook into AttachmentDownloadManager progress reporting
        let progressSource = await progress.addSource(
            withLabel: SecondaryLinkNSyncProgressPhase.waitingForBackup.rawValue,
            // Unit count is irrelevant as there's just one child source and we use a timer.
            unitCount: 100
        )
        return try await progressSource.updatePeriodically(
            estimatedTimeToCompletion: 10,
            work: { () async throws(SecondaryLinkNSyncError) -> URL in
                try await self._downloadEphemeralBackup(
                    waitForBackupResponse: waitForBackupResponse,
                    ephemeralBackupKey: ephemeralBackupKey
                )
            }
        )
    }

    private func _downloadEphemeralBackup(
        waitForBackupResponse: Requests.WaitForLinkNSyncBackupUploadResponse,
        ephemeralBackupKey: BackupKey
    ) async throws(SecondaryLinkNSyncError) -> URL {
        do {
            return try await attachmentDownloadManager.downloadTransientAttachment(
                metadata: AttachmentDownloads.DownloadMetadata(
                    mimeType: MimeType.applicationOctetStream.rawValue,
                    cdnNumber: waitForBackupResponse.cdn,
                    encryptionKey: ephemeralBackupKey.serialize().asData,
                    source: .linkNSyncBackup(cdnKey: waitForBackupResponse.key)
                )
            ).awaitable()
        } catch {
            if error.isNetworkFailureOrTimeout {
                throw SecondaryLinkNSyncError.networkError
            } else {
                throw SecondaryLinkNSyncError.errorDownloadingBackup
            }
        }
    }

    private func restoreEphemeralBackup(
        fileUrl: URL,
        localIdentifiers: LocalIdentifiers,
        ephemeralBackupKey: BackupKey,
        progress: OWSProgressSink
    ) async throws(SecondaryLinkNSyncError) {
        do {
            try await messageBackupManager.importEncryptedBackup(
                fileUrl: fileUrl,
                localIdentifiers: localIdentifiers,
                backupKey: ephemeralBackupKey,
                progress: progress
            )
        } catch {
            owsFailDebug("Unable to restore link'n'sync backup: \(error)")
            throw SecondaryLinkNSyncError.errorRestoringBackup
        }
    }

    fileprivate enum Constants {
        static let enabledOnPrimaryKey = "enabledOnPrimaryKey"

        static let waitForDeviceLinkTimeoutSeconds: UInt32 = FeatureFlags.linkAndSyncTimeoutSeconds
        static let waitForBackupUploadTimeoutSeconds: UInt32 = FeatureFlags.linkAndSyncTimeoutSeconds
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

        static func waitForLinkNSyncBackupUpload(auth: ChatServiceAuth) -> TSRequest {
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
            request.setAuth(auth)
            request.applyRedactionStrategy(.redactURLForSuccessResponses())
            // The timeout is server side; apply wiggle room for our local clock.
            request.timeoutInterval = 30 + TimeInterval(Constants.waitForBackupUploadTimeoutSeconds)
            return request
        }
    }
}
