//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public extension BackupArchive {
    enum Request {
        public struct SourceAttachment {
            let cdn: UInt32
            let key: String
        }

        public struct MediaItem {
            let sourceAttachment: SourceAttachment
            let objectLength: UInt32
            let mediaId: Data
            let hmacKey: Data
            let aesKey: Data

            var asParameters: [String: Any] {
                [
                    "sourceAttachment": [
                        "cdn": self.sourceAttachment.cdn,
                        "key": self.sourceAttachment.key
                    ],
                    "objectLength": self.objectLength,
                    "mediaId": self.mediaId.asBase64Url,
                    "hmacKey": self.hmacKey.base64EncodedString(),
                    "encryptionKey": self.aesKey.base64EncodedString()
                ]
            }
        }

        public struct DeleteMediaTarget: Codable {
            let cdn: UInt32
            let mediaId: Data

            var asParameters: [String: Any] {
                [
                    "cdn": self.cdn,
                    "mediaId": self.mediaId.asBase64Url
                ]
            }
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

        public enum CopyToMediaTierError: Int, Error {
            case badArgument = 400
            case invalidAuth = 401
            case forbidden = 403
            case sourceObjectNotFound = 410
            case outOfCapacity = 413
            case rateLimited = 429
        }

        public enum BackupUploadFormError: Int, Error {
            case badArgument = 400
            case invalidAuth = 401
            case forbidden = 403
            /// The backup file is too large (as reported by us in `backupByteLength`.
            case tooLarge = 413
            case rateLimited = 429
        }
    }
}

public protocol BackupRequestManager {

    /// Passthrough API for ``BackupAuthCredentialManager/fetchBackupServiceAuthForRegistration``.
    func fetchBackupServiceAuthForRegistration(
        key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth: ChatServiceAuth,
    ) async throws -> BackupServiceAuth

    /// Passthrough API for ``BackupAuthCredentialManager/fetchBackupServiceAuth``.
    func fetchBackupServiceAuth(
        for key: BackupKeyMaterial,
        localAci: Aci,
        auth: ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool
    ) async throws -> BackupServiceAuth

    /// - parameter backupByteLength: length in bytes of the encrypted backup file we will upload
    func fetchBackupUploadForm(
        backupByteLength: UInt32,
        auth: BackupServiceAuth
    ) async throws -> Upload.Form

    func fetchBackupMediaAttachmentUploadForm(
        auth: BackupServiceAuth,
        logger: PrefixedLogger?
    ) async throws -> Upload.Form

    func fetchMediaTierCdnRequestMetadata(cdn: Int32, auth: BackupServiceAuth) async throws -> MediaTierReadCredential

    func fetchBackupRequestMetadata(auth: BackupServiceAuth) async throws -> BackupReadCredential

    func copyToMediaTier(
        item: BackupArchive.Request.MediaItem,
        auth: BackupServiceAuth,
        logger: PrefixedLogger?
    ) async throws -> UInt32

    func copyToMediaTier(
        items: [BackupArchive.Request.MediaItem],
        auth: BackupServiceAuth
    ) async throws -> [BackupArchive.Response.BatchedBackupMediaResult]

    func listMediaObjects(
        cursor: String?,
        limit: UInt32?,
        auth: BackupServiceAuth
    ) async throws -> BackupArchive.Response.ListMediaResult

    func deleteMediaObjects(
        objects: [BackupArchive.Request.DeleteMediaTarget],
        auth: BackupServiceAuth
    ) async throws

    func fetchSVRBAuthCredential(
        key: MessageRootBackupKey,
        chatServiceAuth auth: ChatServiceAuth,
        forceRefresh: Bool,
    ) async throws -> LibSignalClient.Auth
}

extension BackupRequestManager {
    public func fetchBackupServiceAuth(
        for key: BackupKeyMaterial,
        localAci: Aci,
        auth: ChatServiceAuth,
    ) async throws -> BackupServiceAuth {
        return try await self.fetchBackupServiceAuth(
            for: key,
            localAci: localAci,
            auth: auth,
            forceRefreshUnlessCachedPaidCredential: false
        )
    }
}

public struct BackupRequestManagerImpl: BackupRequestManager {

    private let backupAuthCredentialManager: BackupAuthCredentialManager
    private let backupCDNCredentialStore: BackupCDNCredentialStore
    private let backupSettingsStore: BackupSettingsStore
    private let dateProvider: DateProvider
    private let db: any DB
    private let kvStore: KeyValueStore
    private let networkManager: NetworkManager

