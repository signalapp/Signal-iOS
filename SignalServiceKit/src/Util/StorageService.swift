//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc
public protocol StorageServiceManagerProtocol {
    func recordPendingDeletions(deletedIds: [AccountId])
    func recordPendingDeletions(deletedAddresses: [SignalServiceAddress])

    func recordPendingUpdates(updatedIds: [AccountId])
    func recordPendingUpdates(updatedAddresses: [SignalServiceAddress])

    func backupPendingChanges()
    func restoreOrCreateManifestIfNecessary()
}

public struct StorageService {
    public enum StorageError: OperationError {
        case assertion
        case retryableAssertion
        case decryptionFailed(manifestVersion: UInt64)

        public var isRetryable: Bool {
            guard case .retryableAssertion = self else { return false }
            return true
        }
    }

    /// An identifier representing a given contact object.
    /// This can be used to fetch specific contacts from the service.
    public struct ContactIdentifier: Hashable {
        public static let identifierLength: Int32 = 16
        public let data: Data

        public init(data: Data) {
            if data.count != ContactIdentifier.identifierLength { owsFail("Initialized with invalid data") }
            self.data = data
        }

        public static func generate() -> ContactIdentifier {
            return .init(data: Randomness.generateRandomBytes(identifierLength))
        }
    }

