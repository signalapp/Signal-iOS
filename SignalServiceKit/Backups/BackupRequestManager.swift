//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public extension BackupArchive {
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

public protocol BackupRequestManager {

    /// Creates a ``BackupServiceAuth``, which wraps a ``BackupAuthCredential``.
    /// Created from local ACI and the current valid backup credential. This
    /// `BackupServiceAuth` is used to authenticate all further `/v1/archive` operations.
    ///
    /// - parameter forceRefreshUnlessCachedPaidCredential: Forces a refresh if we have a cached
    /// credential that isn't ``BackupLevel.paid``. Default false. Set this to true if intending to check whether a
    /// paid credential is available.
    func fetchBackupServiceAuth(
        for credentialType: BackupAuthCredentialType,
        localAci: Aci,
        auth: ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool
    ) async throws -> BackupServiceAuth

    func fetchBackupUploadForm(auth: BackupServiceAuth) async throws -> Upload.Form

    func fetchBackupMediaAttachmentUploadForm(auth: BackupServiceAuth) async throws -> Upload.Form

    func fetchMediaTierCdnRequestMetadata(cdn: Int32, auth: BackupServiceAuth) async throws -> MediaTierReadCredential

    func fetchBackupRequestMetadata(auth: BackupServiceAuth) async throws -> BackupReadCredential

    func copyToMediaTier(
        item: BackupArchive.Request.MediaItem,
        auth: BackupServiceAuth
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

    func redeemReceipt(
        receiptCredentialPresentation: Data
    ) async throws
}

extension BackupRequestManager {
    func fetchBackupServiceAuth(
        for credentialType: BackupAuthCredentialType,
        localAci: Aci,
        auth: ChatServiceAuth,
    ) async throws -> BackupServiceAuth {
        return try await self.fetchBackupServiceAuth(
            for: credentialType,
            localAci: localAci,
            auth: auth,
            forceRefreshUnlessCachedPaidCredential: false
        )
    }
}

public struct BackupRequestManagerImpl: BackupRequestManager {

    private enum Constants {
        static let keyValueStoreCollectionName = "BackupRequestManager"

        static let cdnNumberOfDaysFetchIntervalInSeconds: TimeInterval = .day
        private static let keyValueStoreCdn2CredentialKey = "Cdn2Credential:"
        private static let keyValueStoreCdn3CredentialKey = "Cdn3Credential:"

        static func cdnCredentialCacheKey(for cdn: Int32, auth: BackupServiceAuth) -> String {
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

        static let backupInfoNumberOfDaysFetchIntervalInSeconds: TimeInterval = .day
        private static let keyValueStoreBackupInfoKeyPrefix = "BackupInfo:"
        private static let keyValueStoreLastBackupInfoFetchTimeKeyPrefix = "LastBackupInfoFetchTime:"

        static func backupInfoCacheInfo(for auth: BackupServiceAuth) -> (infoKey: String, lastfetchTimeKey: String) {
            (
                keyValueStoreBackupInfoKeyPrefix + auth.type.rawValue,
                keyValueStoreLastBackupInfoFetchTimeKeyPrefix + auth.type.rawValue
            )
        }
    }

    private let backupAuthCredentialManager: BackupAuthCredentialManager
    private let backupKeyMaterial: BackupKeyMaterial
    private let dateProvider: DateProvider
    private let db: any DB
    private let kvStore: KeyValueStore
    private let networkManager: NetworkManager

    init(
        backupAuthCredentialManager: BackupAuthCredentialManager,
        backupKeyMaterial: BackupKeyMaterial,
        dateProvider: @escaping DateProvider,
        db: any DB,
        networkManager: NetworkManager
    ) {
        self.backupAuthCredentialManager = backupAuthCredentialManager
        self.backupKeyMaterial = backupKeyMaterial
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = KeyValueStore(collection: Constants.keyValueStoreCollectionName)
        self.networkManager = networkManager
    }

    // MARK: - Backup Auth

    public func fetchBackupServiceAuth(
        for credentialType: BackupAuthCredentialType,
        localAci: Aci,
        auth: ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool
    ) async throws -> BackupServiceAuth {
        let (backupKey, privateKey) = try db.read { tx in
            let key = try backupKeyMaterial.backupKey(type: credentialType, tx: tx)
            let backupKey = key.deriveBackupId(aci: localAci)
            let privateKey = key.deriveEcKey(aci: localAci)
            return (backupKey, privateKey)
        }

        let authCredential = try await backupAuthCredentialManager.fetchBackupCredential(
            for: credentialType,
            localAci: localAci,
            chatServiceAuth: auth,
            forceRefreshUnlessCachedPaidCredential: forceRefreshUnlessCachedPaidCredential
        )

        return try BackupServiceAuth(
            backupKey: backupKey.asData,
            privateKey: privateKey,
            authCredential: authCredential,
            type: credentialType
        )
    }

    // MARK: - Upload Forms

    /// CDN upload form for uploading a backup
    public func fetchBackupUploadForm(auth: BackupServiceAuth) async throws -> Upload.Form {
        owsAssertDebug(auth.type == .messages)
        return try await executeBackupService(
            auth: auth,
            requestFactory: OWSRequestFactory.backupUploadFormRequest(auth:)
        )
    }

    /// CDN upload form for uploading backup media
    public func fetchBackupMediaAttachmentUploadForm(auth: BackupServiceAuth) async throws -> Upload.Form {
        owsAssertDebug(auth.type == .media)
        return try await executeBackupService(
            auth: auth,
            requestFactory: OWSRequestFactory.backupMediaUploadFormRequest(auth:)
        )
    }

