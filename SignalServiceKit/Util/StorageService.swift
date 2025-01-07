//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public struct StorageService {
    public enum StorageError: Error {
        case assertion

        case manifestEncryptionFailed(version: UInt64)
        case itemEncryptionFailed(identifier: StorageIdentifier)

        case manifestDecryptionFailed(version: UInt64)
        case itemDecryptionFailed(identifier: StorageIdentifier)

        case manifestProtoSerializationFailed(version: UInt64)
        case itemProtoSerializationFailed(identifier: StorageIdentifier)
        case readOperationProtoSerializationFailed
        case writeOperationProtoSerializationFailed

        case manifestContainerProtoDeserializationFailed
        case itemsContainerProtoDeserializationFailed
        case manifestProtoDeserializationFailed(version: UInt64)
        case itemProtoDeserializationFailed(identifier: StorageIdentifier)

        case networkError(statusCode: Int)
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
        case error(StorageError)
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
    ) async -> FetchLatestManifestResponse {
        var endpoint = "v1/storage/manifest"
        if let greaterThanVersion = greaterThanVersion {
            endpoint += "/version/\(greaterThanVersion)"
        }

        let response: StorageResponse
        do {
            response = try await storageRequest(
                withMethod: .get,
                endpoint: endpoint,
                chatServiceAuth: chatServiceAuth
            )
        } catch let storageError {
            return .error(storageError)
        }

        switch response.status {
        case .success:
            let encryptedManifestContainer: StorageServiceProtoStorageManifest
            do {
                encryptedManifestContainer = try StorageServiceProtoStorageManifest(serializedData: response.data)
            } catch {
                owsFailDebug("Failed to deserialize manifest container proto!")
                return .error(.manifestContainerProtoDeserializationFailed)
            }

            let decryptResult = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
                return DependenciesBridge.shared.svrKeyDeriver.decrypt(
                    keyType: .storageServiceManifest(version: encryptedManifestContainer.version),
                    encryptedData: encryptedManifestContainer.value,
                    tx: tx.asV2Read
                )
            })
            switch decryptResult {
            case .success(let manifestData):
                do {
                    let proto = try StorageServiceProtoManifestRecord(serializedData: manifestData)
                    return .latestManifest(proto)
                } catch {
                    owsFailDebug("Failed to deserialize manifest proto after successful decryption.")
                    return .error(.manifestProtoDeserializationFailed(version: encryptedManifestContainer.version))
                }
            case .masterKeyMissing, .cryptographyError:
                owsFailDebug("Failed to decrypt manifest!")
                return .error(.manifestDecryptionFailed(version: encryptedManifestContainer.version))
            }
        case .notFound:
            return .noExistingManifest
        case .noContent:
            return .noNewerManifest
        case .conflict:
            owsFailDebug("Got conflict response while fetching manifest!")
            return .error(.assertion)
        }
    }

    // MARK: -

    public enum UpdateManifestResult {
        /// We succeeded in updating the manifest!
        case success

        /// We found a manifest with a conflicting version number.
        case conflictingManifest(StorageServiceProtoManifestRecord)

        /// Something went wrong.
        case error(StorageError)
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
    ) async -> UpdateManifestResult {
        Logger.info("newItems: \(newItems.count), deletedIdentifiers: \(deletedIdentifiers.count), deleteAllExistingRecords: \(deleteAllExistingRecords)")

        var writeOperationBuilder = StorageServiceProtoWriteOperation.builder()

        // Encrypt the manifest
        let manifestData: Data
        do {
            manifestData = try manifest.serializedData()
        } catch {
            owsFailDebug("Failed to serialize manifest proto!")
            return .error(.manifestProtoSerializationFailed(version: manifest.version))
        }

        let encryptedManifestData: Data
        let encryptResult = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
            return DependenciesBridge.shared.svrKeyDeriver.encrypt(
                keyType: .storageServiceManifest(version: manifest.version),
                data: manifestData,
                tx: tx.asV2Read
            )
        })
        switch encryptResult {
        case .success(let data):
            encryptedManifestData = data
        case .masterKeyMissing, .cryptographyError:
            owsFailDebug("Failed to encrypt serialized manifest!")
            return .error(.manifestEncryptionFailed(version: manifest.version))
        }

        let manifestWrapperBuilder = StorageServiceProtoStorageManifest.builder(
            version: manifest.version,
            value: encryptedManifestData
        )
        writeOperationBuilder.setManifest(manifestWrapperBuilder.buildInfallibly())

        // Encrypt the new items
        var newStorageItems = [StorageServiceProtoStorageItem]()
        for item in newItems {
            let plaintextRecordData: Data
            do {
                plaintextRecordData = try item.record.serializedData()
            } catch {
                owsFailDebug("Failed to serialize item proto!")
                return .error(.itemProtoSerializationFailed(identifier: item.identifier))
            }

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
                        return DependenciesBridge.shared.svrKeyDeriver.encrypt(
                            keyType: .legacy_storageServiceRecord(identifier: item.identifier),
                            data: plaintextRecordData,
                            tx: tx.asV2Read
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
                owsFailDebug("Failed to encrypt serialized item proto!")
                return .error(.itemEncryptionFailed(identifier: item.identifier))
            }

            let itemWrapperBuilder = StorageServiceProtoStorageItem.builder(key: item.identifier.data, value: encryptedItemData)
            newStorageItems.append(itemWrapperBuilder.buildInfallibly())
        }
        writeOperationBuilder.setInsertItem(newStorageItems)

        // Flag the deleted keys
        writeOperationBuilder.setDeleteKey(deletedIdentifiers.map { $0.data })

        writeOperationBuilder.setDeleteAll(deleteAllExistingRecords)

        let writeOperationData: Data
        do {
            writeOperationData = try writeOperationBuilder.buildSerializedData()
        } catch {
            owsFailDebug("Failed to serialize write operation proto!")
            return .error(.writeOperationProtoSerializationFailed)
        }

        let response: StorageResponse
        do {
            response = try await storageRequest(
                withMethod: .put,
                endpoint: "v1/storage",
                body: writeOperationData,
                chatServiceAuth: chatServiceAuth
            )
        } catch let storageError {
            return .error(storageError)
        }

        switch response.status {
        case .success:
            // We expect a successful response to have no data
            if !response.data.isEmpty { owsFailDebug("unexpected response data") }
            return .success
        case .conflict:
            // Our version was out of date, we should've received a copy of the latest version
            let encryptedManifestContainer: StorageServiceProtoStorageManifest
            do {
                encryptedManifestContainer = try StorageServiceProtoStorageManifest(serializedData: response.data)
            } catch {
                owsFailDebug("Failed to deserialize manifest container proto!")
                return .error(.manifestContainerProtoDeserializationFailed)
            }

            let decryptionResult = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
                return DependenciesBridge.shared.svrKeyDeriver.decrypt(
                    keyType: .storageServiceManifest(version: encryptedManifestContainer.version),
                    encryptedData: encryptedManifestContainer.value,
                    tx: tx.asV2Read
                )
            })
            switch decryptionResult {
            case .success(let manifestData):
                do {
                    let proto = try StorageServiceProtoManifestRecord(serializedData: manifestData)
                    return .conflictingManifest(proto)
                } catch {
                    owsFailDebug("Failed to deserialize manifest proto after successful decryption!")
                    return .error(.manifestProtoDeserializationFailed(version: encryptedManifestContainer.version))
                }
            case .masterKeyMissing, .cryptographyError:
                owsFailDebug("Failed to decrypt conflicting manifest proto!")
                return .error(.manifestDecryptionFailed(version: encryptedManifestContainer.version))
            }
        case .notFound, .noContent:
            owsFailDebug("Unexpectedly got \(response.status) while updating manifest!")
            return .error(.assertion)
        }
    }

    // MARK: -

    public enum FetchItemsResult {
        case success([StorageItem])
        case error(StorageError)
    }

    /// Fetch a list of item records from the service
    ///
    /// The response will include only the items that could be found on the service
    public static func fetchItems(
        for identifiers: [StorageIdentifier],
        manifest: StorageServiceProtoManifestRecord,
        chatServiceAuth: ChatServiceAuth
    ) async -> FetchItemsResult {
        Logger.info("")

        let keys = StorageIdentifier.deduplicate(identifiers)

        // The server will 500 if we try and request too many keys at once.
        owsAssertDebug(keys.count <= 1024)

        if keys.isEmpty {
            return .success([])
        }

        var builder = StorageServiceProtoReadOperation.builder()
        builder.setReadKey(keys.map { $0.data })
        let data: Data
        do {
            data = try builder.buildSerializedData()
        } catch {
            owsFailDebug("Failed to serialize read operation proto!")
            return .error(.readOperationProtoSerializationFailed)
        }

        let response: StorageResponse
        do {
            response = try await storageRequest(
                withMethod: .put,
                endpoint: "v1/storage/read",
                body: data,
                chatServiceAuth: chatServiceAuth
            )
        } catch let storageError {
            return .error(storageError)
        }

        switch response.status {
        case .success:
            break
        case .conflict, .noContent, .notFound:
            owsFailDebug("Unexpectedly got \(response.status) while fetching items!")
            return .error(.assertion)
        }

        let itemsProto: StorageServiceProtoStorageItems
        do {
            itemsProto = try StorageServiceProtoStorageItems(serializedData: response.data)
        } catch {
            owsFailDebug("Failed to deserialize items container proto!")
            return .error(.itemsContainerProtoDeserializationFailed)
        }

        let keyToIdentifier = Dictionary(uniqueKeysWithValues: keys.map { ($0.data, $0) })

        var fetchedItems = [StorageItem]()
        for item in itemsProto.items {
            guard let itemIdentifier = keyToIdentifier[item.key] else {
                owsFailDebug("Missing identifier for fetched item!")
                return .error(.assertion)
            }

            let decryptedItemData: Data
            if let manifestRecordIkm: ManifestRecordIkm = .from(manifest: manifest) {
                do {
                    decryptedItemData = try manifestRecordIkm.decryptStorageItem(
                        encryptedRecordData: item.value,
                        itemIdentifier: itemIdentifier
                    )
                } catch {
                    owsFailDebug("Failed to decrypt record using recordIkm!")
                    return .error(.itemDecryptionFailed(identifier: itemIdentifier))
                }
            } else {
                /// If we don't yet have a `recordIkm` set we should
                /// continue using the SVR-derived record key.
                let itemDecryptionResult = SSKEnvironment.shared.databaseStorageRef.read(block: { tx in
                    return DependenciesBridge.shared.svrKeyDeriver.decrypt(
                        keyType: .legacy_storageServiceRecord(identifier: itemIdentifier),
                        encryptedData: item.value,
                        tx: tx.asV2Read
                    )
                })
                switch itemDecryptionResult {
                case .success(let itemData):
                    decryptedItemData = itemData
                case .masterKeyMissing, .cryptographyError:
                    owsFailDebug("Failed to decrypt record using SVR-derived key!")
                    return .error(.itemDecryptionFailed(identifier: itemIdentifier))
                }
            }

            do {
                let record = try StorageServiceProtoStorageRecord(serializedData: decryptedItemData)
                fetchedItems.append(StorageItem(identifier: itemIdentifier, record: record))
            } catch {
                owsFailDebug("Failed to deserialize item proto!")
                return .error(.itemProtoDeserializationFailed(identifier: itemIdentifier))
            }
        }

        return .success(fetchedItems)
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
    ) async throws(StorageError) -> StorageResponse {
        if method == .get {
            owsAssertDebug(body == nil)
        }

        let requestDescription = "SS \(method) \(endpoint)"

        let httpResponse: HTTPResponse
        do {
            let (username, password) = try await requestStorageAuth(chatServiceAuth: chatServiceAuth)

            let httpHeaders = OWSHttpHeaders()
            httpHeaders.addHeader("Content-Type", value: MimeType.applicationXProtobuf.rawValue, overwriteOnConflict: true)
            try httpHeaders.addAuthHeader(username: username, password: password)

            Logger.info("Sending… -> \(requestDescription)")

            let urlSession = self.urlSession
            urlSession.require2xxOr3xx = false
            httpResponse = try await urlSession.performRequest(
                endpoint,
                method: method,
                headers: httpHeaders.headers,
                body: body
            )
        } catch {
            Logger.warn("Failure. <- \(requestDescription): \(error)")
            throw .networkError(statusCode: 0)
        }

        let status: StorageResponse.Status
        switch httpResponse.responseStatusCode {
        case 200:
            status = .success
        case 204:
            status = .noContent
        case 409:
            status = .conflict
        case 404:
            status = .notFound
        default:
            owsFailDebug("Unexpected response status code: \(httpResponse.responseStatusCode)")
            throw .assertion
        }

        // We should always receive response data, for some responses it will be empty.
        guard let httpResponseData = httpResponse.responseBodyData else {
            owsFailDebug("Missing response data!")
            throw .assertion
        }

        Logger.info("HTTP \(httpResponse.responseStatusCode) <- \(requestDescription)")
        return StorageResponse(status: status, data: httpResponseData)
    }

    private static func requestStorageAuth(
        chatServiceAuth: ChatServiceAuth
    ) async throws -> (username: String, password: String) {
        let request = OWSRequestFactory.storageAuthRequest(auth: chatServiceAuth)

        let response = try await SSKEnvironment.shared.networkManagerRef
            .asyncRequest(request)

        guard let json = response.responseBodyJson else {
            throw OWSAssertionError("Missing or invalid JSON.")
        }
        guard let parser = ParamParser(responseObject: json) else {
            throw OWSAssertionError("Missing or invalid response.")
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
