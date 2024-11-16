//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

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
    }
}

public protocol MessageBackupRequestManager {

    /// Creates a ``MessageBackupServiceAuth``, which wraps a ``MessageBackupAuthCredential``.
    /// Created from local ACI and the current valid backup credential. This
    /// `MessageBackupServiceAuth` is used to authenticate all further `/v1/archive` operations.
    ///
    /// - Parameter purpose
    /// The intended purpose for this service auth. This influences the steps
    /// taken in fetching the credentials underlying the returned service auth.
    func fetchBackupServiceAuth(
        for credentialType: MessageBackupAuthCredentialType,
        localAci: Aci,
        auth: ChatServiceAuth
    ) async throws -> MessageBackupServiceAuth

    func reserveBackupId(localAci: Aci, auth: ChatServiceAuth) async throws

    func registerBackupKeys(localAci: Aci, auth: ChatServiceAuth) async throws

    func fetchBackupUploadForm(auth: MessageBackupServiceAuth) async throws -> Upload.Form

    func fetchBackupMediaAttachmentUploadForm(auth: MessageBackupServiceAuth) async throws -> Upload.Form

    func fetchBackupInfo(auth: MessageBackupServiceAuth) async throws -> MessageBackupRemoteInfo

    func refreshBackupInfo(auth: MessageBackupServiceAuth) async throws

    func fetchMediaTierCdnRequestMetadata(cdn: Int32, auth: MessageBackupServiceAuth) async throws -> MediaTierReadCredential

    func fetchBackupRequestMetadata(auth: MessageBackupServiceAuth) async throws -> BackupReadCredential

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

    private enum Constants {
        static let keyValueStoreCollectionName = "MessageBackupRequestManager"

        static let cdnNumberOfDaysFetchIntervalInSeconds: TimeInterval = kDayInterval
        private static let keyValueStoreCdn2CredentialKey = "Cdn2Credential:"
        private static let keyValueStoreCdn3CredentialKey = "Cdn3Credential:"

        static func cdnCredentialCacheKey(for cdn: Int32, auth: MessageBackupServiceAuth) -> String {
            switch cdn {
            case 2:
                return Constants.keyValueStoreCdn2CredentialKey + auth.type.rawValue
            case 3:
                return Constants.keyValueStoreCdn3CredentialKey + auth.type.rawValue
            default:
                owsFailDebug("Invalid CDN version requested")
                return Constants.keyValueStoreCdn3CredentialKey + auth.type.rawValue
            }
        }

        static let backupInfoNumberOfDaysFetchIntervalInSeconds: TimeInterval = kDayInterval
        private static let keyValueStoreBackupInfoKeyPrefix = "BackupInfo:"
        private static let keyValueStoreLastBackupInfoFetchTimeKeyPrefix = "LastBackupInfoFetchTime:"

        static func backupInfoCacheInfo(for auth: MessageBackupServiceAuth) -> (infoKey: String, lastfetchTimeKey: String) {
            (
                keyValueStoreBackupInfoKeyPrefix + auth.type.rawValue,
                keyValueStoreLastBackupInfoFetchTimeKeyPrefix + auth.type.rawValue
            )
        }
    }

    private let dateProvider: DateProvider
    private let db: any DB
    private let kvStore: KeyValueStore
    private let messageBackupAuthCredentialManager: MessageBackupAuthCredentialManager
    private let messageBackupKeyMaterial: MessageBackupKeyMaterial
    private let networkManager: NetworkManager

    init(
        dateProvider: @escaping DateProvider,
        db: any DB,
        messageBackupAuthCredentialManager: MessageBackupAuthCredentialManager,
        messageBackupKeyMaterial: MessageBackupKeyMaterial,
        networkManager: NetworkManager
    ) {
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = KeyValueStore(collection: Constants.keyValueStoreCollectionName)
        self.messageBackupAuthCredentialManager = messageBackupAuthCredentialManager
        self.messageBackupKeyMaterial = messageBackupKeyMaterial
        self.networkManager = networkManager
    }