    // MARK: - Backup Info

    /// Backup info provided by the server that is cached locally, so this can be discarded and
    /// refreshed at any time.
    ///
    /// `cdn`, `backupDir`, and `mediaDir` should be static as long as backup state doesn't
    /// significantly change (e.g. - changing subscription level, re-enabling backups after the grace period)
    fileprivate struct BackupRemoteInfo: Codable, Equatable {
        /// The CDN type where the message backup is stored. Media may be stored elsewhere.
        public let cdn: Int32

        /// The base directory of your backup data on the cdn. The message backup can befound in the
        /// returned cdn at /backupDir/backupName and stored media can be found at /backupDir/mediaDir/mediaId
        public let backupDir: String

        /// The prefix path component for media objects on a cdn. Stored media for mediaId
        /// can be found at /backupDir/mediaDir/mediaId.
        public let mediaDir: String

        /// The name of the most recent message backup on the cdn. The backup is at /backupDir/backupName
        public let backupName: String

        /// The amount of space used to store media
        let usedSpace: Int64
    }

    /// Fetch details about the current backup
    private func fetchBackupInfo(auth: BackupServiceAuth) async throws -> BackupRemoteInfo {
        let cacheInfo = Constants.backupInfoCacheInfo(for: auth)
        let cachedBackupInfo = db.read { tx -> BackupRemoteInfo? in
            let lastInfoFetchTime = kvStore.getDate(
                cacheInfo.lastfetchTimeKey,
                transaction: tx
            ) ?? .distantPast

            // Refresh backup info after 24 hours
            if abs(lastInfoFetchTime.timeIntervalSinceNow) < Constants.backupInfoNumberOfDaysFetchIntervalInSeconds {
                do {
                    if let backupInfo: BackupRemoteInfo = try kvStore.getCodableValue(
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

        let backupInfo: BackupRemoteInfo = try await executeBackupService(
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

    public func fetchBackupRequestMetadata(auth: BackupServiceAuth) async throws -> BackupReadCredential {
        let info = try await fetchBackupInfo(auth: auth)
        let authCredential = try await fetchCDNReadCredentials(cdn: info.cdn, auth: auth)
        return BackupReadCredential(credential: authCredential, info: info)
    }

    public func fetchMediaTierCdnRequestMetadata(
        cdn: Int32,
        auth: BackupServiceAuth
    ) async throws -> MediaTierReadCredential {
        owsAssertDebug(auth.type == .media)
        let info = try await fetchBackupInfo(auth: auth)
        let authCredential = try await fetchCDNReadCredentials(cdn: cdn, auth: auth)
        return MediaTierReadCredential(cdn: cdn, credential: authCredential, info: info)
    }

    public func copyToMediaTier(
        item: BackupArchive.Request.MediaItem,
        auth: BackupServiceAuth
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

    // MARK: - Subscriptions

    public func redeemReceipt(receiptCredentialPresentation: Data) async throws {
        _ = OWSRequestFactory.redeemReceipt(receiptCredentialPresentation: receiptCredentialPresentation)
        // TODO: Send the request built on the previous line to the server.
        throw OWSAssertionError("Not implemented.")
    }

    // MARK: - Private utility methods

    private func executeBackupServiceRequest(
        auth: BackupServiceAuth,
        requestFactory: (BackupServiceAuth) -> TSRequest
    ) async throws -> HTTPResponse {
        // TODO: Switch this back to true when reg supports websockets
        return try await networkManager.asyncRequest(requestFactory(auth), canUseWebSocket: false)
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

private struct CDNReadCredential: Codable {
    private static let cdnCredentialLifetimeInSeconds: TimeInterval = .day

    let createDate: Date
    let headers: HttpHeaders

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.headers = try container.decode(HttpHeaders.self, forKey: .headers)

        // createDate will default to current date, but can be overwritten during decodable initialization
        self.createDate = try container.decodeIfPresent(Date.self, forKey: .createDate) ?? Date()
    }

    var isExpired: Bool {
        return abs(createDate.timeIntervalSinceNow) >= CDNReadCredential.cdnCredentialLifetimeInSeconds
    }
}

public struct MediaTierReadCredential {

    public let cdn: Int32
    private let credential: CDNReadCredential
    private let info: BackupRequestManagerImpl.BackupRemoteInfo

    fileprivate init(
        cdn: Int32,
        credential: CDNReadCredential,
        info: BackupRequestManagerImpl.BackupRemoteInfo
    ) {
        self.cdn = cdn
        self.credential = credential
        self.info = info
    }

    var isExpired: Bool {
        return credential.isExpired
    }

    var cdnAuthHeaders: HttpHeaders {
        return credential.headers
    }

    func mediaTierUrlPrefix() -> String {
        return "backups/\(info.backupDir)/\(info.mediaDir)"
    }
}

public struct BackupReadCredential {

    private let credential: CDNReadCredential
    private let info: BackupRequestManagerImpl.BackupRemoteInfo

    fileprivate init(
        credential: CDNReadCredential,
        info: BackupRequestManagerImpl.BackupRemoteInfo
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

    var cdnAuthHeaders: HttpHeaders {
        return credential.headers
    }

    func backupLocationUrl() -> String {
        return "backups/\(info.backupDir)/\(info.backupName)"
    }
}
