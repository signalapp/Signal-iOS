//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

import Foundation
import PromiseKit

/// Fetches contact info from the ContactDiscoveryService
/// Intended to be used by ContactDiscoveryTask. You probably don't want to use this directly.
class LegacyContactDiscoveryOperation: ContactDiscovering {

    private let e164sToLookup: Set<String>
    required init(e164sToLookup: Set<String>) {
        self.e164sToLookup = e164sToLookup
        Logger.debug("with e164sToLookup.count: \(e164sToLookup.count)")
    }

    func perform(on queue: DispatchQueue) -> Promise<Set<DiscoveredContactInfo>> {
        let e164sByHash = mapHashToE164()

        return Promise<Any?> { (resolver) in
            let hashes = Array(e164sByHash.keys)
            self.makeRequest(for: hashes, on: queue, responseResolver: resolver)

        }.map(on: queue) { (response) -> Set<DiscoveredContactInfo> in
            let discoveredNumbers = try self.parse(response: response, e164sByHash: e164sByHash)
            return Set(discoveredNumbers.map { DiscoveredContactInfo(e164: $0, uuid: nil) })
        }
    }

    // MARK: - Private

    private func mapHashToE164() -> [String: String] {
        var e164sByHash: [String: String] = [:]

        for e164 in e164sToLookup {
            guard let hash = Cryptography.truncatedSHA1Base64EncodedWithoutPadding(e164) else {
                owsFailDebug("could not hash recipient id: \(e164)")
                continue
            }
            assert(e164sByHash[hash] == nil)
            e164sByHash[hash] = e164
        }
        return e164sByHash
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
                if IsNetworkConnectivityFailure(error) {
                    responseResolver.reject(error)

                } else if (task.response as? HTTPURLResponse)?.statusCode == 413 {
                    responseResolver.reject(ContactDiscoveryError(
                        kind: .rateLimit,
                        debugDescription: "Rate limited",
                        retryable: true,
                        retryAfterDate: error.httpRetryAfterDate
                    ))

                } else {
                    responseResolver.reject(ContactDiscoveryError(
                        kind: .genericServerError,
                        debugDescription: "Unexpected response code",
                        retryable: true,
                        retryAfterDate: error.httpRetryAfterDate
                    ))
                }
            }
        )
    }

    private func parse(response: Any?, e164sByHash: [String: String]) throws -> Set<String> {
        guard let responseDict = response as? [String: AnyObject],
              let contactDicts = responseDict["contacts"] as? [[String: AnyObject]] else {
            throw ContactDiscoveryError.assertionError(description: "Couldn't parse server response")
        }

        var registeredRecipientIds: Set<String> = Set()

        for contactDict in contactDicts {
            guard let hash = contactDict["token"] as? String, hash.count > 0 else {
                owsFailDebug("hash was unexpectedly nil")
                continue
            }

            guard let e164 = e164sByHash[hash], e164.count > 0 else {
                owsFailDebug("phoneNumber was unexpectedly nil")
                continue
            }

            guard e164sToLookup.contains(e164) else {
                owsFailDebug("unexpected phoneNumber")
                continue
            }

            registeredRecipientIds.insert(e164)
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
