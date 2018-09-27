//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

@objc(OWSLegacyContactDiscoveryOperation)
class LegacyContactDiscoveryBatchOperation: OWSOperation {

    @objc
    var registeredRecipientIds: Set<String>

    private let recipientIdsToLookup: [String]
    private var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }

    // MARK: Initializers

    @objc
    required init(recipientIdsToLookup: [String]) {
        self.recipientIdsToLookup = recipientIdsToLookup
        self.registeredRecipientIds = Set()

        super.init()

        Logger.debug("with recipientIdsToLookup: \(recipientIdsToLookup.count)")
    }

    // MARK: OWSOperation Overrides

    // Called every retry, this is where the bulk of the operation's work should go.
    override func run() {
        Logger.debug("")

        guard !isCancelled else {
            Logger.info("no work to do, since we were canceled")
            self.reportCancelled()
            return
        }

        var phoneNumbersByHashes: [String: String] = [:]

        for recipientId in recipientIdsToLookup {
            guard let hash = Cryptography.truncatedSHA1Base64EncodedWithoutPadding(recipientId) else {
                owsFailDebug("could not hash recipient id: \(recipientId)")
                continue
            }
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
        let modernCDSOperation = CDSOperation(recipientIdsToLookup: self.recipientIdsToLookup)
        let cdsFeedbackOperation = CDSFeedbackOperation(legacyRegisteredRecipientIds: self.registeredRecipientIds)
        cdsFeedbackOperation.addDependency(modernCDSOperation)

        let operations = modernCDSOperation.dependencies + [modernCDSOperation, cdsFeedbackOperation]
        CDSOperation.operationQueue.addOperations(operations, waitUntilFinished: false)
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
                owsFailDebug("hash was unexpectedly nil")
                continue
            }

            guard let recipientId = phoneNumbersByHashes[hash], recipientId.count > 0 else {
                owsFailDebug("recipientId was unexpectedly nil")
                continue
            }

            guard recipientIdsToLookup.contains(recipientId) else {
                owsFailDebug("unexpected recipientId")
                continue
            }

            registeredRecipientIds.insert(recipientId)
        }

        return registeredRecipientIds
    }

}

enum ContactDiscoveryError: Error {
    case parseError(description: String)
    case assertionError(description: String)
    case attestationError(underlyingError: Error)
    case clientError(underlyingError: Error)
    case serverError(underlyingError: Error)
}

@objc(OWSCDSOperation)
class CDSOperation: OWSOperation {

    let batchSize = 2048
    static let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5
        queue.name = CDSOperation.logTag()
        return queue
    }()

    let recipientIdsToLookup: [String]

    @objc
    var registeredRecipientIds: Set<String>

    @objc
    required init(recipientIdsToLookup: [String]) {
        self.recipientIdsToLookup = recipientIdsToLookup
        self.registeredRecipientIds = Set()

        super.init()

        Logger.debug("with recipientIdsToLookup: \(recipientIdsToLookup.count)")
        for batchIds in recipientIdsToLookup.chunked(by: batchSize) {
            let batchOperation = CDSBatchOperation(recipientIdsToLookup: batchIds)
            self.addDependency(batchOperation)
        }
    }

    // MARK: Mandatory overrides

    // Called every retry, this is where the bulk of the operation's work should go.
    override func run() {
        Logger.debug("")

        for dependency in self.dependencies {
            guard let batchOperation = dependency as? CDSBatchOperation else {
                owsFailDebug("unexpected dependency: \(dependency)")
                continue
            }

            self.registeredRecipientIds.formUnion(batchOperation.registeredRecipientIds)
        }

        self.reportSuccess()
    }

}

public
class CDSBatchOperation: OWSOperation {

    private let recipientIdsToLookup: [String]
    private(set) var registeredRecipientIds: Set<String>

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

