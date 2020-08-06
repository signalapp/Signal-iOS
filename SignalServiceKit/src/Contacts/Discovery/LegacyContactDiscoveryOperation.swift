//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

/// Fetches contact info from the ContactDiscoveryService
/// Intended to be used by ContactDiscoveryTask. You probably don't want to use this directly.
class LegacyContactDiscoveryOperation: ContactDiscovering {

    private let phoneNumbersToLookup: Set<String>
    required init(phoneNumbersToLookup: Set<String>) {
        self.phoneNumbersToLookup = phoneNumbersToLookup
        Logger.debug("with phoneNumbersToLookup: \(phoneNumbersToLookup.count)")
    }

    func perform(on queue: DispatchQueue) -> Promise<Set<DiscoveredContactInfo>> {
        let phoneNumberByHashes = mapHashToPhoneNumber()

        return Promise<Any?> { (resolver) in
            let hashes = Array(phoneNumberByHashes.keys)
            self.makeRequest(for: hashes, on: queue, responseResolver: resolver)

        }.map(on: queue) { (response) -> Set<DiscoveredContactInfo> in
            let discoveredNumbers = try self.parse(response: response, phoneNumbersByHashes: phoneNumberByHashes)
            return Set(discoveredNumbers.map { DiscoveredContactInfo(e164: $0, uuid: nil) })
        }
    }

    // MARK: - Private

    private func mapHashToPhoneNumber() -> [String: String] {
        var phoneNumbersByHashes: [String: String] = [:]

        for phoneNumber in phoneNumbersToLookup {
            guard let hash = Cryptography.truncatedSHA1Base64EncodedWithoutPadding(phoneNumber) else {
                owsFailDebug("could not hash recipient id: \(phoneNumber)")
                continue
            }
            assert(phoneNumbersByHashes[hash] == nil)
            phoneNumbersByHashes[hash] = phoneNumber
        }
        return phoneNumbersByHashes
    }

    private func makeRequest(for hashes: [String],
                     on queue: DispatchQueue,
                     responseResolver: Resolver<Any?>) {
        let request = OWSRequestFactory.contactsIntersectionRequest(withHashesArray: hashes)

        self.networkManager.makeRequest(
            request,
            completionQueue: queue,
            success: { (task, responseDict) in
                responseResolver.fulfill(responseDict)
            },
            failure: { (task, error) in
                guard let response = task.response as? HTTPURLResponse else {
                    if IsNetworkConnectivityFailure(error) {
                        responseResolver.reject(error)
                    } else {
                        let responseError: NSError = OWSErrorMakeUnableToProcessServerResponseError() as NSError
                        responseError.isRetryable = true
                        responseResolver.reject(responseError)
                    }
                    return
                }

                guard response.statusCode != 413 else {
                    let nsError = OWSErrorWithCodeDescription(OWSErrorCode.contactDiscoveryRateLimit, "Contacts Intersection Rate Limit") as NSError
                    nsError.isRetryable = false
                    responseResolver.reject(nsError)
                    return
                }
                responseResolver.reject(error)
            }
        )
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

// MARK: - Dependencies

extension LegacyContactDiscoveryOperation {
    private var networkManager: TSNetworkManager {
        return TSNetworkManager.shared()
    }
}
