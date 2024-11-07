//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
public import SignalRingRTC

@objc
public protocol StorageServiceManagerObjc {
    func recordPendingUpdates(updatedRecipientUniqueIds: [RecipientUniqueId])
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress])
    func recordPendingUpdates(updatedGroupV2MasterKeys: [Data])
    func recordPendingUpdates(updatedStoryDistributionListIds: [Data])

    // A convenience method that calls recordPendingUpdates(updatedGroupV2MasterKeys:).
    func recordPendingUpdates(groupModel: TSGroupModel)

    func recordPendingLocalAccountUpdates()

    /// Updates the local user's identity.
    ///
    /// Called during app launch, registration, and change number.
    func setLocalIdentifiers(_ localIdentifiers: LocalIdentifiersObjC)
}

public protocol StorageServiceManager: StorageServiceManagerObjc {
    /// The version of the latest known Storage Service manifest.
    func currentManifestVersion(tx: DBReadTransaction) -> UInt64
    /// Whether the latest-known Storage Service manifest contains a `recordIkm`.
    func currentManifestHasRecordIkm(tx: DBReadTransaction) -> Bool

    func recordPendingUpdates(callLinkRootKeys: [CallLinkRootKey])

    func backupPendingChanges(authedDevice: AuthedDevice)

    @discardableResult
    func restoreOrCreateManifestIfNecessary(authedDevice: AuthedDevice) -> Promise<Void>

    /// Creates a brand-new manifest based on local state, pointing to brand-new
    /// records.
    /// - Important
    /// This method is synchronized internally, and multiple calls will be
    /// serialized. However, this is an expensive operation (as all existing
    /// records need to be deleted and recreated from scratch), so callers
    /// should take care to avoid unnecessary calls.
    /// - Note
    /// The new manifest's version will be `currentVersion + 1`.
    func rotateManifest(authedDevice: AuthedDevice) async throws

    /// Wipes all local state related to Storage Service, without mutating
    /// remote state.
    ///
    /// - Note
    /// The expected behavior after calling this method is that the next time we
    /// perform a backup we will create a brand-new manifest with version 1, as
    /// we have no local manifest version. However, since we still (probably)
    /// have a remote manifest this backup will be rejected, and we'll merge in
    /// the remote manifest, then re-attempt our backup.
    ///
    /// This is a weird behavior to specifically want, and new callers who are
    /// interested in forcing a manifest recreation should probably prefer
    /// ``rotateManifest`` instead.
    func resetLocalData(transaction: DBWriteTransaction)

    /// Waits for pending restores to finish.
    ///
    /// When this is resolved, it means the current device has the latest state
    /// available on storage service.
    ///
    /// If this device believes there's new state available on storage service
    /// but the request to fetch it has failed, this Promise will be rejected.
    ///
    /// If the local device doesn't believe storage service has new state, this
    /// will resolve without performing any network requests.
    ///
    /// Due to the asynchronous nature of network requests, it's possible for
    /// another device to write to storage service at the same time the returned
    /// Promise resolves. Therefore, the precise behavior of this method is best
    /// described as: "if this device has knowledge that storage service has new
    /// state at the time this method is invoked, the returned Promise will be
    /// resolved after that state has been fetched".
    func waitForPendingRestores() -> Promise<Void>
}

// MARK: -

public struct StorageService {
    public enum StorageError: Error, IsRetryableProvider {
        case assertion
        case retryableAssertion
        case manifestEncryptionFailed(version: UInt64)
        case manifestDecryptionFailed(version: UInt64)
        /// Decryption succeeded (passed validation) but interpreting those bytes as a proto failed.
        case manifestProtoDeserializationFailed(version: UInt64)
        case itemEncryptionFailed(identifier: StorageIdentifier)
        case itemDecryptionFailed(identifier: StorageIdentifier)
        /// Decryption succeeded (passed validation) but interpreting those bytes as a proto failed.
        case itemProtoDeserializationFailed(identifier: StorageIdentifier)
        case networkError(statusCode: Int, underlyingError: Error)