        Logger.debug("with recipientIdsToLookup: \(recipientIdsToLookup.count)")
    }

    // MARK: OWSOperationOverrides

    // Called every retry, this is where the bulk of the operation's work should go.
    override public func run() {
        Logger.debug("")

        guard !isCancelled else {
            Logger.info("no work to do, since we were canceled")
            self.reportCancelled()
            return
        }

        contactDiscoveryService.performRemoteAttestation(success: { (remoteAttestation: RemoteAttestation) in
            self.makeContactDiscoveryRequest(remoteAttestation: remoteAttestation)
        },
                                                         failure: self.attestationFailure)
    }

    private func attestationFailure(error: Error) {
        let attestationError: NSError = ContactDiscoveryError.attestationError(underlyingError: error) as NSError
        attestationError.isRetryable = false
        self.reportError(attestationError)
    }

    private func makeContactDiscoveryRequest(remoteAttestation: RemoteAttestation) {

        guard !isCancelled else {
            Logger.info("no work to do, since we were canceled")
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
                                                                       authUsername: remoteAttestation.auth.username,
                                                                       authPassword: remoteAttestation.auth.password,
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
                                                let responseError = OWSErrorMakeUnableToProcessServerResponseError() as NSError
                                                responseError.isRetryable = true
                                                self.reportError(responseError)
                                                return
                                            }

                                            guard response.statusCode != 413 else {
                                                let rateLimitError: NSError = OWSErrorWithCodeDescription(OWSErrorCode.contactsUpdaterRateLimit, "Contacts Intersection Rate Limit") as NSError

                                                // TODO CDS ratelimiting, handle Retry-After header if available
                                                rateLimitError.isRetryable = false
                                                self.reportError(rateLimitError)
                                                return
                                            }

                                            guard response.statusCode / 100 != 4 else {
                                                let clientError: NSError = ContactDiscoveryError.clientError(underlyingError: error) as NSError
                                                clientError.isRetryable = (error as NSError).isRetryable
                                                self.reportError(clientError)
                                                return
                                            }

                                            guard response.statusCode / 100 != 5 else {
                                                let serverError = ContactDiscoveryError.serverError(underlyingError: error) as NSError
                                                serverError.isRetryable = (error as NSError).isRetryable

                                                // TODO CDS ratelimiting, handle Retry-After header if available
                                                self.reportError(serverError)
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

            throw ContactDiscoveryError.assertionError(description: "Encryption failure")
        }

        return encryptionResult
    }

    class func encodePhoneNumbers(recipientIds: [String]) throws -> Data {
        var output = Data()

        for recipientId in recipientIds {
            guard recipientId.prefix(1) == "+" else {
                throw ContactDiscoveryError.assertionError(description: "unexpected id format")
            }

            let numericPortionIndex = recipientId.index(after: recipientId.startIndex)
            let numericPortion = recipientId.suffix(from: numericPortionIndex)

            guard let numericIdentifier = UInt64(numericPortion), numericIdentifier > 99 else {
                throw ContactDiscoveryError.assertionError(description: "unexpectedly short identifier")
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
            throw ContactDiscoveryError.assertionError(description: "isIncluded was unexpectedly nil")
        }

        return try match(recipientIds: self.recipientIdsToLookup, isIncluded: isIncluded)
    }

    class func boolArray(data: Data) -> [Bool]? {
        var bools: [Bool]?
        data.withUnsafeBytes { (bytes: UnsafePointer<Bool>) -> Void in
            let buffer = UnsafeBufferPointer(start: bytes, count: data.count)
            bools = Array(buffer)
        }

        return bools
    }

    func match(recipientIds: [String], isIncluded: [Bool]) throws -> Set<String> {
        guard recipientIds.count == isIncluded.count else {
            throw ContactDiscoveryError.assertionError(description: "length mismatch for isIncluded/recipientIds")
        }

        let includedRecipientIds: [String] = (0..<recipientIds.count).compactMap { index in
            isIncluded[index] ? recipientIds[index] : nil
        }

        return Set(includedRecipientIds)
    }

    func parseAndDecrypt(response: Any?, remoteAttestation: RemoteAttestation) throws -> Data {

        guard let params = ParamParser(responseObject: response) else {
            throw ContactDiscoveryError.parseError(description: "missing response dict")
        }

        let cipherText = try params.requiredBase64EncodedData(key: "data")
        let initializationVector = try params.requiredBase64EncodedData(key: "iv")
        let authTag = try params.requiredBase64EncodedData(key: "mac")

        guard let plainText = Cryptography.decryptAESGCM(withInitializationVector: initializationVector,
                                                         ciphertext: cipherText,
                                                         additionalAuthenticatedData: nil,
                                                         authTag: authTag,
                                                         key: remoteAttestation.keys.serverKey) else {
                                                            throw ContactDiscoveryError.parseError(description: "decryption failed")
        }

        return plainText
    }
}

class CDSFeedbackOperation: OWSOperation {

    enum FeedbackResult: String {
        case ok
        case mismatch
        case attestationError = "attestation-error"
        case unexpectedError = "unexpected-error"
    }

    private let legacyRegisteredRecipientIds: Set<String>

    var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }

    // MARK: Initializers

    required init(legacyRegisteredRecipientIds: Set<String>) {
        self.legacyRegisteredRecipientIds = legacyRegisteredRecipientIds

        super.init()

        Logger.debug("")
    }

    // MARK: OWSOperation Overrides

    override func checkForPreconditionError() -> Error? {
        // override super with no-op
        // In this rare case, we want to proceed even though our dependency might have an
        // error so we can report the details of that error to the feedback service.
        return nil
    }

    // Called every retry, this is where the bulk of the operation's work should go.
    override func run() {

        guard !isCancelled else {
            Logger.info("no work to do, since we were canceled")
            self.reportCancelled()
            return
        }

        guard let cdsOperation = dependencies.first as? CDSOperation else {
            let error = OWSErrorMakeAssertionError("cdsOperation was unexpectedly nil")
            self.reportError(error)
            return
        }

        if let error = cdsOperation.failingError {
            switch error {
            case ContactDiscoveryError.serverError, ContactDiscoveryError.clientError:
                // Server already has this information, no need to report.
                self.reportSuccess()
            case ContactDiscoveryError.attestationError:
                self.makeRequest(result: .attestationError)
            default:
                self.makeRequest(result: .unexpectedError)
            }

            return
        }

        if cdsOperation.registeredRecipientIds == legacyRegisteredRecipientIds {
            self.makeRequest(result: .ok)
            return
        } else {
            self.makeRequest(result: .mismatch)
            return
        }
    }

    func makeRequest(result: FeedbackResult) {
        let request = OWSRequestFactory.cdsFeedbackRequest(result: result.rawValue)
        self.networkManager.makeRequest(request,
                                        success: { _, _ in self.reportSuccess() },
                                        failure: { _, error in self.reportError(error) })
    }
}

extension Array {
    func chunked(by chunkSize: Int) -> [[Element]] {
        return stride(from: 0, to: self.count, by: chunkSize).map {
            Array(self[$0..<Swift.min($0 + chunkSize, self.count)])
        }
    }
}