    init(
        backupAuthCredentialManager: BackupAuthCredentialManager,
        backupCDNCredentialStore: BackupCDNCredentialStore,
        backupSettingsStore: BackupSettingsStore,
        dateProvider: @escaping DateProvider,
        db: any DB,
        networkManager: NetworkManager
    ) {
        self.backupAuthCredentialManager = backupAuthCredentialManager
        self.backupCDNCredentialStore = backupCDNCredentialStore
        self.backupSettingsStore = backupSettingsStore
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = KeyValueStore(collection: "BackupRequestManager")
        self.networkManager = networkManager
    }

    // MARK: - Backup Auth

    public func fetchBackupServiceAuthForRegistration(
        key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth: ChatServiceAuth
    ) async throws -> BackupServiceAuth {
        return try await backupAuthCredentialManager.fetchBackupServiceAuthForRegistration(
            key: key,
            localAci: localAci,
            chatServiceAuth: chatServiceAuth,
        )
    }

    public func fetchBackupServiceAuth(
        for key: BackupKeyMaterial,
        localAci: Aci,
        auth: ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool
    ) async throws -> BackupServiceAuth {
        return try await backupAuthCredentialManager.fetchBackupServiceAuth(
            key: key,
            localAci: localAci,
            chatServiceAuth: auth,
            forceRefreshUnlessCachedPaidCredential: forceRefreshUnlessCachedPaidCredential,
        )
    }

    // MARK: - Upload Forms

    /// CDN upload form for uploading a backup
    public func fetchBackupUploadForm(
        backupByteLength: UInt32,
        auth: BackupServiceAuth
    ) async throws -> Upload.Form {
        owsAssertDebug(auth.type == .messages)
        do {
            return try await executeBackupService(
                auth: auth,
                requestFactory: { auth in
                    OWSRequestFactory.backupUploadFormRequest(
                        backupByteLength: backupByteLength,
                        auth: auth
                    )
                }
            )
        } catch let error {
            if
                let httpStatusCode = error.httpStatusCode,
                let error = BackupArchive.Response.BackupUploadFormError(rawValue: httpStatusCode)
            {
                throw error
            } else {
                throw error
            }
        }
    }

    /// CDN upload form for uploading backup media
    public func fetchBackupMediaAttachmentUploadForm(
        auth: BackupServiceAuth,
        logger: PrefixedLogger? = nil
    ) async throws -> Upload.Form {
        owsAssertDebug(auth.type == .media)
        return try await executeBackupService(
            auth: auth,
            requestFactory: { auth in
                OWSRequestFactory.backupMediaUploadFormRequest(
                    auth: auth,
                    logger: logger
                )
            }
        )
    }

    // MARK: - Backup Info

    private func fetchBackupCDNMetadata(auth: BackupServiceAuth) async throws -> BackupCDNMetadata {
        if let cachedCDNMetadata = db.read(block: { tx in
            backupCDNCredentialStore.backupCDNMetadata(
                authType: auth.type,
                now: dateProvider(),
                tx: tx
            )
        }) {
            return cachedCDNMetadata
        }

        let cdnMetadata: BackupCDNMetadata = try await executeBackupService(
            auth: auth,
            requestFactory: OWSRequestFactory.backupInfoRequest(auth:)
        )

        await db.awaitableWrite { tx in
            backupCDNCredentialStore.setBackupCDNMetadata(
                cdnMetadata,
                authType: auth.type,
                now: dateProvider(),
                currentBackupPlan: backupSettingsStore.backupPlan(tx: tx),
                tx: tx
            )
        }

        return cdnMetadata
    }

    // TODO: [Backups] Call this regularly, or move it somewhere it is called regularly
    /// Backup keep-alive request.  If not called, the backup may be deleted after 30 days.
    private func refreshBackupInfo(auth: BackupServiceAuth) async throws {
        _ = try await executeBackupServiceRequest(
            auth: auth,
            requestFactory: OWSRequestFactory.backupRefreshInfoRequest(auth:)
        )
    }

    // MARK: - Media