    // MARK: - Reserve Backup

    /// Onetime request to reserve this backup ID.
    public func reserveBackupId(localAci: Aci, auth: ChatServiceAuth) async throws {
        let messageBackupRequestContext = try db.read { tx in
            BackupAuthCredentialRequestContext.create(
                backupKey: try messageBackupKeyMaterial.backupKey(type: .messages, tx: tx).serialize(),
                aci: localAci.rawUUID
            )
        }
        let mediaBackupRequestContext = try db.read { tx in
            return BackupAuthCredentialRequestContext.create(
                backupKey: try messageBackupKeyMaterial.backupKey(type: .media, tx: tx).serialize(),
                aci: localAci.rawUUID
            )
        }
        let base64MessageRequestContext = messageBackupRequestContext.getRequest().serialize().asData.base64EncodedString()
        let base64MediaRequestContext = mediaBackupRequestContext.getRequest().serialize().asData.base64EncodedString()
        let request = try OWSRequestFactory.reserveBackupId(
            backupId: base64MessageRequestContext,
            mediaBackupId: base64MediaRequestContext,
            auth: auth
        )
        // TODO: Switch this back to true when reg supports websockets
        _ = try await networkManager.asyncRequest(request, canUseWebSocket: false)
    }

    // MARK: - Backup Auth

    public func fetchBackupServiceAuth(
        for credentialType: MessageBackupAuthCredentialType,
        localAci: Aci,
        auth: ChatServiceAuth
    ) async throws -> MessageBackupServiceAuth {
        let (backupKey, privateKey) = try db.read { tx in
            let key = try messageBackupKeyMaterial.backupKey(type: credentialType, tx: tx)
            let backupKey = key.deriveBackupId(aci: localAci)
            let privateKey = key.deriveEcKey(aci: localAci)
            return (backupKey, privateKey)
        }

        let authCredential = try await messageBackupAuthCredentialManager.fetchBackupCredential(
            for: credentialType,
            localAci: localAci,
            chatServiceAuth: auth
        )

        return try MessageBackupServiceAuth(
            backupKey: backupKey.asData,
            privateKey: privateKey,
            authCredential: authCredential,
            type: credentialType
        )
    }

    // MARK: - Register Backup

    /// Onetime request to register the backup public key.
    public func registerBackupKeys(localAci: Aci, auth: ChatServiceAuth) async throws {
        let backupAuth = try await fetchBackupServiceAuth(
            for: .messages,
            localAci: localAci,
            auth: auth
        )
        _ = try await executeBackupServiceRequest(
            auth: backupAuth,
            requestFactory: OWSRequestFactory.backupSetPublicKeyRequest(auth:)
        )

        let mediaBackupAuth = try await fetchBackupServiceAuth(
            for: .media,
            localAci: localAci,
            auth: auth
        )
        _ = try await executeBackupServiceRequest(
            auth: mediaBackupAuth,
            requestFactory: OWSRequestFactory.backupSetPublicKeyRequest(auth:)
        )
    }

    // MARK: - Upload Forms

    /// CDN upload form for uploading a backup
    public func fetchBackupUploadForm(auth: MessageBackupServiceAuth) async throws -> Upload.Form {
        owsAssertDebug(auth.type == .messages)
        return try await executeBackupService(
            auth: auth,
            requestFactory: OWSRequestFactory.backupUploadFormRequest(auth:)
        )
    }

    /// CDN upload form for uploading backup media
    public func fetchBackupMediaAttachmentUploadForm(auth: MessageBackupServiceAuth) async throws -> Upload.Form {
        owsAssertDebug(auth.type == .media)
        return try await executeBackupService(
            auth: auth,
            requestFactory: OWSRequestFactory.backupMediaUploadFormRequest(auth:)
        )
    }

