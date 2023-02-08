//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

@objc
public protocol StorageServiceManagerProtocol {
    func recordPendingDeletions(deletedAccountIds: [AccountId])
    func recordPendingDeletions(deletedAddresses: [SignalServiceAddress])
    func recordPendingDeletions(deletedGroupV1Ids: [Data])
    func recordPendingDeletions(deletedGroupV2MasterKeys: [Data])
    func recordPendingDeletions(deletedStoryDistributionListIds: [Data])

    func recordPendingUpdates(updatedAccountIds: [AccountId])
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress])
    func recordPendingUpdates(updatedGroupV1Ids: [Data])
    func recordPendingUpdates(updatedGroupV2MasterKeys: [Data])
    func recordPendingUpdates(updatedStoryDistributionListIds: [Data])

    // A convenience method that calls recordPendingUpdates(updatedGroupV1Ids:)
    // or recordPendingUpdates(updatedGroupV2MasterKeys:).
    func recordPendingUpdates(groupModel: TSGroupModel)

    func recordPendingLocalAccountUpdates()

    func backupPendingChanges()

    @discardableResult
    func restoreOrCreateManifestIfNecessary() -> AnyPromise

    func resetLocalData(transaction: SDSAnyWriteTransaction)
}

// MARK: -

public struct StorageService: Dependencies {
    public enum StorageError: Error, IsRetryableProvider {
        case assertion
        case retryableAssertion
        case manifestDecryptionFailed(version: UInt64)
        case itemDecryptionFailed(identifier: StorageIdentifier)
        case networkError(statusCode: Int, underlyingError: Error)
        case accountMissing
        case storyMissing

        // MARK: 