    /// Retrieve credentials used for reading from the CDN
    private func fetchCDNReadCredentials(
        cdn: Int32,
        auth: BackupServiceAuth
    ) async throws -> BackupCDNReadCredential {
        if let cachedCDNReadCredential = db.read(block: { tx in
            backupCDNCredentialStore.backupCDNReadCredential(
                cdnNumber: cdn,
                authType: auth.type,
                now: dateProvider(),
                tx: tx
            )
        }) {
            return cachedCDNReadCredential
        }

        let cdnReadCredential: BackupCDNReadCredential = try await executeBackupService(
            auth: auth,
            requestFactory: { OWSRequestFactory.fetchBackupCDNCredentials(auth: $0, cdn: cdn) }
        )

        await db.awaitableWrite { tx in
            backupCDNCredentialStore.setBackupCDNReadCredential(
                cdnReadCredential,
                cdnNumber: cdn,
                authType: auth.type,
                currentBackupPlan: backupSettingsStore.backupPlan(tx: tx),
                tx: tx
            )
        }

        return cdnReadCredential
    }

    public func fetchBackupRequestMetadata(auth: BackupServiceAuth) async throws -> BackupReadCredential {
        let metadata = try await fetchBackupCDNMetadata(auth: auth)
        let authCredential = try await fetchCDNReadCredentials(cdn: metadata.cdn, auth: auth)
        return BackupReadCredential(credential: authCredential, metadata: metadata)
    }

    public func fetchMediaTierCdnRequestMetadata(
        cdn: Int32,
        auth: BackupServiceAuth
    ) async throws -> MediaTierReadCredential {
        owsAssertDebug(auth.type == .media)
        let metadata = try await fetchBackupCDNMetadata(auth: auth)
        let authCredential = try await fetchCDNReadCredentials(cdn: cdn, auth: auth)
        return MediaTierReadCredential(cdn: cdn, credential: authCredential, metadata: metadata)
    }

    public func copyToMediaTier(
        item: BackupArchive.Request.MediaItem,
        auth: BackupServiceAuth,
        logger: PrefixedLogger? = nil
    ) async throws -> UInt32 {
        owsAssertDebug(auth.type == .media)
        do {
            let response = try await executeBackupServiceRequest(
                auth: auth,
                requestFactory: {
                    OWSRequestFactory.copyToMediaTier(
                        auth: $0,
                        item: item,
                        logger: logger
                    )
                }
            )
            if let error = BackupArchive.Response.CopyToMediaTierError.init(rawValue: response.responseStatusCode) {
                throw error
            }
            guard let bodyData = response.responseBodyData else {
                throw OWSAssertionError("Missing body data")
            }
            let dict = try JSONDecoder().decode([String: UInt32].self, from: bodyData)
            guard let cdn = dict["cdn"] else {
                throw OWSAssertionError("Missing cdn")
            }
            return cdn
        } catch let error {
            if
                let responseStatusCode = error.httpStatusCode,
                let typedError = BackupArchive.Response.CopyToMediaTierError.init(rawValue: responseStatusCode)
            {
                throw typedError
            } else {
                throw error
            }
        }
    }

