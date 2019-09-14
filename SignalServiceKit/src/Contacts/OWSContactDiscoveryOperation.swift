//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

@objc(OWSLegacyContactDiscoveryOperation)
public class LegacyContactDiscoveryOperation: OWSOperation {

    @objc
    public var registeredPhoneNumbers: Set<String>?

    @objc
    public var registeredAddresses: Set<SignalServiceAddress>?

    private var phoneNumbersToLookup: [String] {
        return contactsToLookup.map { $0.e164PhoneNumber }
    }

    private let contactsToLookup: [CDSContactQuery]

    // MARK: - Dependencies

    private var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }

    // MARK: - Initializers

    public required init(contactsToLookup: [CDSContactQuery]) {
        self.contactsToLookup = contactsToLookup
        Logger.debug("with contactsToLookup: \(contactsToLookup.count)")
    }

    // MARK: - OWSOperation Overrides

    // Called every retry, this is where the bulk of the operation's work should go.
    override public func run() {
        Logger.debug("")

        guard !isCancelled else {
            Logger.info("no work to do, since we were canceled")
            self.reportCancelled()
            return
        }

        var phoneNumbersByHashes: [String: String] = [:]

        for phoneNumber in phoneNumbersToLookup {
            guard let hash = Cryptography.truncatedSHA1Base64EncodedWithoutPadding(phoneNumber) else {
                owsFailDebug("could not hash recipient id: \(phoneNumber)")
                continue
            }
            assert(phoneNumbersByHashes[hash] == nil)
            phoneNumbersByHashes[hash] = phoneNumber
        }

        let hashes: [String] = Array(phoneNumbersByHashes.keys)

        let request = OWSRequestFactory.contactsIntersectionRequest(withHashesArray: hashes)

        self.networkManager.makeRequest(request,
                                        success: { (task, responseDict) in
                                            do {
                                                self.registeredPhoneNumbers = try self.parse(response: responseDict, phoneNumbersByHashes: phoneNumbersByHashes)
                                                self.reportSuccess()
                                            } catch {
                                                self.reportError(withUndefinedRetry: error)
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
                                                let nsError = OWSErrorWithCodeDescription(OWSErrorCode.contactsUpdaterRateLimit, "Contacts Intersection Rate Limit") as NSError
                                                nsError.isRetryable = false
                                                self.reportError(nsError)
                                                return
                                            }

                                            self.reportError(withUndefinedRetry: error)
        })
    }

    // Called at most one time.
    override public func didSucceed() {
        guard !IsUsingProductionService() else {
            // comparison disabled in prod for now
            return
        }

        // Compare against new CDS service
        let modernContactDiscoveryOperation = ContactDiscoveryOperation(contactsToLookup: self.contactsToLookup)

        let operations = modernContactDiscoveryOperation.dependencies + [modernContactDiscoveryOperation]
        ContactDiscoveryOperation.operationQueue.addOperations(operations, waitUntilFinished: false)

        guard let legacyRegisteredPhoneNumbers = self.registeredPhoneNumbers else {
            owsFailDebug("legacyRegisteredPhoneNumbers was unexpectedly nil")
            return
        }

        let cdsFeedbackOperation = CDSFeedbackOperation(legacyRegisteredPhoneNumbers: legacyRegisteredPhoneNumbers)
        cdsFeedbackOperation.addDependency(modernContactDiscoveryOperation)
        ContactDiscoveryOperation.operationQueue.addOperation(cdsFeedbackOperation)
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

            guard let phoneNumber = phoneNumbersByHashes[hash], phoneNumber.count > 0 else {
                owsFailDebug("phoneNumber was unexpectedly nil")
                continue
            }

            guard phoneNumbersToLookup.contains(phoneNumber) else {
                owsFailDebug("unexpected phoneNumber")
                continue
            }

            registeredRecipientIds.insert(phoneNumber)
        }

        return registeredRecipientIds
    }

}

enum ContactDiscoveryError: Error {
    case parseError(description: String)
    case assertionError(description: String)
    case clientError(underlyingError: Error)
    case serverError(underlyingError: Error)
}

@objc(SSKContactDiscoveryOperation)
public class ContactDiscoveryOperation: OWSOperation {

