//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

public struct StorageService {
    public enum StorageError: Error {
        case assertion
    }

    public struct ContactKey: Hashable {
        public static let keyLength: Int32 = 16
        public let data: Data

        public init(data: Data = Randomness.generateRandomBytes(keyLength)) {
            if data.count != ContactKey.keyLength { owsFailDebug("Initialized with invalid data") }
            self.data = data
        }
    }

    /// Fetch the latest manifest from the storage service
    ///
    /// Returns nil if a manifest has never been stored.
    public static func fetchManifest() -> Promise<StorageServiceProtoManifestRecord?> {
        Logger.info("")

        return storageRequest(withMethod: "GET", endpoint: "v1/contacts/manifest").map(on: .global()) { response in
            switch response.statusCode {
            case 200:
                guard let responseData = response.data else {
                    owsFailDebug("response missing data")
                    throw StorageError.assertion
                }

                let encryptedManifestData = try StorageServiceProtoContactsManifest.parseData(responseData).value
                let manifestData = try KeyBackupService.decryptWithMasterKey(encryptedManifestData)
                return try StorageServiceProtoManifestRecord.parseData(manifestData)
            case 404:
                return nil
            default:
                owsFailDebug("invalid response \(response.statusCode)")
                throw StorageError.assertion
            }
        }
    }