    public func copyToMediaTier(
        items: [BackupArchive.Request.MediaItem],
        auth: BackupServiceAuth
    ) async throws -> [BackupArchive.Response.BatchedBackupMediaResult] {
        owsAssertDebug(auth.type == .media)
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
        auth: BackupServiceAuth
    ) async throws -> BackupArchive.Response.ListMediaResult {
        owsAssertDebug(auth.type == .media)
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

    public func deleteMediaObjects(objects: [BackupArchive.Request.DeleteMediaTarget], auth: BackupServiceAuth) async throws {
        owsAssertDebug(auth.type == .media)
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

    public func fetchSVRBAuthCredential(
        key: MessageRootBackupKey,
        chatServiceAuth auth: ChatServiceAuth,
        forceRefresh: Bool,
    ) async throws -> LibSignalClient.Auth {
        return try await backupAuthCredentialManager.fetchSVRBAuthCredential(
            key: key,
            chatServiceAuth: auth,
            forceRefresh: forceRefresh,
        )
    }

    // MARK: - Private utility methods

    private func executeBackupServiceRequest(
        auth: BackupServiceAuth,
        requestFactory: (BackupServiceAuth) -> TSRequest
    ) async throws -> HTTPResponse {
        return try await networkManager.asyncRequest(requestFactory(auth))
    }

    private func executeBackupService<T: Decodable>(
        auth: BackupServiceAuth,
        requestFactory: (BackupServiceAuth) -> TSRequest
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

public struct MediaTierReadCredential {

    public let cdn: Int32
    private let credential: BackupCDNReadCredential
    private let metadata: BackupCDNMetadata

    fileprivate init(
        cdn: Int32,
        credential: BackupCDNReadCredential,
        metadata: BackupCDNMetadata,
    ) {
        self.cdn = cdn
        self.credential = credential
        self.metadata = metadata
    }

    var isExpired: Bool {
        return credential.isExpired(now: Date())
    }

    var cdnAuthHeaders: HttpHeaders {
        return credential.headers
    }

    func mediaTierUrlPrefix() -> String {
        return "backups/\(metadata.backupDir)/\(metadata.mediaDir)"
    }
}

public struct BackupReadCredential {

    private let credential: BackupCDNReadCredential
    private let metadata: BackupCDNMetadata

    fileprivate init(
        credential: BackupCDNReadCredential,
        metadata: BackupCDNMetadata
    ) {
        self.credential = credential
        self.metadata = metadata
    }

    var isExpired: Bool {
        return credential.isExpired(now: Date())
    }

    var cdn: Int32 {
        return metadata.cdn
    }

    var cdnAuthHeaders: HttpHeaders {
        return credential.headers
    }

    func backupLocationUrl() -> String {
        return "backups/\(metadata.backupDir)/\(metadata.backupName)"
    }
}

// MARK: -

#if TESTABLE_BUILD

public class BackupRequestManagerMock: BackupRequestManager {

    init() {}

    public func fetchBackupServiceAuthForRegistration(
        key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth: ChatServiceAuth,
    ) async throws -> BackupServiceAuth {
        return BackupServiceAuth.mock(type: .media, backupLevel: .paid)
    }

    public func fetchBackupServiceAuth(
        for key: SignalServiceKit.BackupKeyMaterial,
        localAci: LibSignalClient.Aci,
        auth: SignalServiceKit.ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool
    ) async throws -> SignalServiceKit.BackupServiceAuth {
        return BackupServiceAuth.mock(type: .media, backupLevel: .paid)
    }

    public func fetchBackupUploadForm(
        backupByteLength: UInt32,
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws -> SignalServiceKit.Upload.Form {
        fatalError("Unimplemented")
    }

    public func fetchBackupMediaAttachmentUploadForm(
        auth: SignalServiceKit.BackupServiceAuth,
        logger: PrefixedLogger? = nil
    ) async throws -> SignalServiceKit.Upload.Form {
        fatalError("Unimplemented")
    }

    public func fetchMediaTierCdnRequestMetadata(
        cdn: Int32,
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws -> SignalServiceKit.MediaTierReadCredential {
        fatalError("Unimplemented")
    }

    public func fetchBackupRequestMetadata(
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws -> SignalServiceKit.BackupReadCredential {
        fatalError("Unimplemented")
    }

    public func copyToMediaTier(
        item: SignalServiceKit.BackupArchive.Request.MediaItem,
        auth: SignalServiceKit.BackupServiceAuth,
        logger: PrefixedLogger? = nil
    ) async throws -> UInt32 {
        fatalError("Unimplemented")
    }

    public func copyToMediaTier(
        items: [SignalServiceKit.BackupArchive.Request.MediaItem],
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws -> [SignalServiceKit.BackupArchive.Response.BatchedBackupMediaResult] {
        fatalError("Unimplemented")
    }

    var listMediaResults = [BackupArchive.Response.ListMediaResult]()

    public func listMediaObjects(
        cursor: String?,
        limit: UInt32?,
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws -> SignalServiceKit.BackupArchive.Response.ListMediaResult {
        return listMediaResults.popFirst()!
    }

    public func deleteMediaObjects(
        objects: [SignalServiceKit.BackupArchive.Request.DeleteMediaTarget],
        auth: SignalServiceKit.BackupServiceAuth
    ) async throws {
        fatalError("Unimplemented")
    }

    func redeemReceipt(receiptCredentialPresentation: Data) async throws {
        fatalError("Unimplemented")
    }

    public func fetchSVRBAuthCredential(
        key: SignalServiceKit.MessageRootBackupKey,
        chatServiceAuth auth: SignalServiceKit.ChatServiceAuth,
        forceRefresh: Bool
    ) async throws -> LibSignalClient.Auth {
        return LibSignalClient.Auth(username: "", password: "")
    }
}

#endif