        public var isRetryableProvider: Bool {
            switch self {
            case .assertion:
                return false
            case .retryableAssertion:
                return true
            case .manifestEncryptionFailed:
                return false
            case .manifestDecryptionFailed:
                return false
            case .manifestProtoDeserializationFailed:
                return false
            case .itemEncryptionFailed:
                return false
            case .itemDecryptionFailed:
                return false
            case .itemProtoDeserializationFailed:
                return false
            case .networkError(let statusCode, _):
                // If this is a server error, retry
                return statusCode >= 500
            }
        }

        public var errorUserInfo: [String: Any] {
            var userInfo: [String: Any] = [:]
            if case .networkError(_, let underlyingError) = self {
                userInfo[NSUnderlyingErrorKey] = underlyingError
            }
            return userInfo
        }
    }

    /// An identifier representing a given storage item.
    /// This can be used to fetch specific items from the service.
    public struct StorageIdentifier: Hashable, Codable {
        public static let identifierLength: UInt = 16
        public let data: Data
        public let type: StorageServiceProtoManifestRecordKeyType

        public init(data: Data, type: StorageServiceProtoManifestRecordKeyType) {
            if data.count != StorageIdentifier.identifierLength { owsFail("Initialized with invalid data") }
            self.data = data
            self.type = type
        }

        public static func generate(type: StorageServiceProtoManifestRecordKeyType) -> StorageIdentifier {
            return .init(data: Randomness.generateRandomBytes(identifierLength), type: type)
        }

        public func buildRecord() -> StorageServiceProtoManifestRecordKey {
            let builder = StorageServiceProtoManifestRecordKey.builder(data: data, type: type)
            return builder.buildInfallibly()
        }

        public static func deduplicate(_ identifiers: [StorageIdentifier]) -> [StorageIdentifier] {
            var identifierTypeMap = [Data: StorageIdentifier]()
            for identifier in identifiers {
                if let existingIdentifier = identifierTypeMap[identifier.data] {
                    owsFailDebug("Duplicate identifiers in manifest with types: \(identifier.type), \(existingIdentifier.type)")
                } else {
                    identifierTypeMap[identifier.data] = identifier
                }
            }
            return Array(identifierTypeMap.values)
        }
    }

    public struct StorageItem {
        public let identifier: StorageIdentifier
        public let record: StorageServiceProtoStorageRecord

        public var type: StorageServiceProtoManifestRecordKeyType { identifier.type }

        public var contactRecord: StorageServiceProtoContactRecord? {
            guard case .contact = type else { return nil }
            guard case .contact(let record) = record.record else {
                owsFailDebug("unexpectedly missing contact record")
                return nil
            }
            return record
        }

        public var groupV1Record: StorageServiceProtoGroupV1Record? {
            guard case .groupv1 = type else { return nil }
            guard case .groupV1(let record) = record.record else {
                owsFailDebug("unexpectedly missing group v1 record")
                return nil
            }
            return record
        }

        public var groupV2Record: StorageServiceProtoGroupV2Record? {
            guard case .groupv2 = type else { return nil }
            guard case .groupV2(let record) = record.record else {
                owsFailDebug("unexpectedly missing group v2 record")
                return nil
            }
            return record
        }

        public var accountRecord: StorageServiceProtoAccountRecord? {
            guard case .account = type else { return nil }
            guard case .account(let record) = record.record else {
                owsFailDebug("unexpectedly missing account record")
                return nil
            }
            return record
        }

        public var storyDistributionListRecord: StorageServiceProtoStoryDistributionListRecord? {
            guard case .storyDistributionList = type else { return nil }
            guard case .storyDistributionList(let record) = record.record else {
                owsFailDebug("unexpectedly missing story distribution list record")
                return nil
            }
            return record
        }

        public var callLinkRecord: StorageServiceProtoCallLinkRecord? {
            guard case .callLink = type else { return nil }
            guard case .callLink(let record) = record.record else {
                owsFailDebug("unexpectedly missing call link record")
                return nil
            }
            return record
        }

        public init(identifier: StorageIdentifier, contact: StorageServiceProtoContactRecord) {
            var storageRecord = StorageServiceProtoStorageRecord.builder()
            storageRecord.setRecord(.contact(contact))
            self.init(identifier: identifier, record: storageRecord.buildInfallibly())
        }