    /// Update the manifest record on the service.
    ///
    /// If the version we are updating to already exists on the ervice,
    /// the conflicting manifest will return and the update will not
    /// have been applied until we resolve the conflicts.
    public static func updateManifest(
        _ manifest: StorageServiceProtoManifestRecord,
        newContacts: [StorageServiceProtoContactRecord],
        deletedContacts: [ContactKey]
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
            switch response.statusCode {
            case 200:
                // We expect a successful response to have no data
                if let responseData = response.data, !responseData.isEmpty { owsFailDebug("unexpected response data") }
                return nil
            case 409:
                // Our version was out of date, we should've received a copy of the latest version
                guard let responseData = response.data else {
                    owsFailDebug("response missing data")
                    throw StorageError.assertion
                }

                let encryptedManifestData = try StorageServiceProtoContactsManifest.parseData(responseData).value
                let manifestData = try KeyBackupService.decryptWithMasterKey(encryptedManifestData)
                return try StorageServiceProtoManifestRecord.parseData(manifestData)
            default:
                owsFailDebug("invalid response \(response.statusCode)")
                throw StorageError.assertion
            }
        }
    }

    /// Fetch a contact from the service
    ///
    /// Returns nil if this contact does not exist
    public static func fetchContact(for key: ContactKey) -> Promise<StorageServiceProtoContactRecord?> {
        return fetchContacts(for: [key]).map { $0.first }
    }

    /// Fetch a list of contacts from the service
    ///
    /// The response will include only the contacts that could be found on the service
    public static func fetchContacts(for keys: [ContactKey]) -> Promise<[StorageServiceProtoContactRecord]> {
        Logger.info("")

        return DispatchQueue.global().async(.promise) {
            let builder = StorageServiceProtoReadOperation.builder()
            builder.setReadKey(keys.map { $0.data })
            return try builder.buildSerializedData()
        }.then(on: .global()) { data in
            storageRequest(withMethod: "PUT", endpoint: "v1/contacts/read", body: data)
        }.map(on: .global()) { response in
            guard response.statusCode == 200 else {
                owsFailDebug("invalid response \(response.statusCode)")
                throw StorageError.assertion
            }

            guard let responseData = response.data else {
                owsFailDebug("response missing data")
                throw StorageError.assertion
            }

            let contactsProto = try StorageServiceProtoContacts.parseData(responseData)

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
        let statusCode: Int
        let data: Data?
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
        return signalServiceClient.requetStorageAuth().map { username, password in
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

                if method != "GET" { request.httpBody = body }

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

                    Logger.info("Storage request succeeded: \(method) \(endpoint)")

                    resolver.fulfill(StorageResponse(statusCode: response.statusCode, data: responseObject as? Data))
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
        deletedContacts: [ContactKeyObjc]
    ) -> Promise<StorageServiceProtoManifestRecord?> {
        return updateManifest(manifest, newContacts: newContacts, deletedContacts: deletedContacts.map { $0.contactKey })
    }

    static func fetchContactObjc(for key: ContactKeyObjc) -> Promise<StorageServiceProtoContactRecord?> {
        return fetchContacts(for: [key.contactKey]).map { $0.first }
    }

    static func fetchContactsObjc(for keys: [ContactKeyObjc]) -> Promise<[StorageServiceProtoContactRecord]> {
        return fetchContacts(for: keys.map { $0.contactKey })
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
        deletedContacts: [ContactKeyObjc]
    ) -> AnyPromise {
        return AnyPromise(StorageService.updateManifestObjc(
            manifest,
            newContacts: newContacts,
            deletedContacts: deletedContacts
        ))
    }

    @objc
    public static func fetchContact(forKey key: ContactKeyObjc) -> AnyPromise {
        return AnyPromise(StorageService.fetchContactObjc(for: key))
    }

    @objc
    public static func fetchContacts(forKeys keys: [ContactKeyObjc]) -> AnyPromise {
        return AnyPromise(StorageService.fetchContactsObjc(for: keys))
    }
}

@objc(OWSContactKey)
public class ContactKeyObjc: NSObject {
    fileprivate let contactKey: StorageService.ContactKey

    @objc
    public var data: Data { return contactKey.data }

    @objc
    public init(data: Data) {
        self.contactKey = .init(data: data)
    }

    @objc convenience override init() {
        self.init(data: Randomness.generateRandomBytes(StorageService.ContactKey.keyLength))
    }

    public override func isEqual(_ object: Any?) -> Bool {
        guard let object = object as? ContactKeyObjc else { return false }
        return contactKey == object.contactKey
    }

    public override var hash: Int {
        return contactKey.hashValue
    }
}

// MARK: -

public extension StorageServiceProtoContactRecord {
    var contactKey: StorageService.ContactKey { return .init(data: key) }
}

// MARK: - Test Helpers

#if DEBUG

public extension StorageService {
    static func test() {
        let testNames = ["abc", "def", "ghi", "jkl", "mno"]
        var contactsInManifest = [StorageServiceProtoContactRecord]()
        for i in 0...4 {
            let key = StorageService.ContactKey()

            let recordBuilder = StorageServiceProtoContactRecord.builder(key: key.data)
            recordBuilder.setProfileKey(Randomness.generateRandomBytes(16))
            recordBuilder.setProfileName(testNames[i])

            contactsInManifest.append(try! recordBuilder.build())
        }

        let keysInManfest = contactsInManifest.map { $0.contactKey }

        var ourManifestVersion: UInt64 = 0

        // Fetch Existing
        fetchManifest().map { manifest in
            let previousVersion = manifest?.version ?? ourManifestVersion
            ourManifestVersion = previousVersion + 1

            // set keys
            let newManifestBuilder = StorageServiceProtoManifestRecord.builder(version: ourManifestVersion)
            newManifestBuilder.setKeys(contactsInManifest.map { $0.key })

            return (try! newManifestBuilder.build(), manifest?.keys.map { ContactKey(data: $0) } ?? [])

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

            guard Set(manifest.keys) == Set(keysInManfest.map { $0.data }) else {
                owsFailDebug("manifest should only contain our test keys")
                throw StorageError.assertion
            }

            guard manifest.version == ourManifestVersion else {
                owsFailDebug("manifest version should be the version we set")
                throw StorageError.assertion
            }

        // Fetch the first contact we just stored
        }.then {
            fetchContact(for: keysInManfest.first!)
        }.map { contact in
            guard contact!.key == keysInManfest.first!.data else {
                owsFailDebug("this should be the contact we set")
                throw StorageError.assertion
            }

            guard contact!.profileName == contactsInManifest.first!.profileName else {
                owsFailDebug("this should be the contact we set")
                throw StorageError.assertion
            }

            guard contact!.profileKey == contactsInManifest.first!.profileKey else {
                owsFailDebug("this should be the contact we set")
                throw StorageError.assertion
            }

        // Fetch all the contacts we stored
        }.then {
            fetchContacts(for: keysInManfest)
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

                guard contact.profileName == matchingContact.profileName else {
                    owsFailDebug("this should be a contact we set")
                    throw StorageError.assertion
                }

                guard contact.profileKey == matchingContact.profileKey else {
                    owsFailDebug("this should be the contact we set")
                    throw StorageError.assertion
                }
            }

        // Fetch a contact that doesn't exist
        }.then {
            fetchContact(for: ContactKey())
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
            updateManifest(manifest, newContacts: [], deletedContacts: keysInManfest)
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

            let key = ContactKey()

            let recordBuilder = StorageServiceProtoContactRecord.builder(key: key.data)
            recordBuilder.setProfileKey(Randomness.generateRandomBytes(16))
            recordBuilder.setProfileName(testNames[0])

            oldManifestBuilder.setKeys([key.data])

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
        }
    }
}

#endif