        public var isRetryableProvider: Bool {
            switch self {
            case .assertion:
                return false
            case .retryableAssertion:
                return true
            case .manifestDecryptionFailed:
                return false
            case .itemDecryptionFailed:
                return false
            case .networkError(let statusCode, _):
                // If this is a server error, retry
                return statusCode >= 500
            case .accountMissing:
                return false
            case .storyMissing:
                return false
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

        public init(identifier: StorageIdentifier, contact: StorageServiceProtoContactRecord) throws {
            var storageRecord = StorageServiceProtoStorageRecord.builder()
            storageRecord.setRecord(.contact(contact))
            self.init(identifier: identifier, record: try storageRecord.build())
        }

        public init(identifier: StorageIdentifier, groupV1: StorageServiceProtoGroupV1Record) throws {
            var storageRecord = StorageServiceProtoStorageRecord.builder()
            storageRecord.setRecord(.groupV1(groupV1))
            self.init(identifier: identifier, record: try storageRecord.build())
        }

        public init(identifier: StorageIdentifier, groupV2: StorageServiceProtoGroupV2Record) throws {
            var storageRecord = StorageServiceProtoStorageRecord.builder()
            storageRecord.setRecord(.groupV2(groupV2))
            self.init(identifier: identifier, record: try storageRecord.build())
        }

        public init(identifier: StorageIdentifier, account: StorageServiceProtoAccountRecord) throws {
            var storageRecord = StorageServiceProtoStorageRecord.builder()
            storageRecord.setRecord(.account(account))
            self.init(identifier: identifier, record: try storageRecord.build())
        }

        public init(identifier: StorageIdentifier, storyDistributionList: StorageServiceProtoStoryDistributionListRecord) throws {
            var storageRecord = StorageServiceProtoStorageRecord.builder()
            storageRecord.setRecord(.storyDistributionList(storyDistributionList))
            self.init(identifier: identifier, record: try storageRecord.build())
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
    public static func fetchLatestManifest(greaterThanVersion: UInt64? = nil) -> Promise<FetchLatestManifestResponse> {
        Logger.info("")

        var endpoint = "v1/storage/manifest"
        if let greaterThanVersion = greaterThanVersion {
            endpoint += "/version/\(greaterThanVersion)"
        }

        return storageRequest(withMethod: .get, endpoint: endpoint).map(on: DispatchQueue.global()) { response in
            switch response.status {
            case .success:
                let encryptedManifestContainer = try StorageServiceProtoStorageManifest(serializedData: response.data)
                let manifestData: Data
                do {
                    manifestData = try DependenciesBridge.shared.keyBackupService.decrypt(
                        keyType: .storageServiceManifest(version: encryptedManifestContainer.version),
                        encryptedData: encryptedManifestContainer.value
                    )
                } catch {
                    throw StorageError.manifestDecryptionFailed(version: encryptedManifestContainer.version)
                }
                return .latestManifest(try StorageServiceProtoManifestRecord(serializedData: manifestData))
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
        deleteAllExistingRecords: Bool = false
    ) -> Promise<StorageServiceProtoManifestRecord?> {
        Logger.info("newItems: \(newItems.count), deletedIdentifiers: \(deletedIdentifiers.count), deleteAllExistingRecords: \(deleteAllExistingRecords)")

        return DispatchQueue.global().async(.promise) {
            var builder = StorageServiceProtoWriteOperation.builder()

            // Encrypt the manifest
            let manifestData = try manifest.serializedData()
            let encryptedManifestData = try DependenciesBridge.shared.keyBackupService.encrypt(
                keyType: .storageServiceManifest(version: manifest.version),
                data: manifestData
            )

            let manifestWrapperBuilder = StorageServiceProtoStorageManifest.builder(
                version: manifest.version,
                value: encryptedManifestData
            )
            builder.setManifest(try manifestWrapperBuilder.build())

            // Encrypt the new items
            builder.setInsertItem(try newItems.map { item in
                let itemData = try item.record.serializedData()
                let encryptedItemData = try DependenciesBridge.shared.keyBackupService.encrypt(
                    keyType: .storageServiceRecord(identifier: item.identifier),
                    data: itemData
                )
                let itemWrapperBuilder = StorageServiceProtoStorageItem.builder(key: item.identifier.data, value: encryptedItemData)
                return try itemWrapperBuilder.build()
            })

            // Flag the deleted keys
            builder.setDeleteKey(deletedIdentifiers.map { $0.data })

            builder.setDeleteAll(deleteAllExistingRecords)

            return try builder.buildSerializedData()
        }.then(on: DispatchQueue.global()) { data in
            storageRequest(withMethod: .put, endpoint: "v1/storage", body: data)
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
                do {
                    manifestData = try DependenciesBridge.shared.keyBackupService.decrypt(
                        keyType: .storageServiceManifest(version: encryptedManifestContainer.version),
                        encryptedData: encryptedManifestContainer.value
                    )
                } catch {
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
    public static func fetchItem(for key: StorageIdentifier) -> Promise<StorageItem?> {
        return fetchItems(for: [key]).map { $0.first }
    }

    /// Fetch a list of item records from the service
    ///
    /// The response will include only the items that could be found on the service
    public static func fetchItems(for identifiers: [StorageIdentifier]) -> Promise<[StorageItem]> {
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
            storageRequest(withMethod: .put, endpoint: "v1/storage/read", body: data)
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
                do {
                    itemData = try DependenciesBridge.shared.keyBackupService.decrypt(
                        keyType: .storageServiceRecord(identifier: itemIdentifier),
                        encryptedData: encryptedItemData
                    )
                } catch {
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

    private static func storageRequest(withMethod method: HTTPMethod, endpoint: String, body: Data? = nil) -> Promise<StorageResponse> {
        return serviceClient.requestStorageAuth().then { username, password -> Promise<HTTPResponse> in
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
        }.map(on: DispatchQueue.global()) { (response: HTTPResponse) -> StorageResponse in
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
            if let httpStatusCode = error.httpStatusCode,
               httpStatusCode == 401 {
                // Not registered.
                Logger.warn("Error: \(error)")
            } else {
                owsFailDebugUnlessNetworkFailure(error)
            }
            throw StorageError.networkError(statusCode: 0, underlyingError: error)
        }
    }
}

// MARK: - Test Helpers

#if DEBUG

public extension StorageService {
    static func test() {
        let testNames = ["abc", "def", "ghi", "jkl", "mno"]
        var recordsInManifest = [StorageItem]()
        for i in 0...4 {
            let identifier = StorageService.StorageIdentifier.generate(type: .contact)

            var contactRecordBuilder = StorageServiceProtoContactRecord.builder()
            contactRecordBuilder.setServiceUuid(testNames[i])

            recordsInManifest.append(try! StorageItem(identifier: identifier, contact: try! contactRecordBuilder.build()))
        }

        let identifiersInManfest = recordsInManifest.map { $0.identifier }

        var ourManifestVersion: UInt64 = 0

        // Fetch Existing
        fetchLatestManifest().map { response in
            var existingKeys: [StorageIdentifier]?
            switch response {
            case .latestManifest(let latestManifest):
                existingKeys = latestManifest.keys.map { StorageIdentifier(data: $0.data, type: $0.type) }
            case .noNewerManifest, .noExistingManifest:
                break
            }

            // set keys
            var newManifestBuilder = StorageServiceProtoManifestRecord.builder(version: ourManifestVersion)
            newManifestBuilder.setKeys(recordsInManifest.map { try! $0.identifier.buildRecord() })

            return (try! newManifestBuilder.build(), existingKeys ?? [])

        // Update or create initial manifest with test data
        }.then { latestManifest, deletedKeys in
            updateManifest(latestManifest, newItems: recordsInManifest, deletedIdentifiers: deletedKeys)
        }.map { latestManifest in
            guard latestManifest == nil else {
                owsFailDebug("Manifest conflicted unexpectedly, should be nil")
                throw StorageError.assertion
            }

        // Fetch the manifest we just created
        }.then { fetchLatestManifest() }.map { response in
            guard case .latestManifest(let latestManifest) = response else {
                owsFailDebug("manifest should exist, we just created it")
                throw StorageError.assertion
            }

            guard Set(latestManifest.keys.lazy.map { $0.data }) == Set(identifiersInManfest.lazy.map { $0.data }) else {
                owsFailDebug("manifest should only contain our test keys")
                throw StorageError.assertion
            }

            guard latestManifest.version == ourManifestVersion else {
                owsFailDebug("manifest version should be the version we set")
                throw StorageError.assertion
            }

        // Fetch the manifest we just created specifying the local version
        }.then { fetchLatestManifest(greaterThanVersion: ourManifestVersion) }.map { response in
            guard case .noNewerManifest = response else {
                owsFailDebug("no new manifest should exist, we just created it")
                throw StorageError.assertion
            }

        // Fetch the first contact we just stored
        }.then {
            fetchItem(for: identifiersInManfest.first!)
        }.map { item in
            guard let item = item, item.identifier == identifiersInManfest.first! else {
                owsFailDebug("this should be the contact we set")
                throw StorageError.assertion
            }

            guard item.contactRecord!.serviceUuid == recordsInManifest.first!.contactRecord!.serviceUuid else {
                owsFailDebug("this should be the contact we set")
                throw StorageError.assertion
            }

        // Fetch all the contacts we stored
        }.then {
            fetchItems(for: identifiersInManfest)
        }.map { items in
            guard items.count == recordsInManifest.count else {
                owsFailDebug("wrong number of contacts")
                throw StorageError.assertion
            }

            for item in items {
                guard let matchingRecord = recordsInManifest.first(where: { $0.identifier == item.identifier }) else {
                    owsFailDebug("this should be a contact we set")
                    throw StorageError.assertion
                }

                guard item.contactRecord!.serviceUuid == matchingRecord.contactRecord!.serviceUuid else {
                    owsFailDebug("this should be a contact we set")
                    throw StorageError.assertion
                }

            }

        // Fetch a contact that doesn't exist
        }.then {
            fetchItem(for: .generate(type: .contact))
        }.map { item in
            guard item == nil else {
                owsFailDebug("this contact should not exist")
                throw StorageError.assertion
            }

        // Delete all the contacts we stored
        }.map {
            ourManifestVersion += 1
            let newManifestBuilder = StorageServiceProtoManifestRecord.builder(version: ourManifestVersion)
            return try! newManifestBuilder.build()
        }.then { latestManifest in
            updateManifest(latestManifest, newItems: [], deletedIdentifiers: identifiersInManfest)
        }.map { latestManifest in
            guard latestManifest == nil else {
                owsFailDebug("Manifest conflicted unexpectedly, should be nil")
                throw StorageError.assertion
            }

        // Fetch the manifest we just stored
        }.then { fetchLatestManifest() }.map { latestManifest in
            guard case .latestManifest(let latestManifest) = latestManifest else {
                owsFailDebug("manifest should exist, we just created it")
                throw StorageError.assertion
            }

            guard latestManifest.keys.isEmpty else {
                owsFailDebug("manifest should have no keys")
                throw StorageError.assertion
            }

            guard latestManifest.version == ourManifestVersion else {
                owsFailDebug("manifest version should be the version we set")
                throw StorageError.assertion
            }

        // Try and update a manifest version that already exists
        }.map {
            var oldManifestBuilder = StorageServiceProtoManifestRecord.builder(version: 0)

            let identifier = StorageIdentifier.generate(type: .contact)

            var recordBuilder = StorageServiceProtoContactRecord.builder()
            recordBuilder.setServiceUuid(testNames[0])

            oldManifestBuilder.setKeys([try! identifier.buildRecord()])

            return (try! oldManifestBuilder.build(), try! StorageItem(identifier: identifier, contact: try! recordBuilder.build()))
        }.then { oldManifest, item in
            updateManifest(oldManifest, newItems: [item], deletedIdentifiers: [])
        }.done { latestManifest in
            guard let latestManifest = latestManifest else {
                owsFailDebug("manifest should exist, because there was a conflict")
                throw StorageError.assertion
            }

            guard latestManifest.keys.isEmpty else {
                owsFailDebug("manifest should still have no keys")
                throw StorageError.assertion
            }

            guard latestManifest.version == ourManifestVersion else {
                owsFailDebug("manifest version should be the version we set")
                throw StorageError.assertion
            }
        }.catch { error in
            owsFailDebug("unexpectedly raised error \(error)")
        }
    }
}

#endif

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