        public init(identifier: StorageIdentifier, groupV1: StorageServiceProtoGroupV1Record) {
            var storageRecord = StorageServiceProtoStorageRecord.builder()
            storageRecord.setRecord(.groupV1(groupV1))
            self.init(identifier: identifier, record: storageRecord.buildInfallibly())
        }

        public init(identifier: StorageIdentifier, groupV2: StorageServiceProtoGroupV2Record) {
            var storageRecord = StorageServiceProtoStorageRecord.builder()
            storageRecord.setRecord(.groupV2(groupV2))
            self.init(identifier: identifier, record: storageRecord.buildInfallibly())
        }

        public init(identifier: StorageIdentifier, account: StorageServiceProtoAccountRecord) {
            var storageRecord = StorageServiceProtoStorageRecord.builder()
            storageRecord.setRecord(.account(account))
            self.init(identifier: identifier, record: storageRecord.buildInfallibly())
        }

        public init(identifier: StorageIdentifier, storyDistributionList: StorageServiceProtoStoryDistributionListRecord) {
            var storageRecord = StorageServiceProtoStorageRecord.builder()
            storageRecord.setRecord(.storyDistributionList(storyDistributionList))
            self.init(identifier: identifier, record: storageRecord.buildInfallibly())
        }

        public init(identifier: StorageIdentifier, callLink: StorageServiceProtoCallLinkRecord) {
            var storageRecord = StorageServiceProtoStorageRecord.builder()
            storageRecord.setRecord(.callLink(callLink))
            self.init(identifier: identifier, record: storageRecord.buildInfallibly())
        }

        public init(identifier: StorageIdentifier, record: StorageServiceProtoStorageRecord) {
            self.identifier = identifier
            self.record = record
        }
    }

    public enum FetchLatestManifestResponse {
        case latestManifest(StorageServiceProtoManifestRecord)
        case noNewerManifest
        case noExistingManifest
    }

