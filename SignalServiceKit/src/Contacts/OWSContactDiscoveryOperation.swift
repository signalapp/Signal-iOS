//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation

extension Array {
    func chunked(by chunkSize: Int) -> [[Element]] {
        return stride(from: 0, to: self.count, by: chunkSize).map {
            Array(self[$0..<Swift.min($0 + chunkSize, self.count)])
        }
    }
}

@objc
class OWSContactDiscoveryOperation: OWSOperation {

    // TODO verify proper batch size
//    let batchSize = 2048
    let batchSize = 10
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
            let batchOperation = OWSContactDiscoveryBatchOperation(recipientIdsToLookup: batchIds)
            self.addDependency(batchOperation)
        }
    }

    // MARK: Mandatory overrides
    // Called every retry, this is where the bulk of the operation's work should go.
    override func run() {
        Logger.debug("\(logTag) in \(#function)")

        for dependency in self.dependencies {
            guard let batchOperation = dependency as? OWSContactDiscoveryBatchOperation else {
                owsFail("\(self.logTag) in \(#function) unexpected dependency: \(dependency)")
                continue
            }

            self.registeredRecipientIds.formUnion(batchOperation.registeredRecipientIds)
        }

        self.reportSuccess()
    }

    // MARK: Optional Overrides

    // Called one time only
    override func checkForPreconditionError() -> Error? {
        return super.checkForPreconditionError()
    }

    // Called at most one time.
    override func didSucceed() {
        super.didSucceed()
    }

    // Called at most one time, once retry is no longer possible.
    override func didFail(error: Error) {
        super.didFail(error: error)
    }
}

class OWSContactDiscoveryBatchOperation: OWSOperation {

    private let recipientIdsToLookup: [String]
    var registeredRecipientIds: Set<String>

    required init(recipientIdsToLookup: [String]) {
        self.recipientIdsToLookup = recipientIdsToLookup
        self.registeredRecipientIds = Set()

        super.init()

        Logger.debug("\(logTag) in \(#function) with recipientIdsToLookup: \(recipientIdsToLookup.count)")
    }

    private var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }

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

    // MARK: Mandatory overrides
    // Called every retry, this is where the bulk of the operation's work should go.
    override func run() {
        Logger.debug("\(logTag) in \(#function)")

        var phoneNumbersByHashes: [String: String] = [:]

        for recipientId in recipientIdsToLookup {
            let hash = Cryptography.truncatedSHA1Base64EncodedWithoutPadding(recipientId)
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
                                            if (!IsNSErrorNetworkFailure(error)) {
                                                // FIXME not accessible in swift for some reason.
//                                                OWSProdError(OWSAnalyticsEvents.contactsErrorContactsIntersectionFailed)
                                            }

                                            guard let response = task.response as? HTTPURLResponse else {
                                                let responseError: NSError = OWSErrorMakeUnableToProcessServerResponseError() as NSError
                                                responseError.isRetryable = true
                                                self.reportError(responseError)
                                                return
                                            }

                                            if (response.statusCode == 413) {
                                                let rateLimitError = OWSErrorWithCodeDescription(OWSErrorCode.contactsUpdaterRateLimit, "Contacts Intersection Rate Limit")
                                                self.reportError(rateLimitError)
                                            }
                                            self.reportError(error)

        })
    }

    // MARK: Optional Overrides

    // Called one time only
    override func checkForPreconditionError() -> Error? {
        return super.checkForPreconditionError()
    }

    // Called at most one time.
    override func didSucceed() {
        super.didSucceed()
    }

    // Called at most one time, once retry is no longer possible.
    override func didFail(error: Error) {
        super.didFail(error: error)
    }
}
