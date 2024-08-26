//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

public extension MessageBackup {
    enum Request {
        public struct SourceAttachment: Codable {
            let cdn: UInt32
            let key: String
        }

        public struct MediaItem: Codable {
            let sourceAttachment: SourceAttachment
            let objectLength: UInt32
            let mediaId: Data
            let hmacKey: Data
            let encryptionKey: Data
            let iv: Data

            var asParameters: [String: Any] {
                [
                    "sourceAttachment": [
                        "cdn": self.sourceAttachment.cdn,
                        "key": self.sourceAttachment.key
                    ],
                    "objectLength": self.objectLength,
                    "mediaId": self.mediaId.asBase64Url,
                    "hmacKey": self.hmacKey.base64EncodedString(),
                    "encryptionKey": self.encryptionKey.base64EncodedString(),
                    "iv": self.iv.base64EncodedString()
                ]
            }
        }

        public struct DeleteMediaTarget: Codable {
            let cdn: UInt32
            let mediaId: String
        }
    }

    enum Response {
        public struct BatchedBackupMediaResult: Codable {
            let status: UInt32?
            let failureReason: String?
            let cdn: UInt32?
            let mediaId: String
        }

        public struct ListMediaResult: Codable {
            let storedMediaObjects: [StoredMedia]
            let backupDir: String
            let mediaDir: String
            let cursor: String?
        }

        public struct StoredMedia: Codable {
            let cdn: UInt32
            let mediaId: String
            let objectLength: UInt64
        }
    }
}

public protocol MessageBackupRequestManager {

    func fetchBackupServiceAuth(localAci: Aci, auth: ChatServiceAuth) async throws -> MessageBackupServiceAuth

    func reserveBackupId(localAci: Aci, auth: ChatServiceAuth) async throws

    func registerBackupKeys(auth: MessageBackupServiceAuth) async throws

    func fetchBackupUploadForm(auth: MessageBackupServiceAuth) async throws -> Upload.Form

    func fetchBackupMediaAttachmentUploadForm(auth: MessageBackupServiceAuth) async throws -> Upload.Form

    func fetchBackupInfo(auth: MessageBackupServiceAuth) async throws -> MessageBackupRemoteInfo

    func refreshBackupInfo(auth: MessageBackupServiceAuth) async throws

    func fetchCDNReadCredentials(cdn: Int32, auth: MessageBackupServiceAuth) async throws -> CDNReadCredential

    func copyToMediaTier(
        item: MessageBackup.Request.MediaItem,
        auth: MessageBackupServiceAuth
    ) async throws -> UInt32

    func copyToMediaTier(
        items: [MessageBackup.Request.MediaItem],
        auth: MessageBackupServiceAuth
    ) async throws -> [MessageBackup.Response.BatchedBackupMediaResult]

    func listMediaObjects(
        cursor: String?,
        limit: UInt32?,
        auth: MessageBackupServiceAuth
    ) async throws -> MessageBackup.Response.ListMediaResult

    func deleteMediaObjects(
        objects: [MessageBackup.Request.DeleteMediaTarget],
        auth: MessageBackupServiceAuth
    ) async throws

    func redeemReceipt(
        receiptCredentialPresentation: Data
    ) async throws
}

public struct MessageBackupRequestManagerImpl: MessageBackupRequestManager {

    private let db: DB
    private let messageBackupAuthCredentialManager: MessageBackupAuthCredentialManager
    private let messageBackupKeyMaterial: MessageBackupKeyMaterial
    private let networkManager: NetworkManager

    init(
        db: DB,
        messageBackupAuthCredentialManager: MessageBackupAuthCredentialManager,
        messageBackupKeyMaterial: MessageBackupKeyMaterial,
        networkManager: NetworkManager
    ) {
        self.db = db
        self.messageBackupAuthCredentialManager = messageBackupAuthCredentialManager
        self.messageBackupKeyMaterial = messageBackupKeyMaterial
        self.networkManager = networkManager
    }

    // MARK: - Reserve Backup

    /// Onetime request to reserve this backup ID.
    public func reserveBackupId(localAci: Aci, auth: ChatServiceAuth) async throws {
        let backupRequestContext = try db.read { tx in
            return try messageBackupKeyMaterial.backupAuthRequestContext(localAci: localAci, tx: tx)
        }
        let base64RequestContext = Data(backupRequestContext.getRequest().serialize()).base64EncodedString()
        let request = try OWSRequestFactory.reserveBackupId(backupId: base64RequestContext, auth: auth)
        _ = try await networkManager.makePromise(
            request: request,
            canUseWebSocket: false // TODO[Backups]: Switch this back to true when reg supports websockets
        ).awaitable()
    }

    // MARK: - Backup Auth

    /// Create a `MessageBackupAuthCredential` from local ACI and the current valid backup credential. This
    /// `MessageBackupAuthCredential` is used to authenticate all further `/v1/archive` operations.
    public func fetchBackupServiceAuth(localAci: Aci, auth: ChatServiceAuth) async throws -> MessageBackupServiceAuth {
        let (backupKey, privateKey) = try db.read { tx in
            let backupKey = try messageBackupKeyMaterial.backupID(localAci: localAci, tx: tx)
            let privateKey = try messageBackupKeyMaterial.backupPrivateKey(localAci: localAci, tx: tx)
            return (backupKey, privateKey)
        }
        let authCredential = try await messageBackupAuthCredentialManager.fetchBackupCredential(
            localAci: localAci,
            auth: auth
        )
        return try MessageBackupServiceAuth(backupKey: backupKey, privateKey: privateKey, authCredential: authCredential)
    }