    /// Fetch the latest manifest from the storage service.
    /// If the greater than version is provided, only returns a manifest
    /// if a newer one exists on the service, otherwise indicates
    /// that there is no new content.
    ///
    /// Returns nil if a manifest has never been stored.
    public static func fetchLatestManifest(
        greaterThanVersion: UInt64? = nil,
        chatServiceAuth: ChatServiceAuth
    ) async throws -> FetchLatestManifestResponse {
        Logger.info("")

        var endpoint = "v1/storage/manifest"
        if let greaterThanVersion = greaterThanVersion {
            endpoint += "/version/\(greaterThanVersion)"
        }

        let response = try await storageRequest(
            withMethod: .get,
            endpoint: endpoint,
            chatServiceAuth: chatServiceAuth
        )

        switch response.status {
        case .success:
            let encryptedManifestContainer = try StorageServiceProtoStorageManifest(serializedData: response.data)
            let decryptResult = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
                return DependenciesBridge.shared.svr.decrypt(
                    keyType: .storageServiceManifest(version: encryptedManifestContainer.version),
                    encryptedData: encryptedManifestContainer.value,
                    transaction: tx.asV2Read
                )
            })
            switch decryptResult {
            case .success(let manifestData):
                do {
                    let proto = try StorageServiceProtoManifestRecord(serializedData: manifestData)
                    return .latestManifest(proto)
                } catch {
                    Logger.error("Failed to deserialize manifest proto after successful decryption.")
                    throw StorageError.manifestProtoDeserializationFailed(version: encryptedManifestContainer.version)
                }
            case .masterKeyMissing, .cryptographyError:
                throw StorageError.manifestDecryptionFailed(version: encryptedManifestContainer.version)
            }
        case .notFound:
            return .noExistingManifest
        case .noContent:
            return .noNewerManifest
        default:
            owsFailDebug("unexpected response \(response.status)")
            throw StorageError.retryableAssertion
        }
    }

    /// Update the manifest record on the service.
    ///
    /// If the version we are updating to already exists on the service,
    /// the conflicting manifest will return and the update will not
    /// have been applied until we resolve the conflicts.
    public static func updateManifest(
        _ manifest: StorageServiceProtoManifestRecord,
        newItems: [StorageItem],
        deletedIdentifiers: [StorageIdentifier],
        deleteAllExistingRecords: Bool,
        chatServiceAuth: ChatServiceAuth
    ) async throws -> StorageServiceProtoManifestRecord? {
        Logger.info("newItems: \(newItems.count), deletedIdentifiers: \(deletedIdentifiers.count), deleteAllExistingRecords: \(deleteAllExistingRecords)")

        var builder = StorageServiceProtoWriteOperation.builder()

        // Encrypt the manifest
        let manifestData = try manifest.serializedData()
        let encryptedManifestData: Data
        let encryptResult = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
            return DependenciesBridge.shared.svr.encrypt(
                keyType: .storageServiceManifest(version: manifest.version),
                data: manifestData,
                transaction: tx.asV2Read
            )
        })
        switch encryptResult {
        case .success(let data):
            encryptedManifestData = data
        case .masterKeyMissing, .cryptographyError:
            throw StorageError.manifestEncryptionFailed(version: manifest.version)
        }

        let manifestWrapperBuilder = StorageServiceProtoStorageManifest.builder(
            version: manifest.version,
            value: encryptedManifestData
        )
        builder.setManifest(manifestWrapperBuilder.buildInfallibly())

        // Encrypt the new items
        builder.setInsertItem(try newItems.map { item in
            let plaintextRecordData = try item.record.serializedData()

            let encryptedItemData = { () -> Data? in
                if let manifestRecordIkm: ManifestRecordIkm = .from(manifest: manifest) {
                    /// If we have a `recordIkm`, we should always use it.
                    return try? manifestRecordIkm.encryptStorageItem(
                        plaintextRecordData: plaintextRecordData,
                        itemIdentifier: item.identifier
                    )
                } else {
                    /// If we don't have a `recordIkm` yet, fall back to the
                    /// SVR-derived key.
                    let itemEncryptionResult = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
                        return DependenciesBridge.shared.svr.encrypt(
                            keyType: .legacy_storageServiceRecord(identifier: item.identifier),
                            data: plaintextRecordData,
                            transaction: tx.asV2Read
                        )
                    })
                    switch itemEncryptionResult {
                    case .success(let data):
                        return data
                    case .masterKeyMissing, .cryptographyError:
                        return nil
                    }
                }
            }()

            guard let encryptedItemData else {
                throw StorageError.itemEncryptionFailed(identifier: item.identifier)
            }

            let itemWrapperBuilder = StorageServiceProtoStorageItem.builder(key: item.identifier.data, value: encryptedItemData)
            return itemWrapperBuilder.buildInfallibly()
        })

        // Flag the deleted keys
        builder.setDeleteKey(deletedIdentifiers.map { $0.data })

        builder.setDeleteAll(deleteAllExistingRecords)

        let data = try builder.buildSerializedData()

        let response = try await storageRequest(
            withMethod: .put,
            endpoint: "v1/storage",
            body: data,
            chatServiceAuth: chatServiceAuth
        )

        switch response.status {
        case .success:
            // We expect a successful response to have no data
            if !response.data.isEmpty { owsFailDebug("unexpected response data") }
            return nil
        case .conflict:
            // Our version was out of date, we should've received a copy of the latest version
            let encryptedManifestContainer = try StorageServiceProtoStorageManifest(serializedData: response.data)

            let decryptionResult = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
                return DependenciesBridge.shared.svr.decrypt(
                    keyType: .storageServiceManifest(version: encryptedManifestContainer.version),
                    encryptedData: encryptedManifestContainer.value,
                    transaction: tx.asV2Read
                )
            })
            switch decryptionResult {
            case .success(let manifestData):
                do {
                    let proto = try StorageServiceProtoManifestRecord(serializedData: manifestData)
                    return proto
                } catch {
                    Logger.error("Failed to deserialize manifest proto after successful decryption.")
                    throw StorageError.manifestProtoDeserializationFailed(version: encryptedManifestContainer.version)
                }
            case .masterKeyMissing, .cryptographyError:
                throw StorageError.manifestDecryptionFailed(version: encryptedManifestContainer.version)
            }
        default:
            owsFailDebug("unexpected response \(response.status)")
            throw StorageError.retryableAssertion
        }
    }

    /// Fetch a list of item records from the service
    ///
    /// The response will include only the items that could be found on the service
    public static func fetchItems(
        for identifiers: [StorageIdentifier],
        manifest: StorageServiceProtoManifestRecord,
        chatServiceAuth: ChatServiceAuth
    ) async throws -> [StorageItem] {
        Logger.info("")

        let keys = StorageIdentifier.deduplicate(identifiers)

        // The server will 500 if we try and request too many keys at once.
        owsAssertDebug(keys.count <= 1024)

        if keys.isEmpty {
            return []
        }

        var builder = StorageServiceProtoReadOperation.builder()
        builder.setReadKey(keys.map { $0.data })
        let data = try builder.buildSerializedData()

        let response = try await storageRequest(
            withMethod: .put,
            endpoint: "v1/storage/read",
            body: data,
            chatServiceAuth: chatServiceAuth
        )

        guard case .success = response.status else {
            owsFailDebug("unexpected response \(response.status)")
            throw StorageError.retryableAssertion
        }

        let itemsProto = try StorageServiceProtoStorageItems(serializedData: response.data)

        let keyToIdentifier = Dictionary(uniqueKeysWithValues: keys.map { ($0.data, $0) })

        return try itemsProto.items.map { item throws -> StorageItem in
            guard let itemIdentifier = keyToIdentifier[item.key] else {
                owsFailDebug("missing identifier for fetched item")
                throw StorageError.assertion
            }

            let decryptedItemData: Data
            if let manifestRecordIkm: ManifestRecordIkm = .from(manifest: manifest) {
                do {
                    decryptedItemData = try manifestRecordIkm.decryptStorageItem(
                        encryptedRecordData: item.value,
                        itemIdentifier: itemIdentifier
                    )
                } catch {
                    Logger.error("Failed to decrypt record using recordIkm!")
                    throw StorageError.itemDecryptionFailed(identifier: itemIdentifier)
                }
            } else {
                /// If we don't yet have a `recordIkm` set we should
                /// continue using the SVR-derived record key.
                let itemDecryptionResult = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
                    return DependenciesBridge.shared.svr.decrypt(
                        keyType: .legacy_storageServiceRecord(identifier: itemIdentifier),
                        encryptedData: item.value,
                        transaction: tx.asV2Read
                    )
                })
                switch itemDecryptionResult {
                case .success(let itemData):
                    decryptedItemData = itemData
                case .masterKeyMissing, .cryptographyError:
                    Logger.error("Failed to decrypt record using SVR-derived key!")
                    throw StorageError.itemDecryptionFailed(identifier: itemIdentifier)
                }
            }

            do {
                let record = try StorageServiceProtoStorageRecord(serializedData: decryptedItemData)
                return StorageItem(identifier: itemIdentifier, record: record)
            } catch {
                Logger.error("Storage Service record decrypted successfully, but was malformed!")
                throw StorageError.itemProtoDeserializationFailed(identifier: itemIdentifier)
            }
        }
    }

    // MARK: -

    /// Wraps a `recordIkm` stored in a Storage Service manifest, which is used
    /// to encrypt/decrypt Storage Service records ("storage items").
    struct ManifestRecordIkm {
        static let expectedLength: UInt = 32

        private let data: Data
        private let manifestVersion: UInt64

        private init(data: Data, manifestVersion: UInt64) {
            self.data = data
            self.manifestVersion = manifestVersion
        }

        static func from(manifest: StorageServiceProtoManifestRecord) -> ManifestRecordIkm? {
            guard let recordIkm = manifest.recordIkm else {
                return nil
            }

            return ManifestRecordIkm(
                data: recordIkm,
                manifestVersion: manifest.version
            )
        }

        static func generateForNewManifest() -> Data {
            return Randomness.generateRandomBytes(Self.expectedLength)
        }

        // MARK: -

        func encryptStorageItem(
            plaintextRecordData: Data,
            itemIdentifier: StorageIdentifier
        ) throws -> Data {
            let recordKey = try recordKey(forIdentifier: itemIdentifier)

            return try Aes256GcmEncryptedData.encrypt(
                plaintextRecordData,
                key: recordKey
            ).concatenate()
        }

        func decryptStorageItem(
            encryptedRecordData: Data,
            itemIdentifier: StorageIdentifier
        ) throws -> Data {
            let recordKey = try recordKey(forIdentifier: itemIdentifier)

            return try Aes256GcmEncryptedData(
                concatenated: encryptedRecordData
            ).decrypt(key: recordKey)
        }

        private func recordKey(forIdentifier identifier: StorageIdentifier) throws -> Data {
            /// The info used to derive the key incorporates the identifier for
            /// this Storage Service record.
            let infoData = "20240801_SIGNAL_STORAGE_SERVICE_ITEM_".data(using: .utf8)! + identifier.data

            return try hkdf(
                outputLength: 32,
                inputKeyMaterial: data,
                salt: Data(),
                info: infoData
            ).asData
        }
    }

    // MARK: - Dependencies

    private static var urlSession: OWSURLSessionProtocol {
        return SSKEnvironment.shared.signalServiceRef.urlSessionForStorageService()
    }

    // MARK: - Storage Requests

    private struct StorageResponse {
        enum Status {
            case success
            case conflict
            case notFound
            case noContent
        }
        let status: Status
        let data: Data
    }

    private static func storageRequest(
        withMethod method: HTTPMethod,
        endpoint: String,
        body: Data? = nil,
        chatServiceAuth: ChatServiceAuth
    ) async throws -> StorageResponse {
        let requestDescription = "SS \(method) \(endpoint)"
        do {
            let (username, password) = try await SignalServiceRestClient.shared.requestStorageAuth(chatServiceAuth: chatServiceAuth).awaitable()

            if method == .get { assert(body == nil) }

            let httpHeaders = OWSHttpHeaders()
            httpHeaders.addHeader("Content-Type", value: MimeType.applicationXProtobuf.rawValue, overwriteOnConflict: true)
            try httpHeaders.addAuthHeader(username: username, password: password)

            Logger.info("Sending… -> \(requestDescription)")

            let urlSession = self.urlSession
            // Some 4xx responses are expected;
            // we'll discriminate the status code ourselves.
            urlSession.require2xxOr3xx = false
            let response = try await urlSession.performRequest(
                endpoint,
                method: method,
                headers: httpHeaders.headers,
                body: body
            )

            let status: StorageResponse.Status

            let statusCode = response.responseStatusCode
            switch statusCode {
            case 200:
                status = .success
            case 204:
                status = .noContent
            case 409:
                status = .conflict
            case 404:
                status = .notFound
            default:
                let error = OWSAssertionError("Unexpected statusCode: \(statusCode)")
                throw StorageError.networkError(statusCode: statusCode, underlyingError: error)
            }

            // We should always receive response data, for some responses it will be empty.
            guard let responseData = response.responseBodyData else {
                owsFailDebug("missing response data")
                throw StorageError.retryableAssertion
            }

            // The layers that use this only want to process 200 and 409 responses,
            // anything else we should raise as an error.

            Logger.info("HTTP \(statusCode) <- \(requestDescription)")

            return StorageResponse(status: status, data: responseData)
        } catch {
            Logger.warn("Failure. <- \(requestDescription): \(error)")
            throw StorageError.networkError(statusCode: 0, underlyingError: error)
        }
    }
}

// MARK: -

extension StorageServiceProtoManifestRecordKeyType: Codable {}

extension StorageServiceProtoManifestRecordKeyType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .unknown:
            return ".unknown"
        case .contact:
            return ".contact"
        case .groupv1:
            return ".groupv1"
        case .groupv2:
            return ".groupv2"
        case .account:
            return ".account"
        case .storyDistributionList:
            return ".storyDistributionList"
        case .callLink:
            return ".callLink"
        case .UNRECOGNIZED:
            return ".UNRECOGNIZED"
        }
    }
}