    let batchSize = 2048
    static let operationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 5
        queue.name = ContactDiscoveryOperation.logTag()
        return queue
    }()

    @objc
    public var registeredAddresses: Set<SignalServiceAddress> {
        assert(!dependencies.map { $0.isFinished }.contains(false))
        return Set(registeredContacts.map { $0.address })
    }

    let contactsToLookup: [CDSContactQuery]
    var registeredContacts: Set<CDSRegisteredContact>

    required init(contactsToLookup: [CDSContactQuery]) {
        assert(contactsToLookup.count == Set(contactsToLookup.map { $0.e164PhoneNumber }).count)
        self.contactsToLookup = contactsToLookup
        self.registeredContacts = Set()

        super.init()

        Logger.debug("with contactsToLookup.count: \(contactsToLookup.count)")
        for batchContacts in contactsToLookup.chunked(by: batchSize) {
            let batchOperation = CDSBatchOperation(contactsToLookup: batchContacts)
            self.addDependency(batchOperation)
        }
    }

    // MARK: Mandatory overrides

    // Called every retry, this is where the bulk of the operation's work should go.
    override public func run() {
        Logger.debug("")

        for dependency in self.dependencies {
            guard let batchOperation = dependency as? CDSBatchOperation else {
                owsFailDebug("unexpected dependency: \(dependency)")
                continue
            }

            guard let registeredContactsBatch = batchOperation.registeredContacts else {
                owsFailDebug("registeredContactsBatch was unexpectedly nil")
                continue
            }

            self.registeredContacts.formUnion(registeredContactsBatch)
        }

        self.reportSuccess()
    }

}

public
class CDSBatchOperation: OWSOperation {

    private let contactsToLookup: [CDSContactQuery]
    private var phoneNumbersToLookup: [String] {
        return contactsToLookup.map { $0.e164PhoneNumber }
    }

    private(set) var registeredContacts: Set<CDSRegisteredContact>?
    private(set) var erroredContacts: Set<CDSErroredContact>?

    var contactDiscoveryService: ContactDiscoveryService {
        return ContactDiscoveryService()
    }

    // MARK: Initializers

    public required init(contactsToLookup: [CDSContactQuery]) {
        self.contactsToLookup = contactsToLookup

        super.init()

        Logger.debug("with contactsToLookup: \(contactsToLookup.count)")
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

        firstly {
            self.makeContactDiscoveryRequest(contactsToLookup: self.contactsToLookup)
        }.done(on: .global()) { (registeredContacts, erroredContacts) in
            self.registeredContacts = registeredContacts
            self.erroredContacts = erroredContacts
            self.reportSuccess()
        }.catch(on: .global()) { error in
            switch error {
            case let serviceError as ContactDiscoveryService.ServiceError:
                self.reportError(serviceError)
            default:
                self.reportError(withUndefinedRetry: error)
            }
        }.retainUntilComplete()
    }

    typealias IntersectionResult = (Set<CDSRegisteredContact>, Set<CDSErroredContact>)
    private func makeContactDiscoveryRequest(contactsToLookup: [CDSContactQuery]) -> Promise<IntersectionResult> {
        let contactCount = UInt(contactsToLookup.count)

        return firstly { () -> Promise<RemoteAttestation> in
            return RemoteAttestation.perform(for: .contactDiscovery)
        }.then(on: .global()) { (remoteAttestation: RemoteAttestation) -> Promise<IntersectionResult> in
            return firstly { () -> Promise<ContactDiscoveryService.IntersectionResponse> in
                let encryptionResult = try self.buildEncryptedRequestData(contacts: self.contactsToLookup,
                                                                          remoteAttestation: remoteAttestation)

                assert(encryptionResult.ciphertext.count == contactCount * 40)
                return self.contactDiscoveryService.getRegisteredSignalUsers(remoteAttestation: remoteAttestation,
                                                                             addressCount: contactCount,
                                                                             encryptedAddressData: encryptionResult.ciphertext,
                                                                             cryptIv: encryptionResult.initializationVector,
                                                                             cryptMac: encryptionResult.authTag)
            }.map(on: .global()) { response -> IntersectionResult in
                guard let plaintext = Cryptography.decryptAESGCM(withInitializationVector: response.iv,
                                                                 ciphertext: response.data,
                                                                 additionalAuthenticatedData: nil,
                                                                 authTag: response.mac,
                                                                 key: remoteAttestation.keys.serverKey) else {
                                                                    throw ContactDiscoveryError.parseError(description: "decryption failed")
                }

                // 16 bytes per UUID + 1 byte per error
                assert(plaintext.count == contactCount * 17)
                let dataParser = OWSDataParser(data: plaintext)
                let errorsData = try dataParser.nextData(length: contactCount, name: "errors")
                let uuidsData = try dataParser.nextData(length: contactCount * 16, name: "uuids")

                guard dataParser.isEmpty else {
                    throw OWSAssertionError("failed check: dataParse.isEmpty")
                }

                let errors = type(of: self).boolArray(from: errorsData)
                let uuids = type(of: self).uuidArray(from: uuidsData)

                guard uuids.count == contactCount else {
                    throw OWSAssertionError("failed check: uuids.count == contactCount")
                }

                guard errors.count == uuids.count else {
                    throw OWSAssertionError("failed check: errors.length == uuids.length")
                }

                let unregisteredUuid = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

                var registeredContacts: Set<CDSRegisteredContact> = Set()
                var erroredContacts: Set<CDSErroredContact> = Set()

                for (index, contactLookup) in contactsToLookup.enumerated() {
                    guard errors[index] == false else {
                        Logger.error("error with lookup for contact: \(contactLookup.e164PhoneNumber)")
                        erroredContacts.insert(CDSErroredContact(contact: contactLookup))
                        continue
                    }

                    guard uuids[index] != unregisteredUuid else {
                        Logger.verbose("not a signal user: \(contactLookup.e164PhoneNumber)")
                        continue
                    }

                    Logger.verbose("signal user: \(contactLookup.e164PhoneNumber)")
                    registeredContacts.insert(CDSRegisteredContact(signalUuid: uuids[index],
                                                                   contact: contactLookup))
                }

                return (registeredContacts, erroredContacts)
            }
        }
    }

