//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSContactDiscoveryOperation)
class ContactDiscoveryOperation: OWSOperation, LegacyContactDiscoveryBatchOperationDelegate {

    let batchSize = 2048
    let recipientIdsToLookup: [String]

    @objc
    var registeredRecipientIds: Set<String>

    @objc
    required init(recipientIdsToLookup: [String]) {
        self.recipientIdsToLookup = recipientIdsToLookup
        self.registeredRecipientIds = Set()

        super.init()

        Logger.debug("\(logTag) in \(#function) with recipientIdsToLookup: \(recipientIdsToLookup.count)")
        for batchIds in recipientIdsToLookup.chunked(by: batchSize) {
            let batchOperation = LegacyContactDiscoveryBatchOperation(recipientIdsToLookup: batchIds)
            batchOperation.delegate = self
            self.addDependency(batchOperation)
        }
    }

    // MARK: Mandatory overrides

    // Called every retry, this is where the bulk of the operation's work should go.
    override func run() {
        Logger.debug("\(logTag) in \(#function)")

        for dependency in self.dependencies {
            guard let batchOperation = dependency as? LegacyContactDiscoveryBatchOperation else {
                owsFail("\(self.logTag) in \(#function) unexpected dependency: \(dependency)")
                continue
            }

            self.registeredRecipientIds.formUnion(batchOperation.registeredRecipientIds)
        }

        self.reportSuccess()
    }

    // MARK: LegacyContactDiscoveryBatchOperationDelegate
    func contactDiscoverBatchOperation(_ contactDiscoverBatchOperation: LegacyContactDiscoveryBatchOperation, didFailWithError error: Error) {
        Logger.debug("\(logTag) in \(#function) canceling self and all dependencies.")

        self.dependencies.forEach { $0.cancel() }
        self.cancel()
    }
}

protocol LegacyContactDiscoveryBatchOperationDelegate: class {
    func contactDiscoverBatchOperation(_ contactDiscoverBatchOperation: LegacyContactDiscoveryBatchOperation, didFailWithError error: Error)
}

class LegacyContactDiscoveryBatchOperation: OWSOperation {

    var registeredRecipientIds: Set<String>
    weak var delegate: LegacyContactDiscoveryBatchOperationDelegate?