    // MARK: - Backup Info

    /// Fetch details about the current backup
    public func fetchBackupInfo(auth: MessageBackupServiceAuth) async throws -> MessageBackupRemoteInfo {
        let cacheInfo = Constants.backupInfoCacheInfo(for: auth)
        let cachedBackupInfo = db.read { tx -> MessageBackupRemoteInfo? in
            let lastInfoFetchTime = kvStore.getDate(
                cacheInfo.lastfetchTimeKey,
                transaction: tx
            ) ?? .distantPast

            // Refresh backup info after 24 hours
            if abs(lastInfoFetchTime.timeIntervalSinceNow) < Constants.backupInfoNumberOfDaysFetchIntervalInSeconds {
                do {
                    if let backupInfo: MessageBackupRemoteInfo = try kvStore.getCodableValue(
                        forKey: cacheInfo.infoKey,
                        transaction: tx
                    ) {
                        return backupInfo
                    }
                } catch {
                    // Failure to deserialize this object should be ok since it's simply
                    // a cache of the remote info and can be refetched.  But still worth
                    // a log entry in case something results in repeated errors.
                    Logger.debug("Couldn't decode backup info, fetch remotely")
                }
            }
            return nil
        }

        if let cachedBackupInfo {
            return cachedBackupInfo
        }

        let backupInfo: MessageBackupRemoteInfo = try await executeBackupService(
            auth: auth,
            requestFactory: OWSRequestFactory.backupInfoRequest(auth:)
        )

        try await db.awaitableWrite { tx in
            try kvStore.setCodable(
                backupInfo,
                key: cacheInfo.infoKey,
                transaction: tx
            )

            kvStore.setDate(
                dateProvider(),
                key: cacheInfo.lastfetchTimeKey,
                transaction: tx
            )
        }

        return backupInfo
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
        owsAssertDebug(auth.type == .messages)
        _ = try await executeBackupServiceRequest(
            auth: auth,
            requestFactory: OWSRequestFactory.deleteBackupRequest(auth:)
        )
    }

    // MARK: - Media

    /// Retrieve credentials used for reading from the CDN
    private func fetchCDNReadCredentials(
        cdn: Int32,
        auth: MessageBackupServiceAuth
    ) async throws -> CDNReadCredential {
        let cacheKey = Constants.cdnCredentialCacheKey(for: cdn, auth: auth)
        let result = db.read { tx -> CDNReadCredential? in
            do {
                if
                    let backupAuthCredential: CDNReadCredential = try kvStore.getCodableValue(forKey: cacheKey, transaction: tx),
                    backupAuthCredential.isExpired.negated
                {
                    return backupAuthCredential
                }
            } catch {
                // Failure to deserialize this object should be ok since the credential
                // can be refetched.  But still worth a log entry in case something
                // results in repeated errors.
                Logger.info("Couldn't decode backup info, fetch remotely")
            }
            return nil
        }

        if let result {
            return result
        }

        let authCredential: CDNReadCredential = try await executeBackupService(
            auth: auth,
            requestFactory: { OWSRequestFactory.fetchCDNCredentials(auth: $0, cdn: cdn) }
        )

        try await db.awaitableWrite { tx in
            try kvStore.setCodable(authCredential, key: cacheKey, transaction: tx)
        }

        return authCredential
    }

    public func fetchBackupRequestMetadata(auth: MessageBackupServiceAuth) async throws -> BackupReadCredential {
        let info = try await fetchBackupInfo(auth: auth)
        let authCredential = try await fetchCDNReadCredentials(cdn: info.cdn, auth: auth)
        return BackupReadCredential(credential: authCredential, info: info)
    }

    public func fetchMediaTierCdnRequestMetadata(
        cdn: Int32,
        auth: MessageBackupServiceAuth
    ) async throws -> MediaTierReadCredential {
        owsAssertDebug(auth.type == .media)
        let info = try await fetchBackupInfo(auth: auth)
        let authCredential = try await fetchCDNReadCredentials(cdn: cdn, auth: auth)
        return MediaTierReadCredential(cdn: cdn, credential: authCredential, info: info)
    }