    /// Fetch the latest manifest from the storage service
    ///
    /// Returns nil if a manifest has never been stored.
    public static func fetchManifest() -> Promise<StorageServiceProtoManifestRecord?> {
        Logger.info("")

        return storageRequest(withMethod: "GET", endpoint: "v1/contacts/manifest").map(on: .global()) { response in
            switch response.status {
            case .success:
                let encryptedManifestContainer = try StorageServiceProtoContactsManifest.parseData(response.data)
                let manifestData: Data
                do {
                    manifestData = try KeyBackupService.decryptWithMasterKey(encryptedManifestContainer.value)
                } catch {
                    throw StorageError.decryptionFailed(manifestVersion: encryptedManifestContainer.version)
                }
                return try StorageServiceProtoManifestRecord.parseData(manifestData)
            case .notFound:
                return nil
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
        newContacts: [StorageServiceProtoContactRecord],
        deletedContacts: [ContactIdentifier]
    ) -> Promise<StorageServiceProtoManifestRecord?> {
        Logger.info("")

        return DispatchQueue.global().async(.promise) {
            let builder = StorageServiceProtoWriteOperation.builder()

            // Encrypt the manifest
            let manifestData = try manifest.serializedData()
            let encryptedManifestData = try KeyBackupService.encryptWithMasterKey(manifestData)

            let manifestWrapperBuilder = StorageServiceProtoContactsManifest.builder(
                version: manifest.version,
                value: encryptedManifestData
            )
            builder.setManifest(try manifestWrapperBuilder.build())

            // Encrypt the new contacts
            builder.setInsertContact(try newContacts.map { contact in
                let contactData = try contact.serializedData()
                let encryptedContactData = try KeyBackupService.encryptWithMasterKey(contactData)
                let contactWrapperBuilder = StorageServiceProtoContact.builder(key: contact.key, value: encryptedContactData)
                return try contactWrapperBuilder.build()
            })

            // Flag the deleted contacts
            builder.setDeleteKey(deletedContacts.map { $0.data })

            return try builder.buildSerializedData()
        }.then(on: .global()) { data in
            storageRequest(withMethod: "PUT", endpoint: "/v1/contacts", body: data)
        }.map(on: .global()) { response in
            switch response.status {
            case .success:
                // We expect a successful response to have no data
                if !response.data.isEmpty { owsFailDebug("unexpected response data") }
                return nil
            case .conflict:
                // Our version was out of date, we should've received a copy of the latest version
                let encryptedManifestData = try StorageServiceProtoContactsManifest.parseData(response.data).value
                let manifestData = try KeyBackupService.decryptWithMasterKey(encryptedManifestData)
                return try StorageServiceProtoManifestRecord.parseData(manifestData)
            default:
                owsFailDebug("unexpected response \(response.status)")
                throw StorageError.retryableAssertion
            }
        }
    }

    /// Fetch a contact from the service
    ///
    /// Returns nil if this contact does not exist
    public static func fetchContact(for key: ContactIdentifier) -> Promise<StorageServiceProtoContactRecord?> {
        return fetchContacts(for: [key]).map { $0.first }
    }

    /// Fetch a list of contacts from the service
    ///
    /// The response will include only the contacts that could be found on the service
    public static func fetchContacts(for keys: [ContactIdentifier]) -> Promise<[StorageServiceProtoContactRecord]> {
        Logger.info("")

        return DispatchQueue.global().async(.promise) {
            let builder = StorageServiceProtoReadOperation.builder()
            builder.setReadKey(keys.map { $0.data })
            return try builder.buildSerializedData()
        }.then(on: .global()) { data in
            storageRequest(withMethod: "PUT", endpoint: "v1/contacts/read", body: data)
        }.map(on: .global()) { response in
            guard case .success = response.status else {
                owsFailDebug("unexpected response \(response.status)")
                throw StorageError.retryableAssertion
            }

            let contactsProto = try StorageServiceProtoContacts.parseData(response.data)

            return try contactsProto.contacts.map { contact in
                let encryptedContactData = contact.value
                let contactData = try KeyBackupService.decryptWithMasterKey(encryptedContactData)
                return try StorageServiceProtoContactRecord.parseData(contactData)
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
        }
        let status: Status
        let data: Data
    }

    private struct Auth {
        let username: String
        let password: String

        func authHeader() throws -> String {
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

                        owsFailDebug("response error \(error)")
                        return resolver.reject(error)
                    }

                    let status: StorageResponse.Status

                    switch response.statusCode {
                    case 200:
                        status = .success
                    case 409:
                        status = .conflict
                    case 404:
                        status = .notFound
                    default:
                        owsFailDebug("invalid response \(response.statusCode)")
                        if response.statusCode >= 500 {
                            // This is a server error, retry
                            return resolver.reject(StorageError.retryableAssertion)
                        } else if let error = error {
                            return resolver.reject(error)
                        } else {
                            return resolver.reject(StorageError.assertion)
                        }
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

// MARK: - Objc Interface

public extension StorageService {
    static func updateManifestObjc(
        _ manifest: StorageServiceProtoManifestRecord,
        newContacts: [StorageServiceProtoContactRecord],
        deletedContacts: [ContactIdentifierObjc]
    ) -> Promise<StorageServiceProtoManifestRecord?> {
        return updateManifest(manifest, newContacts: newContacts, deletedContacts: deletedContacts.map { $0.contactIdentifier })
    }

    static func fetchContactObjc(for key: ContactIdentifierObjc) -> Promise<StorageServiceProtoContactRecord?> {
        return fetchContacts(for: [key.contactIdentifier]).map { $0.first }
    }

    static func fetchContactsObjc(for keys: [ContactIdentifierObjc]) -> Promise<[StorageServiceProtoContactRecord]> {
        return fetchContacts(for: keys.map { $0.contactIdentifier })
    }
}

@objc(OWSStorageService)
@available(swift, obsoleted: 1.0)
public class StorageServiceObjc: NSObject {
    @objc
    public static func fetchManifest() -> AnyPromise {
        return AnyPromise(StorageService.fetchManifest())
    }

    @objc
    public static func updateManifest(
        _ manifest: StorageServiceProtoManifestRecord,
        newContacts: [StorageServiceProtoContactRecord],
        deletedContacts: [ContactIdentifierObjc]
    ) -> AnyPromise {
        return AnyPromise(StorageService.updateManifestObjc(
            manifest,
            newContacts: newContacts,
            deletedContacts: deletedContacts
        ))
    }

    @objc
    public static func fetchContact(forKey key: ContactIdentifierObjc) -> AnyPromise {
        return AnyPromise(StorageService.fetchContactObjc(for: key))
    }

    @objc
    public static func fetchContacts(forKeys keys: [ContactIdentifierObjc]) -> AnyPromise {
        return AnyPromise(StorageService.fetchContactsObjc(for: keys))
    }
}

@objc(OWSContactKey)
public class ContactIdentifierObjc: NSObject {
    fileprivate let contactIdentifier: StorageService.ContactIdentifier

    @objc
    public var data: Data { return contactIdentifier.data }

    @objc
    public convenience init(data: Data) {
        self.init(.init(data: data))
    }

    // This function isn't objc accessible, it's just used for casting in swift land
    public init(_ contactIdentifier: StorageService.ContactIdentifier) {
        self.contactIdentifier = contactIdentifier
    }

    @objc static func generate() -> ContactIdentifierObjc {
        return ContactIdentifierObjc(.generate())
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? ContactIdentifierObjc else { return false }
        return contactIdentifier == object.contactIdentifier
    }

    public override var hash: Int {
        return contactIdentifier.hashValue
    }
}

// MARK: -

public extension StorageServiceProtoContactRecord {
    var contactIdentifier: StorageService.ContactIdentifier { return .init(data: key) }
}

// MARK: - Test Helpers

#if DEBUG

public extension StorageService {
    static func test() {
        let testNames = ["abc", "def", "ghi", "jkl", "mno"]
        var contactsInManifest = [StorageServiceProtoContactRecord]()
        for i in 0...4 {
            let identifier = StorageService.ContactIdentifier.generate()

            let recordBuilder = StorageServiceProtoContactRecord.builder(key: identifier.data)
            recordBuilder.setServiceUuid(testNames[i])

            contactsInManifest.append(try! recordBuilder.build())
        }

        let identifiersInManfest = contactsInManifest.map { $0.contactIdentifier }

        var ourManifestVersion: UInt64 = 0

        // Fetch Existing
        fetchManifest().map { manifest in
            let previousVersion = manifest?.version ?? ourManifestVersion
            ourManifestVersion = previousVersion + 1

            // set keys
            let newManifestBuilder = StorageServiceProtoManifestRecord.builder(version: ourManifestVersion)
            newManifestBuilder.setKeys(contactsInManifest.map { $0.key })

            return (try! newManifestBuilder.build(), manifest?.keys.map { ContactIdentifier(data: $0) } ?? [])

        // Update or create initial manifest with test data
        }.then { manifest, deletedKeys in
            updateManifest(manifest, newContacts: contactsInManifest, deletedContacts: deletedKeys)
        }.map { manifest in
            guard manifest == nil else {
                owsFailDebug("Manifest conflicted unexpectedly, should be nil")
                throw StorageError.assertion
            }

        // Fetch the manifest we just created
        }.then { fetchManifest() }.map { manifest in
            guard let manifest = manifest else {
                owsFailDebug("manifest should exist, we just created it")
                throw StorageError.assertion
            }

            guard Set(manifest.keys) == Set(identifiersInManfest.map { $0.data }) else {
                owsFailDebug("manifest should only contain our test keys")
                throw StorageError.assertion
            }

            guard manifest.version == ourManifestVersion else {
                owsFailDebug("manifest version should be the version we set")
                throw StorageError.assertion
            }

        // Fetch the first contact we just stored
        }.then {
            fetchContact(for: identifiersInManfest.first!)
        }.map { contact in
            guard contact!.key == identifiersInManfest.first!.data else {
                owsFailDebug("this should be the contact we set")
                throw StorageError.assertion
            }

            guard contact!.serviceUuid == contactsInManifest.first!.serviceUuid else {
                owsFailDebug("this should be the contact we set")
                throw StorageError.assertion
            }

        // Fetch all the contacts we stored
        }.then {
            fetchContacts(for: identifiersInManfest)
        }.map { contacts in
            guard contacts.count == contactsInManifest.count else {
                owsFailDebug("wrong number of contacts")
                throw StorageError.assertion
            }

            for contact in contacts {
                guard let matchingContact = contactsInManifest.first(where: { $0.key == contact.key }) else {
                    owsFailDebug("this should be a contact we set")
                    throw StorageError.assertion
                }

                guard contact.serviceUuid == matchingContact.serviceUuid else {
                    owsFailDebug("this should be a contact we set")
                    throw StorageError.assertion
                }

            }

        // Fetch a contact that doesn't exist
        }.then {
            fetchContact(for: .generate())
        }.map { contact in
            guard contact == nil else {
                owsFailDebug("this contact should not exist")
                throw StorageError.assertion
            }

        // Delete all the contacts we stored
        }.map {
            ourManifestVersion += 1
            let newManifestBuilder = StorageServiceProtoManifestRecord.builder(version: ourManifestVersion)
            return try! newManifestBuilder.build()
        }.then { manifest in
            updateManifest(manifest, newContacts: [], deletedContacts: identifiersInManfest)
        }.map { manifest in
            guard manifest == nil else {
                owsFailDebug("Manifest conflicted unexpectedly, should be nil")
                throw StorageError.assertion
            }

        // Fetch the manifest we just stored
        }.then { fetchManifest() }.map { manifest in
            guard let manifest = manifest else {
                owsFailDebug("manifest should exist, we just created it")
                throw StorageError.assertion
            }

            guard manifest.keys.isEmpty else {
                owsFailDebug("manifest should have no keys")
                throw StorageError.assertion
            }

            guard manifest.version == ourManifestVersion else {
                owsFailDebug("manifest version should be the version we set")
                throw StorageError.assertion
            }

        // Try and update a manifest version that already exists
        }.map {
            let oldManifestBuilder = StorageServiceProtoManifestRecord.builder(version: 0)

            let identifier = ContactIdentifier.generate()

            let recordBuilder = StorageServiceProtoContactRecord.builder(key: identifier.data)
            recordBuilder.setServiceUuid(testNames[0])

            oldManifestBuilder.setKeys([identifier.data])

            return (try! oldManifestBuilder.build(), try! recordBuilder.build())
        }.then { oldManifest, contact in
            updateManifest(oldManifest, newContacts: [contact], deletedContacts: [])
        }.done { manifest in
            guard let manifest = manifest else {
                owsFailDebug("manifest should exist, because there was a conflict")
                throw StorageError.assertion
            }

            guard manifest.keys.isEmpty else {
                owsFailDebug("manifest should still have no keys")
                throw StorageError.assertion
            }

            guard manifest.version == ourManifestVersion else {
                owsFailDebug("manifest version should be the version we set")
                throw StorageError.assertion
            }
        }.catch { error in
            owsFailDebug("unexpectedly raised error \(error)")
        }.retainUntilComplete()
    }
}

#endif
