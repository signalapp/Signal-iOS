//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public struct StorageService {
    public enum StorageError: Error, IsRetryableProvider {
        /// We found a manifest with a conflicting version number.
        case conflictingManifest(StorageServiceProtoManifestRecord)

        case manifestDecryptionFailed(version: UInt64)
        case manifestProtoDeserializationFailed(version: UInt64)

        case itemDecryptionFailed(identifier: StorageIdentifier)
        case itemProtoDeserializationFailed(identifier: StorageIdentifier)

        public var isRetryableProvider: Bool {
            switch self {
            case .conflictingManifest: true
            case .manifestDecryptionFailed: false
            case .manifestProtoDeserializationFailed: false
            case .itemDecryptionFailed: false
            case .itemProtoDeserializationFailed: false
            }
        }
    }

    public enum MasterKeySource: Equatable {
        case implicit
        case explicit(MasterKey)

        public func orIfImplicitUse(_ other: Self) -> Self {
            switch self {
            case .explicit:
                return self
            case .implicit:
                return other
            }
        }

        public static func ==(lhs: StorageService.MasterKeySource, rhs: StorageService.MasterKeySource) -> Bool {
            switch (lhs, rhs) {
            case (.implicit, .implicit):
                return true
            case (.explicit(let lhKey), .explicit(let rhKey)):
                return lhKey.rawData == rhKey.rawData
            default:
                return false
            }
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

    // MARK: -

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
        ifGreaterThanVersion greaterThanVersion: UInt64?,
        masterKey: MasterKey,
        chatServiceAuth: ChatServiceAuth,
    ) async throws -> FetchLatestManifestResponse {
        var endpoint = "v1/storage/manifest"
        if let greaterThanVersion {
            endpoint += "/version/\(greaterThanVersion)"
        }

        let httpResponse = try await storageRequest(
            withMethod: .get,
            endpoint: endpoint,
            chatServiceAuth: chatServiceAuth,
        )

        switch httpResponse.responseStatusCode {
        case 204:
            return .noNewerManifest
        case 404:
            return .noExistingManifest
        case 200:
            let encryptedManifestContainer = try StorageServiceProtoStorageManifest(
                serializedData: httpResponse.responseBodyData ?? Data(),
            )
            let manifestData: Data
            do {
                manifestData = try masterKey.decrypt(
                    keyType: .storageServiceManifest(version: encryptedManifestContainer.version),
                    encryptedData: encryptedManifestContainer.value,
                )
            } catch {
                throw StorageError.manifestDecryptionFailed(version: encryptedManifestContainer.version)
            }
            let proto: StorageServiceProtoManifestRecord
            do {
                proto = try StorageServiceProtoManifestRecord(serializedData: manifestData)
            } catch {
                throw StorageError.manifestProtoDeserializationFailed(version: encryptedManifestContainer.version)
            }
            return .latestManifest(proto)
        default:
            throw httpResponse.asError()
        }
    }

    // MARK: -

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
        masterKey: MasterKey,
        chatServiceAuth: ChatServiceAuth,
    ) async throws {
        Logger.info("newItems: \(newItems.count), deletedIdentifiers: \(deletedIdentifiers.count), deleteAllExistingRecords: \(deleteAllExistingRecords)")

        var writeOperationBuilder = StorageServiceProtoWriteOperation.builder()

        // Encrypt the manifest
        let manifestData = try manifest.serializedData()
        let encryptedManifestData = try masterKey.encrypt(
            keyType: .storageServiceManifest(version: manifest.version),
            data: manifestData,
        )

        let manifestWrapperBuilder = StorageServiceProtoStorageManifest.builder(
            version: manifest.version,
            value: encryptedManifestData,
        )
        writeOperationBuilder.setManifest(manifestWrapperBuilder.buildInfallibly())

        let manifestRecordIkm = ManifestRecordIkm.from(manifest: manifest)

        // Encrypt the new items
        var newStorageItems = [StorageServiceProtoStorageItem]()
        for item in newItems {
            let plaintextRecordData = try item.record.serializedData()

            let encryptedItemData: Data
            if let manifestRecordIkm {
                /// If we have a `recordIkm`, we should always use it.
                encryptedItemData = try manifestRecordIkm.encryptStorageItem(
                    plaintextRecordData: plaintextRecordData,
                    itemIdentifier: item.identifier,
                )
            } else {
                /// If we don't have a `recordIkm` yet, fall back to the
                /// SVR-derived key.
                encryptedItemData = try masterKey.encrypt(
                    keyType: .legacy_storageServiceRecord(identifier: item.identifier),
                    data: plaintextRecordData,
                )
            }

            let itemWrapperBuilder = StorageServiceProtoStorageItem.builder(key: item.identifier.data, value: encryptedItemData)
            newStorageItems.append(itemWrapperBuilder.buildInfallibly())
        }
        writeOperationBuilder.setInsertItem(newStorageItems)

        // Flag the deleted keys
        writeOperationBuilder.setDeleteKey(deletedIdentifiers.map { $0.data })

        writeOperationBuilder.setDeleteAll(deleteAllExistingRecords)

        let writeOperationData = try writeOperationBuilder.buildSerializedData()

        let httpResponse = try await storageRequest(
            withMethod: .put,
            endpoint: "v1/storage",
            body: writeOperationData,
            chatServiceAuth: chatServiceAuth,
        )

        switch httpResponse.responseStatusCode {
        case 200:
            return
        case 409:
            // Our version was out of date, we should've received a copy of the latest version
            let encryptedManifestContainer = try StorageServiceProtoStorageManifest(
                serializedData: httpResponse.responseBodyData ?? Data(),
            )
            let manifestData: Data
            do {
                manifestData = try masterKey.decrypt(
                    keyType: .storageServiceManifest(version: encryptedManifestContainer.version),
                    encryptedData: encryptedManifestContainer.value,
                )
            } catch {
                throw StorageError.manifestDecryptionFailed(version: encryptedManifestContainer.version)
            }
            let proto: StorageServiceProtoManifestRecord
            do {
                proto = try StorageServiceProtoManifestRecord(serializedData: manifestData)
            } catch {
                throw StorageError.manifestProtoDeserializationFailed(version: encryptedManifestContainer.version)
            }
            throw StorageError.conflictingManifest(proto)
        default:
            throw httpResponse.asError()
        }
    }

    // MARK: -

    /// Fetch a list of item records from the service
    ///
    /// The response will include only the items that could be found on the service
    public static func fetchItems(
        for identifiers: [StorageIdentifier],
        manifest: StorageServiceProtoManifestRecord,
        masterKey: MasterKey,
        chatServiceAuth: ChatServiceAuth,
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

        let httpResponse = try await storageRequest(
            withMethod: .put,
            endpoint: "v1/storage/read",
            body: data,
            chatServiceAuth: chatServiceAuth,
        )

        guard httpResponse.responseStatusCode == 200 else {
            throw httpResponse.asError()
        }

        let itemsProto = try StorageServiceProtoStorageItems(serializedData: httpResponse.responseBodyData ?? Data())

        let keyToIdentifier = Dictionary(uniqueKeysWithValues: keys.map { ($0.data, $0) })
        let manifestRecordIkm = ManifestRecordIkm.from(manifest: manifest)

        var fetchedItems = [StorageItem]()
        for item in itemsProto.items {
            guard let itemIdentifier = keyToIdentifier[item.key] else {
                owsFailDebug("we got an item we didn't ask for")
                continue
            }

            let decryptedItemData: Data
            do {
                if let manifestRecordIkm {
                    decryptedItemData = try manifestRecordIkm.decryptStorageItem(
                        encryptedRecordData: item.value,
                        itemIdentifier: itemIdentifier,
                    )
                } else {
                    /// If we don't yet have a `recordIkm` set we should
                    /// continue using the SVR-derived record key.
                    decryptedItemData = try masterKey.decrypt(
                        keyType: .legacy_storageServiceRecord(identifier: itemIdentifier),
                        encryptedData: item.value,
                    )
                }
            } catch {
                throw StorageError.itemDecryptionFailed(identifier: itemIdentifier)
            }

            do {
                let record = try StorageServiceProtoStorageRecord(serializedData: decryptedItemData)
                fetchedItems.append(StorageItem(identifier: itemIdentifier, record: record))
            } catch {
                throw StorageError.itemProtoDeserializationFailed(identifier: itemIdentifier)
            }
        }

        return fetchedItems
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
                manifestVersion: manifest.version,
            )
        }

        static func generateForNewManifest() -> Data {
            return Randomness.generateRandomBytes(Self.expectedLength)
        }

        // MARK: -

        func encryptStorageItem(
            plaintextRecordData: Data,
            itemIdentifier: StorageIdentifier,
        ) throws -> Data {
            let recordKey = try recordKey(forIdentifier: itemIdentifier)

            return try Aes256GcmEncryptedData.encrypt(
                plaintextRecordData,
                key: recordKey,
            ).concatenate()
        }

        func decryptStorageItem(
            encryptedRecordData: Data,
            itemIdentifier: StorageIdentifier,
        ) throws -> Data {
            let recordKey = try recordKey(forIdentifier: itemIdentifier)

            return try Aes256GcmEncryptedData(
                concatenated: encryptedRecordData,
            ).decrypt(key: recordKey)
        }

        private func recordKey(forIdentifier identifier: StorageIdentifier) throws -> Data {
            /// The info used to derive the key incorporates the identifier for
            /// this Storage Service record.
            let infoData = Data("20240801_SIGNAL_STORAGE_SERVICE_ITEM_".utf8) + identifier.data

            return try hkdf(
                outputLength: 32,
                inputKeyMaterial: data,
                salt: Data(),
                info: infoData,
            )
        }
    }

    // MARK: - Dependencies

    private static var urlSession: OWSURLSessionProtocol {
        return SSKEnvironment.shared.signalServiceRef.urlSessionForStorageService()
    }

    // MARK: - Storage Requests

    private static func storageRequest(
        withMethod method: HTTPMethod,
        endpoint: String,
        body: Data? = nil,
        chatServiceAuth: ChatServiceAuth,
    ) async throws -> HTTPResponse {
        if method == .get {
            owsAssertDebug(body == nil)
        }

        let requestDescription = "SS \(method) \(endpoint)"

        let httpResponse: HTTPResponse
        do {
            let (username, password) = try await requestStorageAuth(chatServiceAuth: chatServiceAuth)

            var httpHeaders = HttpHeaders()
            httpHeaders.addHeader("Content-Type", value: MimeType.applicationXProtobuf.rawValue, overwriteOnConflict: true)
            httpHeaders.addAuthHeader(username: username, password: password)

            Logger.info("Sending… -> \(requestDescription)")

            let urlSession = self.urlSession
            urlSession.require2xxOr3xx = false
            httpResponse = try await urlSession.performRequest(
                endpoint,
                method: method,
                headers: httpHeaders,
                body: body,
            )
        } catch {
            Logger.warn("Failure. <- \(requestDescription): \(error)")
            throw error
        }

        Logger.info("HTTP \(httpResponse.responseStatusCode) <- \(requestDescription)")
        return httpResponse
    }

    private static func requestStorageAuth(
        chatServiceAuth: ChatServiceAuth,
    ) async throws -> (username: String, password: String) {
        let request = OWSRequestFactory.storageAuthRequest(auth: chatServiceAuth)

        let response = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request)

        guard let parser = response.responseBodyParamParser else {
            throw OWSAssertionError("Missing or invalid JSON.")
        }

        let username: String = try parser.required(key: "username")
        let password: String = try parser.required(key: "password")

        return (username: username, password: password)
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