    // MARK: - Register Backup

    /// Onetime request to register the backup public key.
    public func registerBackupKeys(auth: MessageBackupServiceAuth) async throws {
        _ = try await executeBackupServiceRequest(
            auth: auth,
            requestFactory: OWSRequestFactory.backupSetPublicKeyRequest(auth:)
        )
    }

    // MARK: - Upload Forms

    /// CDN upload form for uploading a backup
    public func fetchBackupUploadForm(auth: MessageBackupServiceAuth) async throws -> Upload.Form {
        return try await executeBackupService(
            auth: auth,
            requestFactory: OWSRequestFactory.backupUploadFormRequest(auth:)
        )
    }

    /// CDN upload form for uploading backup media
    public func fetchBackupMediaAttachmentUploadForm(auth: MessageBackupServiceAuth) async throws -> Upload.Form {
        return try await executeBackupService(
            auth: auth,
            requestFactory: OWSRequestFactory.backupMediaUploadFormRequest(auth:)
        )
    }

    // MARK: - Backup Info

    /// Fetch details about the current backup
    public func fetchBackupInfo(auth: MessageBackupServiceAuth) async throws -> MessageBackupRemoteInfo {
        return try await executeBackupService(
            auth: auth,
            requestFactory: OWSRequestFactory.backupInfoRequest(auth:)
        )
    }

    /// Backup keep-alive request.  If not called, the backup may be deleted after 30 days.
    public func refreshBackupInfo(auth: MessageBackupServiceAuth) async throws {
        _ = try await executeBackupServiceRequest(
            auth: auth,
            requestFactory: OWSRequestFactory.backupRefreshInfoRequest(auth:)
        )
    }

    /// Delete the current backup
    public func deleteBackup(auth: MessageBackupServiceAuth) async throws {
        _ = try await executeBackupServiceRequest(
            auth: auth,
            requestFactory: OWSRequestFactory.deleteBackupRequest(auth:)
        )
    }

    // MARK: - Media

    /// Retrieve credentials used for reading from the CDN
    public func fetchCDNReadCredentials(cdn: Int32, auth: MessageBackupServiceAuth) async throws -> CDNReadCredential {
        return try await executeBackupService(
            auth: auth,
            requestFactory: { OWSRequestFactory.fetchCDNCredentials(auth: $0, cdn: cdn) }
        )
    }

    public func copyToMediaTier(
        item: MessageBackup.Request.MediaItem,
        auth: MessageBackupServiceAuth
    ) async throws -> UInt32 {
        return try await executeBackupService(
            auth: auth,
            requestFactory: {
                OWSRequestFactory.copyToMediaTier(
                    auth: $0,
                    item: item
                )
            }
        )
    }

    public func copyToMediaTier(
        items: [MessageBackup.Request.MediaItem],
        auth: MessageBackupServiceAuth
    ) async throws -> [MessageBackup.Response.BatchedBackupMediaResult] {
        return try await executeBackupService(
            auth: auth,
            requestFactory: {
                OWSRequestFactory.archiveMedia(
                    auth: $0,
                    items: items
                )
            }
        )
    }

    public func listMediaObjects(
        cursor: String?,
        limit: UInt32?,
        auth: MessageBackupServiceAuth
    ) async throws -> MessageBackup.Response.ListMediaResult {
        return try await executeBackupService(
            auth: auth,
            requestFactory: {
                OWSRequestFactory.listMedia(
                    auth: $0,
                    cursor: cursor,
                    limit: limit
                )
            }
        )
    }

    public func deleteMediaObjects(objects: [MessageBackup.Request.DeleteMediaTarget], auth: MessageBackupServiceAuth) async throws {
        _ = try await executeBackupServiceRequest(
            auth: auth,
            requestFactory: {
                OWSRequestFactory.deleteMedia(
                    auth: $0,
                    objects: objects
                )
            }
        )
    }

    // MARK: - Subscriptions

    public func redeemReceipt(receiptCredentialPresentation: Data) async throws {
        _ = OWSRequestFactory.redeemReceipt(receiptCredentialPresentation: receiptCredentialPresentation)
    }

    // MARK: - Private utility methods

    private func executeBackupServiceRequest(
        auth: MessageBackupServiceAuth,
        requestFactory: (MessageBackupServiceAuth) -> TSRequest
    ) async throws -> HTTPResponse {
        return try await networkManager.makePromise(
            request: requestFactory(auth),
            canUseWebSocket: false // TODO[Backups]: Switch this back to true when reg supports websockets
        ).awaitable()
    }

    private func executeBackupService<T: Decodable>(
        auth: MessageBackupServiceAuth,
        requestFactory: (MessageBackupServiceAuth) -> TSRequest
    ) async throws -> T {
        let response = try await executeBackupServiceRequest(
            auth: auth,
            requestFactory: requestFactory
        )
        guard let bodyData = response.responseBodyData else {
            throw OWSAssertionError("Missing body data")
        }
        return try JSONDecoder().decode(T.self, from: bodyData)
    }
}

public struct CDNReadCredential: Decodable {
    let headers: [String: String]
}