    public func copyToMediaTier(
        item: MessageBackup.Request.MediaItem,
        auth: MessageBackupServiceAuth
    ) async throws -> UInt32 {
        owsAssertDebug(auth.type == .media)
        do {
            let response = try await executeBackupServiceRequest(
                auth: auth,
                requestFactory: {
                    OWSRequestFactory.copyToMediaTier(
                        auth: $0,
                        item: item
                    )
                }
            )
            if let error = MessageBackup.Response.CopyToMediaTierError.init(rawValue: response.responseStatusCode) {
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
                let typedError = MessageBackup.Response.CopyToMediaTierError.init(rawValue: responseStatusCode)
            {
                throw typedError
            } else {
                throw error
            }
        }
    }

    public func copyToMediaTier(
        items: [MessageBackup.Request.MediaItem],
        auth: MessageBackupServiceAuth
    ) async throws -> [MessageBackup.Response.BatchedBackupMediaResult] {
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
        auth: MessageBackupServiceAuth
    ) async throws -> MessageBackup.Response.ListMediaResult {
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

    public func deleteMediaObjects(objects: [MessageBackup.Request.DeleteMediaTarget], auth: MessageBackupServiceAuth) async throws {
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

    // MARK: - Subscriptions

    public func redeemReceipt(receiptCredentialPresentation: Data) async throws {
        _ = OWSRequestFactory.redeemReceipt(receiptCredentialPresentation: receiptCredentialPresentation)
    }

    // MARK: - Private utility methods

    private func executeBackupServiceRequest(
        auth: MessageBackupServiceAuth,
        requestFactory: (MessageBackupServiceAuth) -> TSRequest
    ) async throws -> HTTPResponse {
        // TODO: Switch this back to true when reg supports websockets
        return try await networkManager.asyncRequest(requestFactory(auth), canUseWebSocket: false)
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

private struct CDNReadCredential: Codable, Equatable {
    private static let cdnCredentialLifetimeInSeconds = kDayInterval

    let createDate: Date
    let headers: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.headers = try container.decode([String: String].self, forKey: .headers)

        // createDate will default to current date, but can be overwritten during decodable initialization
        self.createDate = try container.decodeIfPresent(Date.self, forKey: .createDate) ?? Date()
    }

    var isExpired: Bool {
        return abs(createDate.timeIntervalSinceNow) >= CDNReadCredential.cdnCredentialLifetimeInSeconds
    }
}

public struct MediaTierReadCredential: Equatable {

    public let cdn: Int32
    private let credential: CDNReadCredential
    private let info: MessageBackupRemoteInfo

    fileprivate init(
        cdn: Int32,
        credential: CDNReadCredential,
        info: MessageBackupRemoteInfo
    ) {
        self.cdn = cdn
        self.credential = credential
        self.info = info
    }

    var isExpired: Bool {
        return credential.isExpired
    }

    var cdnAuthHeaders: [String: String] {
        return credential.headers
    }

    func mediaTierUrlPrefix() -> String {
        return "backups/\(info.backupDir)/\(info.mediaDir)"
    }
}

public struct BackupReadCredential: Equatable {

    private let credential: CDNReadCredential
    private let info: MessageBackupRemoteInfo

    fileprivate init(
        credential: CDNReadCredential,
        info: MessageBackupRemoteInfo
    ) {
        self.credential = credential
        self.info = info
    }

    var isExpired: Bool {
        return credential.isExpired
    }

    var cdn: Int32 {
        return info.cdn
    }

    var cdnAuthHeaders: [String: String] {
        return credential.headers
    }

    func backupLocationUrl() -> String {
        return "backups/\(info.backupDir)/\(info.backupName)"
    }
}