    private let recipientIdsToLookup: [String]
    private var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }

    // MARK: Initializers

    required init(recipientIdsToLookup: [String]) {
        self.recipientIdsToLookup = recipientIdsToLookup
        self.registeredRecipientIds = Set()

        super.init()

        Logger.debug("\(logTag) in \(#function) with recipientIdsToLookup: \(recipientIdsToLookup.count)")
    }

    // MARK: OWSOperation Overrides

    // Called every retry, this is where the bulk of the operation's work should go.
    override func run() {
        Logger.debug("\(logTag) in \(#function)")

        guard !isCancelled else {
            Logger.info("\(logTag) in \(#function) no work to do, since we were canceled")
            self.reportCancelled()
            return
        }

        var phoneNumbersByHashes: [String: String] = [:]

        for recipientId in recipientIdsToLookup {
            let hash = Cryptography.truncatedSHA1Base64EncodedWithoutPadding(recipientId)
            assert(phoneNumbersByHashes[hash] == nil)
            phoneNumbersByHashes[hash] = recipientId
        }

        let hashes: [String] = Array(phoneNumbersByHashes.keys)

        let request = OWSRequestFactory.contactsIntersectionRequest(withHashesArray: hashes)

        self.networkManager.makeRequest(request,
                                        success: { (task, responseDict) in
                                            do {
                                                self.registeredRecipientIds = try self.parse(response: responseDict, phoneNumbersByHashes: phoneNumbersByHashes)
                                                self.reportSuccess()
                                            } catch {
                                                self.reportError(error)
                                            }
        },
                                        failure: { (task, error) in
                                            guard let response = task.response as? HTTPURLResponse else {
                                                let responseError: NSError = OWSErrorMakeUnableToProcessServerResponseError() as NSError
                                                responseError.isRetryable = true
                                                self.reportError(responseError)
                                                return
                                            }

                                            guard response.statusCode != 413 else {
                                                let rateLimitError = OWSErrorWithCodeDescription(OWSErrorCode.contactsUpdaterRateLimit, "Contacts Intersection Rate Limit")
                                                self.reportError(rateLimitError)
                                                return
                                            }

                                            self.reportError(error)
        })
    }

    // Called at most one time.
    override func didSucceed() {
        // Compare against new CDS service
        let newCDSBatchOperation = CDSBatchOperation(recipientIdsToLookup: self.recipientIdsToLookup)
        let cdsFeedbackOperation = CDSFeedbackOperation(legacyRegisteredRecipientIds: self.registeredRecipientIds)
        cdsFeedbackOperation.addDependency(newCDSBatchOperation)

        CDSFeedbackOperation.operationQueue.addOperations([newCDSBatchOperation, cdsFeedbackOperation], waitUntilFinished: false)
    }

    // Called at most one time.
    override func didFail(error: Error) {
        self.delegate?.contactDiscoverBatchOperation(self, didFailWithError: error)
    }

    // MARK: Private Helpers

    private func parse(response: Any?, phoneNumbersByHashes: [String: String]) throws -> Set<String> {

        guard let responseDict = response as? [String: AnyObject] else {
            let responseError: NSError = OWSErrorMakeUnableToProcessServerResponseError() as NSError
            responseError.isRetryable = true

            throw responseError
        }

        guard let contactDicts = responseDict["contacts"] as? [[String: AnyObject]] else {
            let responseError: NSError = OWSErrorMakeUnableToProcessServerResponseError() as NSError
            responseError.isRetryable = true

            throw responseError
        }

        var registeredRecipientIds: Set<String> = Set()

        for contactDict in contactDicts {
            guard let hash = contactDict["token"] as? String, hash.count > 0 else {
                owsFail("\(self.logTag) in \(#function) hash was unexpectedly nil")
                continue
            }

            guard let recipientId = phoneNumbersByHashes[hash], recipientId.count > 0 else {
                owsFail("\(self.logTag) in \(#function) recipientId was unexpectedly nil")
                continue
            }

            guard recipientIdsToLookup.contains(recipientId) else {
                owsFail("\(self.logTag) in \(#function) unexpected recipientId")
                continue
            }

            registeredRecipientIds.insert(recipientId)
        }

        return registeredRecipientIds
    }

}

public
class CDSBatchOperation: OWSOperation {

    enum CDSBatchOperationError: Error {
        case parseError(description: String)
        case assertionError(description: String)
    }

    private let recipientIdsToLookup: [String]
    var registeredRecipientIds: Set<String>