    func buildEncryptedRequestData(contacts: [CDSContactQuery], remoteAttestation: RemoteAttestation) throws -> AES25GCMEncryptionResult {

        let addressPlainTextData = try type(of: self).encodePhoneNumbers(contacts.map { $0.e164PhoneNumber })
        let noncePlainTextData = Data(contacts.flatMap { $0.nonce })

        let plaintext = Data.join([addressPlainTextData, noncePlainTextData])

        guard let encryptionResult = Cryptography.encryptAESGCM(plainTextData: plaintext,
                                                                additionalAuthenticatedData: remoteAttestation.requestId,
                                                                key: remoteAttestation.keys.clientKey) else {

            throw ContactDiscoveryError.assertionError(description: "Encryption failure")
        }

        return encryptionResult
    }

    class func encodePhoneNumbers(_ phoneNumbers: [String]) throws -> Data {
        var output = Data()

        for phoneNumber in phoneNumbers {
            guard phoneNumber.prefix(1) == "+" else {
                throw ContactDiscoveryError.assertionError(description: "unexpected id format")
            }

            let numericPortionIndex = phoneNumber.index(after: phoneNumber.startIndex)
            let numericPortion = phoneNumber.suffix(from: numericPortionIndex)

            guard let numericIdentifier = UInt64(numericPortion), numericIdentifier > 99 else {
                throw ContactDiscoveryError.assertionError(description: "unexpectedly short identifier")
            }

            var bigEndian: UInt64 = CFSwapInt64HostToBig(numericIdentifier)
            let buffer = UnsafeBufferPointer(start: &bigEndian, count: 1)
            output.append(buffer)
        }

        return output
    }

    class func boolArray(from data: Data) -> [Bool] {
        return data.withUnsafeBytes {
            [Bool]($0.bindMemory(to: Bool.self))
        }
    }

    class func uuidArray(from data: Data) -> [UUID] {
        return data.withUnsafeBytes {
            [uuid_t]($0.bindMemory(to: uuid_t.self))
        }.map {
            UUID(uuid: $0)
        }
    }
}

class CDSFeedbackOperation: OWSOperation {

    enum FeedbackResult {
        case ok
        case mismatch
        case attestationError(reason: String)
        case unexpectedError(reason: String)
    }

    private let legacyRegisteredPhoneNumbers: Set<String>

