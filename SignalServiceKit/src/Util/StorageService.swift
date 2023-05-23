//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public protocol StorageServiceManager {
    func recordPendingDeletions(deletedGroupV1Ids: [Data])

    func recordPendingUpdates(updatedAccountIds: [AccountId])
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress])
    func recordPendingUpdates(updatedGroupV1Ids: [Data])
    func recordPendingUpdates(updatedGroupV2MasterKeys: [Data])
    func recordPendingUpdates(updatedStoryDistributionListIds: [Data])

    // A convenience method that calls recordPendingUpdates(updatedGroupV1Ids:)
    // or recordPendingUpdates(updatedGroupV2MasterKeys:).
    func recordPendingUpdates(groupModel: TSGroupModel)

    func recordPendingLocalAccountUpdates()

    /// Updates the local user's identity.
    ///
    /// Called during app launch, registration, and change number.
    func setLocalIdentifiers(_ localIdentifiers: LocalIdentifiersObjC)

    func backupPendingChanges(authedAccount: AuthedAccount)

    @discardableResult
    func restoreOrCreateManifestIfNecessary(authedAccount: AuthedAccount) -> AnyPromise

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
    func waitForPendingRestores() -> AnyPromise

    func resetLocalData(transaction: SDSAnyWriteTransaction)
}

// MARK: -

public struct StorageService: Dependencies {
    public enum StorageError: Error, IsRetryableProvider {
        case assertion
        case retryableAssertion
        case manifestEncryptionFailed(version: UInt64)
        case manifestDecryptionFailed(version: UInt64)
        case itemEncryptionFailed(identifier: StorageIdentifier)
        case itemDecryptionFailed(identifier: StorageIdentifier)
        case networkError(statusCode: Int, underlyingError: Error)

        // MARK: 

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
            case .itemEncryptionFailed:
                return false
            case .itemDecryptionFailed:
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
        public static let identifierLength: Int32 = 16
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

        public func buildRecord() throws -> StorageServiceProtoManifestRecordKey {
            let builder = StorageServiceProtoManifestRecordKey.builder(data: data, type: type)
            return try builder.build()
        }