    private var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }

    private var contactDiscoveryService: ContactDiscoveryService {
        return ContactDiscoveryService.shared()
    }

    // MARK: Initializers

    public required init(recipientIdsToLookup: [String]) {
        self.recipientIdsToLookup = Set(recipientIdsToLookup).map { $0 }
        self.registeredRecipientIds = Set()

        super.init()

        Logger.debug("\(logTag) in \(#function) with recipientIdsToLookup: \(recipientIdsToLookup.count)")
    }

    // MARK: OWSOperationOverrides

    // Called every retry, this is where the bulk of the operation's work should go.
    override public func run() {
        Logger.debug("\(logTag) in \(#function)")

        guard !isCancelled else {
            Logger.info("\(logTag) in \(#function) no work to do, since we were canceled")
            self.reportCancelled()
            return
        }

        contactDiscoveryService.performRemoteAttestation(success: { (remoteAttestation: RemoteAttestation) in
            self.makeContactDiscoveryRequest(remoteAttestation: remoteAttestation)
        },
                                     failure: self.reportError)
    }

    private func makeContactDiscoveryRequest(remoteAttestation: RemoteAttestation) {

        guard !isCancelled else {
            Logger.info("\(logTag) in \(#function) no work to do, since we were canceled")
            self.reportCancelled()
            return
        }

        let encryptionResult: AES25GCMEncryptionResult
        do {
            encryptionResult = try encryptAddresses(recipientIds: recipientIdsToLookup, remoteAttestation: remoteAttestation)
        } catch {
            reportError(error)
            return
        }

        let request = OWSRequestFactory.enclaveContactDiscoveryRequest(withId: remoteAttestation.requestId,
                                                                       addressCount: UInt(recipientIdsToLookup.count),
                                                                       encryptedAddressData: encryptionResult.ciphertext,
                                                                       cryptIv: encryptionResult.initializationVector,
                                                                       cryptMac: encryptionResult.authTag,
                                                                       enclaveId: remoteAttestation.enclaveId,
                                                                       authUsername: remoteAttestation.authUsername,
                                                                       authPassword: remoteAttestation.authToken,
                                                                       cookies: remoteAttestation.cookies)

        self.networkManager.makeRequest(request,
                                        success: { (task, responseDict) in
                                            do {
                                                self.registeredRecipientIds = try self.handle(response: responseDict, remoteAttestation: remoteAttestation)
                                                self.reportSuccess()
                                            } catch {
                                                self.reportError(error)
                                            }
        },
                                        failure: { (task, error) in
                                            guard let response = task.response as? HTTPURLResponse else {
                                                let responseError: NSError = OWSErrorMakeUnableToProcessServerResponseError() as NSError
                                                responseError.isRetryable = true
                                                self.reportError(responseError)
                                                return
                                            }

                                            guard response.statusCode != 413 else {
                                                let rateLimitError = OWSErrorWithCodeDescription(OWSErrorCode.contactsUpdaterRateLimit, "Contacts Intersection Rate Limit")
                                                self.reportError(rateLimitError)
                                                return
                                            }

                                            self.reportError(error)
        })
    }

    func encryptAddresses(recipientIds: [String], remoteAttestation: RemoteAttestation) throws -> AES25GCMEncryptionResult {

        let addressPlainTextData = try type(of: self).encodePhoneNumbers(recipientIds: recipientIds)

        guard let encryptionResult = Cryptography.encryptAESGCM(plainTextData: addressPlainTextData,
                                                                additionalAuthenticatedData: remoteAttestation.requestId,
                                                                key: remoteAttestation.keys.clientKey) else {

            throw CDSBatchOperationError.assertionError(description: "Encryption failure")
        }

        return encryptionResult
    }

    class func encodePhoneNumbers(recipientIds: [String]) throws -> Data {
        var output = Data()

        for recipientId in recipientIds {
            guard recipientId.prefix(1) == "+" else {
                throw CDSBatchOperationError.assertionError(description: "unexpected id format")
            }

            let numericPortionIndex = recipientId.index(after: recipientId.startIndex)
            let numericPortion = recipientId.suffix(from: numericPortionIndex)

            guard let numericIdentifier = UInt64(numericPortion), numericIdentifier > 99 else {
                throw CDSBatchOperationError.assertionError(description: "unexpectedly short identifier")
            }

            var bigEndian: UInt64 = CFSwapInt64HostToBig(numericIdentifier)
            let buffer = UnsafeBufferPointer(start: &bigEndian, count: 1)
            output.append(buffer)
        }

        return output
    }

    func handle(response: Any?, remoteAttestation: RemoteAttestation) throws -> Set<String> {
        let isIncludedData: Data = try parseAndDecrypt(response: response, remoteAttestation: remoteAttestation)
        guard let isIncluded: [Bool] = type(of: self).boolArray(data: isIncludedData) else {
            throw CDSBatchOperationError.assertionError(description: "isIncluded was unexpectedly nil")
        }

        return try match(recipientIds: self.recipientIdsToLookup, isIncluded: isIncluded)
    }

    class func boolArray(data: Data) -> [Bool]? {
        var bools: [Bool]? = nil
        data.withUnsafeBytes { (bytes: UnsafePointer<Bool>) -> Void in
            let buffer = UnsafeBufferPointer(start: bytes, count: data.count)
            bools = Array(buffer)
        }

        return bools
    }

    func match(recipientIds: [String], isIncluded: [Bool]) throws -> Set<String> {
        guard recipientIds.count == isIncluded.count else {
            throw CDSBatchOperationError.assertionError(description: "length mismatch for isIncluded/recipientIds")
        }

        let includedRecipientIds: [String] = (0..<recipientIds.count).compactMap { index in
            isIncluded[index] ? recipientIds[index] : nil
        }

        return Set(includedRecipientIds)
    }

    func parseAndDecrypt(response: Any?, remoteAttestation: RemoteAttestation) throws -> Data {

        guard let responseDict = response as? [String: AnyObject] else {
            throw CDSBatchOperationError.parseError(description: "missing response dict")
        }

        let cipherText = try responseDict.expectBase64EncodedData(key: "data")
        let initializationVector = try responseDict.expectBase64EncodedData(key: "iv")
        let authTag = try responseDict.expectBase64EncodedData(key: "mac")

        guard let plainText = Cryptography.decryptAESGCM(withInitializationVector: initializationVector,
                                                          ciphertext: cipherText,
                                                          additionalAuthenticatedData: nil,
                                                          authTag: authTag,
                                                          key: remoteAttestation.keys.serverKey) else {

                                                            throw CDSBatchOperationError.parseError(description: "decryption failed")
        }

        return plainText
    }
}