    var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }

    // MARK: Initializers

    required init(legacyRegisteredPhoneNumbers: Set<String>) {
        self.legacyRegisteredPhoneNumbers = legacyRegisteredPhoneNumbers

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

        guard let cdsOperation = dependencies.first as? ContactDiscoveryOperation else {
            let error = OWSAssertionError("cdsOperation was unexpectedly nil")
            self.reportError(error)
            return
        }

        if let error = cdsOperation.failingError {
            switch error {
            case TSNetworkManagerError.failedConnection:
                // Don't submit feedback for connectivity errors
                self.reportSuccess()
            case ContactDiscoveryError.serverError, ContactDiscoveryError.clientError:
                // Server already has this information, no need submit feedback
                self.reportSuccess()
            case let raError as RemoteAttestationError:
                let reason = raError.reason
                switch raError.code {
                case .assertionError:
                    self.makeRequest(result: .unexpectedError(reason: "Remote Attestation assertionError: \(reason ?? "unknown")"))
                case .failed:
                    self.makeRequest(result: .attestationError(reason: "Remote Attestation failed: \(reason ?? "unknown")"))
                @unknown default:
                    self.makeRequest(result: .unexpectedError(reason: "Remote Attestation assertionError: unknown raError.code"))
                }
            case ContactDiscoveryError.assertionError(let assertionDescription):
                self.makeRequest(result: .unexpectedError(reason: "assertionError: \(assertionDescription)"))
            case ContactDiscoveryError.parseError(description: let parseErrorDescription):
                self.makeRequest(result: .unexpectedError(reason: "parseError: \(parseErrorDescription)"))
            default:
                let nsError = error as NSError
                let reason = "unexpectedError code:\(nsError.code)"
                self.makeRequest(result: .unexpectedError(reason: reason))
            }

            return
        }

        let registeredPhoneNumbers = Set(cdsOperation.registeredContacts.map { $0.e164PhoneNumber })

        if registeredPhoneNumbers == legacyRegisteredPhoneNumbers {
            self.makeRequest(result: .ok)
            return
        } else {
            self.makeRequest(result: .mismatch)
            return
        }
    }

    func makeRequest(result: FeedbackResult) {
        let reason: String?
        switch result {
        case .ok:
            reason = nil
        case .mismatch:
            reason = nil
        case .attestationError(let attestationErrorReason):
            reason = attestationErrorReason
        case .unexpectedError(let unexpectedErrorReason):
            reason = unexpectedErrorReason
        }
        let request = OWSRequestFactory.cdsFeedbackRequest(status: result.statusPath, reason: reason)
        self.networkManager.makeRequest(request,
                                        success: { _, _ in self.reportSuccess() },
                                        failure: { _, error in self.reportError(withUndefinedRetry: error) })
    }
}

extension Array {
    func chunked(by chunkSize: Int) -> [[Element]] {
        return stride(from: 0, to: self.count, by: chunkSize).map {
            Array(self[$0..<Swift.min($0 + chunkSize, self.count)])
        }
    }
}

extension CDSFeedbackOperation.FeedbackResult {
    var statusPath: String {
        switch self {
        case .ok:
            return "ok"
        case .mismatch:
            return "mismatch"
        case .attestationError:
            return "attestation-error"
        case .unexpectedError:
            return "unexpected-error"
        }
    }
}

extension RemoteAttestationError {
    var reason: String? {
        return userInfo[RemoteAttestationErrorKey_Reason] as? String
    }
}

extension RemoteAttestation {
    class func perform(for service: RemoteAttestationService) -> Promise<RemoteAttestation> {
        return Promise { resolver in
            self.perform(for: service, success: resolver.fulfill, failure: resolver.reject)
        }
    }

    class func perform(for service: RemoteAttestationService, auth: RemoteAttestationAuth?) -> Promise<RemoteAttestation> {
        return Promise { resolver in
            self.perform(for: service, auth: auth, success: resolver.fulfill, failure: resolver.reject)
        }
    }
}

public struct CDSContactQuery {
    static let nonceLength: Int32 = 32

    let e164PhoneNumber: String
    let nonce: Data

    init(e164PhoneNumber: String, nonce: Data) throws {
        self.e164PhoneNumber = e164PhoneNumber
        guard nonce.count == type(of: self).nonceLength else {
            throw OWSAssertionError("invalid nonce length: \(nonce.count)")
        }
        self.nonce = nonce
    }
}

extension CDSContactQuery: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(e164PhoneNumber)
    }
}

extension CDSContactQuery: Equatable {
    public static func == (lhs: CDSContactQuery, rhs: CDSContactQuery) -> Bool {
        return lhs.e164PhoneNumber == rhs.e164PhoneNumber
    }
}

public struct CDSRegisteredContact: Hashable {
    let signalUuid: UUID
    let contact: CDSContactQuery

    var e164PhoneNumber: String {
        return contact.e164PhoneNumber
    }

    var address: SignalServiceAddress {
        return SignalServiceAddress(uuid: signalUuid, phoneNumber: e164PhoneNumber)
    }
}

public struct CDSErroredContact: Hashable {
    let contact: CDSContactQuery
    var e164PhoneNumber: String { return contact.e164PhoneNumber }
}

extension ContactDiscoveryService.ServiceError: OperationError {
    var isRetryable: Bool {
        switch self {
        case .error5xx:
            return true
        case .tooManyRequests:
            return false
        case .error4xx:
            return false
        case .invalidResponse:
            return true
        }
    }
}