        public static func deduplicate(_ identifiers: [StorageIdentifier]) -> [StorageIdentifier] {
            var identifierTypeMap = [Data: StorageIdentifier]()
            for identifier in identifiers {
                if let existingIdentifier = identifierTypeMap[identifier.data] {
                    Logger.verbose("identifier.data: \(identifier.data.hexadecimalString)")
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
    ) -> Promise<FetchLatestManifestResponse> {
        Logger.info("")

        var endpoint = "v1/storage/manifest"
        if let greaterThanVersion = greaterThanVersion {
            endpoint += "/version/\(greaterThanVersion)"
        }

        return storageRequest(
            withMethod: .get,
            endpoint: endpoint,
            chatServiceAuth: chatServiceAuth
        ).map(on: DispatchQueue.global()) { response in
            switch response.status {
            case .success:
                let encryptedManifestContainer = try StorageServiceProtoStorageManifest(serializedData: response.data)
                let decryptResult = DependenciesBridge.shared.svr.decrypt(
                    keyType: .storageServiceManifest(version: encryptedManifestContainer.version),
                    encryptedData: encryptedManifestContainer.value
                )
                switch decryptResult {
                case .success(let manifestData):
                    return .latestManifest(try StorageServiceProtoManifestRecord(serializedData: manifestData))
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
    }

    /// Update the manifest record on the service.
    ///
    /// If the version we are updating to already exists on the service,
    /// the conflicting manifest will return and the update will not
    /// have been applied until we resolve the conflicts.
    public static func updateManifest(
        _ manifest: StorageServiceProtoManifestRecord,
        newItems: [StorageItem],
        deletedIdentifiers: [StorageIdentifier] = [],
        deleteAllExistingRecords: Bool = false,
        chatServiceAuth: ChatServiceAuth
    ) -> Promise<StorageServiceProtoManifestRecord?> {
        Logger.info("newItems: \(newItems.count), deletedIdentifiers: \(deletedIdentifiers.count), deleteAllExistingRecords: \(deleteAllExistingRecords)")

        return DispatchQueue.global().async(.promise) {
            var builder = StorageServiceProtoWriteOperation.builder()

            // Encrypt the manifest
            let manifestData = try manifest.serializedData()
            let encryptedManifestData: Data
            let encryptResult = DependenciesBridge.shared.svr.encrypt(
                keyType: .storageServiceManifest(version: manifest.version),
                data: manifestData
            )
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
            builder.setManifest(try manifestWrapperBuilder.build())

            // Encrypt the new items
            builder.setInsertItem(try newItems.map { item in
                let itemData = try item.record.serializedData()
                let encryptedItemData: Data
                let itemEncryptionResult = DependenciesBridge.shared.svr.encrypt(
                    keyType: .storageServiceRecord(identifier: item.identifier),
                    data: itemData
                )
                switch itemEncryptionResult {
                case .success(let data):
                    encryptedItemData = data
                case .masterKeyMissing, .cryptographyError:
                    throw StorageError.itemEncryptionFailed(identifier: item.identifier)
                }
                let itemWrapperBuilder = StorageServiceProtoStorageItem.builder(key: item.identifier.data, value: encryptedItemData)
                return try itemWrapperBuilder.build()
            })

            // Flag the deleted keys
            builder.setDeleteKey(deletedIdentifiers.map { $0.data })

            builder.setDeleteAll(deleteAllExistingRecords)

            return try builder.buildSerializedData()
        }.then(on: DispatchQueue.global()) { data in
            storageRequest(
                withMethod: .put,
                endpoint: "v1/storage",
                body: data,
                chatServiceAuth: chatServiceAuth
            )
        }.map(on: DispatchQueue.global()) { response in
            switch response.status {
            case .success:
                // We expect a successful response to have no data
                if !response.data.isEmpty { owsFailDebug("unexpected response data") }
                return nil
            case .conflict:
                // Our version was out of date, we should've received a copy of the latest version
                let encryptedManifestContainer = try StorageServiceProtoStorageManifest(serializedData: response.data)
                let manifestData: Data
                let decryptionResult = DependenciesBridge.shared.svr.decrypt(
                    keyType: .storageServiceManifest(version: encryptedManifestContainer.version),
                    encryptedData: encryptedManifestContainer.value
                )
                switch decryptionResult {
                case .success(let data):
                    manifestData = data
                case .masterKeyMissing, .cryptographyError:
                    throw StorageError.manifestDecryptionFailed(version: encryptedManifestContainer.version)
                }
                return try StorageServiceProtoManifestRecord(serializedData: manifestData)
            default:
                owsFailDebug("unexpected response \(response.status)")
                throw StorageError.retryableAssertion
            }
        }
    }

    /// Fetch an item record from the service
    ///
    /// Returns nil if this record does not exist
    public static func fetchItem(for key: StorageIdentifier, chatServiceAuth: ChatServiceAuth) -> Promise<StorageItem?> {
        return fetchItems(for: [key], chatServiceAuth: chatServiceAuth).map { $0.first }
    }

    /// Fetch a list of item records from the service
    ///
    /// The response will include only the items that could be found on the service
    public static func fetchItems(
        for identifiers: [StorageIdentifier],
        chatServiceAuth: ChatServiceAuth
    ) -> Promise<[StorageItem]> {
        Logger.info("")

        let keys = StorageIdentifier.deduplicate(identifiers)

        // The server will 500 if we try and request too many keys at once.
        owsAssertDebug(keys.count <= 1024)

        guard !keys.isEmpty else { return Promise.value([]) }

        return DispatchQueue.global().async(.promise) {
            var builder = StorageServiceProtoReadOperation.builder()
            builder.setReadKey(keys.map { $0.data })
            return try builder.buildSerializedData()
        }.then(on: DispatchQueue.global()) { data in
            storageRequest(
                withMethod: .put,
                endpoint: "v1/storage/read",
                body: data,
                chatServiceAuth: chatServiceAuth
            )
        }.map(on: DispatchQueue.global()) { response in
            guard case .success = response.status else {
                owsFailDebug("unexpected response \(response.status)")
                throw StorageError.retryableAssertion
            }

            let itemsProto = try StorageServiceProtoStorageItems(serializedData: response.data)

            let keyToIdentifier = Dictionary(uniqueKeysWithValues: keys.map { ($0.data, $0) })

            return try itemsProto.items.map { item in
                let encryptedItemData = item.value
                guard let itemIdentifier = keyToIdentifier[item.key] else {
                    owsFailDebug("missing identifier for fetched item")
                    throw StorageError.assertion
                }
                let itemData: Data
                let itemDecryptionResult = DependenciesBridge.shared.svr.decrypt(
                    keyType: .storageServiceRecord(identifier: itemIdentifier),
                    encryptedData: encryptedItemData
                )
                switch itemDecryptionResult {
                case .success(let data):
                    itemData = data
                case .masterKeyMissing, .cryptographyError:
                    throw StorageError.itemDecryptionFailed(identifier: itemIdentifier)
                }
                let record = try StorageServiceProtoStorageRecord(serializedData: itemData)
                return StorageItem(identifier: itemIdentifier, record: record)
            }
        }
    }

    // MARK: - Dependencies

    private static var urlSession: OWSURLSessionProtocol {
        return self.signalService.urlSessionForStorageService()
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
    ) -> Promise<StorageResponse> {
        return serviceClient
            .requestStorageAuth(chatServiceAuth: chatServiceAuth)
            .then { username, password -> Promise<HTTPResponse> in
                if method == .get { assert(body == nil) }

                let httpHeaders = OWSHttpHeaders()
                httpHeaders.addHeader("Content-Type", value: OWSMimeTypeProtobuf, overwriteOnConflict: true)
                try httpHeaders.addAuthHeader(username: username, password: password)

                Logger.info("Storage request started: \(method) \(endpoint)")

                let urlSession = self.urlSession
                // Some 4xx responses are expected;
                // we'll discriminate the status code ourselves.
                urlSession.require2xxOr3xx = false
                return urlSession.dataTaskPromise(endpoint,
                                                  method: method,
                                                  headers: httpHeaders.headers,
                                                  body: body)
            }
            .map(on: DispatchQueue.global()) { (response: HTTPResponse) -> StorageResponse in
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

                Logger.info("Storage request succeeded: \(method) \(endpoint)")

                return StorageResponse(status: status, data: responseData)
            }.recover(on: DispatchQueue.global()) { (error: Error) -> Promise<StorageResponse> in
                owsFailDebugUnlessNetworkFailure(error)
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
        case .UNRECOGNIZED:
            return ".UNRECOGNIZED"
        }
    }
}