class CDSFeedbackOperation: OWSOperation {

    static let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1

        return queue
    }()

    private let legacyRegisteredRecipientIds: Set<String>

    // MARK: Initializers

    required init(legacyRegisteredRecipientIds: Set<String>) {
        self.legacyRegisteredRecipientIds = legacyRegisteredRecipientIds

        super.init()

        Logger.debug("\(logTag) in \(#function)")
    }

    // MARK: OWSOperation Overrides

    // Called every retry, this is where the bulk of the operation's work should go.
    override func run() {
        guard let cdsOperation = dependencies.first as? CDSBatchOperation else {
            let error = OWSErrorMakeAssertionError("\(self.logTag) in \(#function) cdsOperation was unexpectedly nil")
            self.reportError(error)
            return
        }

        let cdsRegisteredRecipientIds = cdsOperation.registeredRecipientIds

        if cdsRegisteredRecipientIds == legacyRegisteredRecipientIds {
            Logger.debug("\(logTag) in \(#function) TODO: PUT /v1/directory/feedback/ok")
        } else {
            Logger.debug("\(logTag) in \(#function) TODO: PUT /v1/directory/feedback/mismatch")
        }

        self.reportSuccess()
    }

    override func didFail(error: Error) {
        // dependency failed.
        // Depending on error, PUT one of:
        // /v1/directory/feedback/server-error:
        // /v1/directory/feedback/client-error:
        // /v1/directory/feedback/attestation-error:
        // /v1/directory/feedback/unexpected-error:
        Logger.debug("\(logTag) in \(#function) TODO: PUT /v1/directory/feedback/*-error")
    }
}

extension Array {
    func chunked(by chunkSize: Int) -> [[Element]] {
        return stride(from: 0, to: self.count, by: chunkSize).map {
            Array(self[$0..<Swift.min($0 + chunkSize, self.count)])
        }
    }
}

extension Dictionary where Key: Hashable {

    enum DictionaryError: Error {
        case missingField(Key)
        case invalidFormat(Key)
    }

    public func expectBase64EncodedData(key: Key) throws -> Data {
        guard let encodedData = self[key] as? String else {
            throw DictionaryError.missingField(key)
        }

        guard let data = Data(base64Encoded: encodedData) else {
            throw DictionaryError.invalidFormat(key)
        }

        return data
    }
}
