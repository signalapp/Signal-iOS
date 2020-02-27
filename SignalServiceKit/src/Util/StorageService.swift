//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public protocol StorageServiceManagerProtocol {
    func recordPendingDeletions(deletedIds: [AccountId])
    func recordPendingDeletions(deletedAddresses: [SignalServiceAddress])
    func recordPendingDeletions(deletedGroupIds: [Data])

    func recordPendingUpdates(updatedIds: [AccountId])
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress])
    func recordPendingUpdates(updatedGroupIds: [Data])

    func backupPendingChanges()

    @discardableResult
    func restoreOrCreateManifestIfNecessary() -> AnyPromise

    func resetLocalData(transaction: SDSAnyWriteTransaction)
}

public struct StorageService {
    public enum StorageError: OperationError {
        case assertion
        case retryableAssertion
        case manifestDecryptionFailed(version: UInt64)
        case itemDecryptionFailed(identifier: StorageIdentifier)
        case networkError(statusCode: Int, underlyingError: Error)
        case accountMissing

        // MARK: 

        public var isRetryable: Bool {
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
            }
        }

        public var errorUserInfo: [String: Any] {
            var userInfo: [String: Any] = [OWSOperationIsRetryableKey: self.isRetryable]
            if case .networkError(_, let underlyingError) = self {
                userInfo[NSUnderlyingErrorKey] = underlyingError
            }
            return userInfo
        }
    }

    /// An identifier representing a given storage item.
    /// This can be used to fetch specific items from the service.
    public struct StorageIdentifier: Hashable {
        public static let identifierLength: Int32 = 16
        public let data: Data

        public init(data: Data) {
            if data.count != StorageIdentifier.identifierLength { owsFail("Initialized with invalid data") }
            self.data = data
        }

        public static func generate() -> StorageIdentifier {
            return .init(data: Randomness.generateRandomBytes(identifierLength))
        }
    }

    public struct StorageItem {
        public let identifier: StorageIdentifier
        public let record: StorageServiceProtoStorageRecord

        public var type: UInt32 { return record.type }

        public var contactRecord: StorageServiceProtoContactRecord? {
            guard type == StorageServiceProtoStorageRecordType.contact.rawValue else { return nil }
            guard let contact = record.contact else {
                owsFailDebug("unexpectedly missing contact record")
                return nil
            }
            return contact
        }

        public var groupV1Record: StorageServiceProtoGroupV1Record? {
            guard type == StorageServiceProtoStorageRecordType.groupv1.rawValue else { return nil }
            guard let groupV1 = record.groupV1 else {
                owsFailDebug("unexpectedly missing group record")
                return nil
            }
            return groupV1
        }

        public init(identifier: StorageIdentifier, contact: StorageServiceProtoContactRecord) throws {
            let storageRecord = StorageServiceProtoStorageRecord.builder(type: UInt32(StorageServiceProtoStorageRecordType.contact.rawValue))
            storageRecord.setContact(contact)
            self.init(identifier: identifier, record: try storageRecord.build())
        }

        public init(identifier: StorageIdentifier, groupV1: StorageServiceProtoGroupV1Record) throws {
            let storageRecord = StorageServiceProtoStorageRecord.builder(type: UInt32(StorageServiceProtoStorageRecordType.groupv1.rawValue))
            storageRecord.setGroupV1(groupV1)
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

        return storageRequest(withMethod: "GET", endpoint: endpoint).map(on: .global()) { response in
            switch response.status {
            case .success:
                let encryptedManifestContainer = try StorageServiceProtoStorageManifest.parseData(response.data)
                let manifestData: Data
                do {
                    manifestData = try KeyBackupService.decrypt(
                        keyType: .storageServiceManifest(version: encryptedManifestContainer.version),
                        encryptedData: encryptedManifestContainer.value
                    )
                } catch {
                    throw StorageError.manifestDecryptionFailed(version: encryptedManifestContainer.version)
                }
                return .latestManifest(try StorageServiceProtoManifestRecord.parseData(manifestData))
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
            let builder = StorageServiceProtoWriteOperation.builder()

            // Encrypt the manifest
            let manifestData = try manifest.serializedData()
            let encryptedManifestData = try KeyBackupService.encrypt(
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
                let encryptedItemData = try KeyBackupService.encrypt(
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
        }.then(on: .global()) { data in
            storageRequest(withMethod: "PUT", endpoint: "v1/storage", body: data)
        }.map(on: .global()) { response in
            switch response.status {
            case .success:
                // We expect a successful response to have no data
                if !response.data.isEmpty { owsFailDebug("unexpected response data") }
                return nil
            case .conflict:
                // Our version was out of date, we should've received a copy of the latest version
                let encryptedManifestContainer = try StorageServiceProtoStorageManifest.parseData(response.data)
                let manifestData: Data
                do {
                    manifestData = try KeyBackupService.decrypt(
                        keyType: .storageServiceManifest(version: encryptedManifestContainer.version),
                        encryptedData: encryptedManifestContainer.value
                    )
                } catch {
                    throw StorageError.manifestDecryptionFailed(version: encryptedManifestContainer.version)
                }
                return try StorageServiceProtoManifestRecord.parseData(manifestData)
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
    public static func fetchItems(for keys: [StorageIdentifier]) -> Promise<[StorageItem]> {
        Logger.info("")
        guard !keys.isEmpty else { return Promise.value([]) }

        return DispatchQueue.global().async(.promise) {
            let builder = StorageServiceProtoReadOperation.builder()
            builder.setReadKey(keys.map { $0.data })
            return try builder.buildSerializedData()
        }.then(on: .global()) { data in
            storageRequest(withMethod: "PUT", endpoint: "v1/storage/read", body: data)
        }.map(on: .global()) { response in
            guard case .success = response.status else {
                owsFailDebug("unexpected response \(response.status)")
                throw StorageError.retryableAssertion
            }

            let itemsProto = try StorageServiceProtoStorageItems.parseData(response.data)

            return try itemsProto.items.map { item in
                let encryptedItemData = item.value
                let itemIdentifier = StorageIdentifier(data: item.key)
                let itemData: Data
                do {
                    itemData = try KeyBackupService.decrypt(
                        keyType: .storageServiceRecord(identifier: itemIdentifier),
                        encryptedData: encryptedItemData
                    )
                } catch {
                    throw StorageError.itemDecryptionFailed(identifier: itemIdentifier)
                }
                let record = try StorageServiceProtoStorageRecord.parseData(itemData)
                return StorageItem(identifier: itemIdentifier, record: record)
            }
        }
    }

    // MARK: - Dependencies

    private static var sessionManager: AFHTTPSessionManager {
        return OWSSignalService.sharedInstance().storageServiceSessionManager
    }

    private static var signalServiceClient: SignalServiceClient {
        return SignalServiceRestClient()
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

    public struct Auth {
        let username: String
        let password: String

        public init(username: String, password: String) {
            self.username = username
            self.password = password
        }

        public func authHeader() throws -> String {
            guard let data = "\(username):\(password)".data(using: .utf8) else {
                owsFailDebug("failed to encode auth data")
                throw StorageError.assertion
            }
            return "Basic " + data.base64EncodedString()
        }
    }

    private static func storageRequest(withMethod method: String, endpoint: String, body: Data? = nil) -> Promise<StorageResponse> {
        return signalServiceClient.requestStorageAuth().map { username, password in
            Auth(username: username, password: password)
        }.then(on: .global()) { auth in
            Promise { resolver in
                guard let url = URL(string: endpoint, relativeTo: sessionManager.baseURL) else {
                    owsFailDebug("failed to initialize URL")
                    throw StorageError.assertion
                }

                var error: NSError?
                let request = sessionManager.requestSerializer.request(
                    withMethod: method,
                    urlString: url.absoluteString,
                    parameters: nil,
                    error: &error
                )

                if let error = error {
                    owsFailDebug("failed to generate request: \(error)")
                    throw StorageError.assertion
                }

                if method == "GET" { assert(body == nil) }

                request.httpBody = body

                request.setValue(OWSMimeTypeProtobuf, forHTTPHeaderField: "Content-Type")
                request.setValue(try auth.authHeader(), forHTTPHeaderField: "Authorization")

                Logger.info("Storage request started: \(method) \(endpoint)")

                let task = sessionManager.dataTask(
                    with: request as URLRequest,
                    uploadProgress: nil,
                    downloadProgress: nil
                ) { response, responseObject, error in
                    guard let response = response as? HTTPURLResponse else {
                        Logger.info("Storage request failed: \(method) \(endpoint)")

                        guard let error = error else {
                            owsFailDebug("unexpected response type")
                            return resolver.reject(StorageError.assertion)
                        }

                        Logger.error("response error \(error)")
                        return resolver.reject(error)
                    }

                    let status: StorageResponse.Status

                    switch response.statusCode {
                    case 200:
                        status = .success
                    case 204:
                        status = .noContent
                    case 409:
                        status = .conflict
                    case 404:
                        status = .notFound
                    default:
                        guard let error = error else {
                            return resolver.reject(OWSAssertionError("error was nil for statusCode: \(response.statusCode)"))
                        }
                        return resolver.reject(StorageError.networkError(statusCode: response.statusCode, underlyingError: error))
                    }

                    // We should always receive response data, for some responses it will be empty.
                    guard let responseData = responseObject as? Data else {
                        owsFailDebug("missing response data")
                        return resolver.reject(StorageError.retryableAssertion)
                    }

                    // The layers that use this only want to process 200 and 409 responses,
                    // anything else we should raise as an error.

                    Logger.info("Storage request succeeded: \(method) \(endpoint)")

                    resolver.fulfill(StorageResponse(status: status, data: responseData))
                }
                task.resume()
            }
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
            let identifier = StorageService.StorageIdentifier.generate()

            let contactRecordBuilder = StorageServiceProtoContactRecord.builder()
            contactRecordBuilder.setServiceUuid(testNames[i])

            recordsInManifest.append(try! StorageItem(identifier: identifier, contact: try! contactRecordBuilder.build()))
        }

        let identifiersInManfest = recordsInManifest.map { $0.identifier }

        var ourManifestVersion: UInt64 = 0

        // Fetch Existing
        fetchLatestManifest().map { response in
            let previousVersion: UInt64
            var existingKeys: [Data]?
            switch response {
            case .latestManifest(let latestManifest):
                previousVersion = latestManifest.version
                existingKeys = latestManifest.keys
            case .noNewerManifest, .noExistingManifest:
                previousVersion = ourManifestVersion
            }

            // set keys
            let newManifestBuilder = StorageServiceProtoManifestRecord.builder(version: ourManifestVersion)
            newManifestBuilder.setKeys(recordsInManifest.map { $0.identifier.data })

            return (try! newManifestBuilder.build(), existingKeys?.map { StorageIdentifier(data: $0) } ?? [])

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

            guard Set(latestManifest.keys) == Set(identifiersInManfest.map { $0.data }) else {
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
            fetchItem(for: .generate())
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
            let oldManifestBuilder = StorageServiceProtoManifestRecord.builder(version: 0)

            let identifier = StorageIdentifier.generate()

            let recordBuilder = StorageServiceProtoContactRecord.builder()
            recordBuilder.setServiceUuid(testNames[0])

            oldManifestBuilder.setKeys([identifier.data])

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
        }.retainUntilComplete()
    }
}

#endif
