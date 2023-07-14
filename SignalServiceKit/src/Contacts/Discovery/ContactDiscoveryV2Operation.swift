//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import Foundation

// MARK: -

private enum Constant {
    static let defaultRetryAfter: TimeInterval = 60
}

// MARK: -

/// Runs a CDSv1-compatible operation against the CDSv2 backend.
final class ContactDiscoveryV2CompatibilityOperation: ContactDiscoveryOperation {
    let e164sToLookup: Set<E164>
    let mode: ContactDiscoveryMode
    let websocketFactory: WebSocketFactory

    init(e164sToLookup: Set<E164>, mode: ContactDiscoveryMode, websocketFactory: WebSocketFactory) {
        self.e164sToLookup = e164sToLookup
        self.mode = mode
        self.websocketFactory = websocketFactory
    }

    func perform(on queue: DispatchQueue) -> Promise<Set<DiscoveredContactInfo>> {
        let operation = ContactDiscoveryV2Operation(
            e164sToLookup: e164sToLookup,
            mode: mode,
            compatibilityMode: .fetchAllACIs,
            websocketFactory: websocketFactory
        )
        return firstly {
            operation.perform(on: queue)
        }.map(on: queue) { discoveryResults in
            var results = Set<DiscoveredContactInfo>()
            for discoveryResult in discoveryResults {
                guard self.e164sToLookup.contains(discoveryResult.e164) else {
                    // In v2, we get back results for previous lookups as well. The API
                    // contract expects only those that were explicitly requested, so filter to
                    // include only those.
                    continue
                }
                guard let aci = discoveryResult.aci else {
                    owsFailDebug("CDSv2: All discovery results should have an ACI")
                    continue
                }
                results.insert(DiscoveredContactInfo(e164: discoveryResult.e164, uuid: aci))
            }
            return results
        }
    }
}

// MARK: -

protocol ContactDiscoveryV2PersistentState {
    /// Load the token & e164s represented by the token.
    ///
    /// If the data isn't available, can't be read, or is corrupted, return
    /// `nil` to reset the token.
    func load() -> (token: Data, e164s: ContactDiscoveryE164Collection<Set<E164>>)?

    /// Save the token response from the server.
    /// - Parameters:
    ///   - newToken: The new token returned by the server.
    ///   - clearE164s:
    ///       If true, all existing e164s will be deleted before `newE164s` are
    ///       written. This is most useful when saving the initial token or
    ///       resetting the token after it's been corrupted.
    ///   - newE164s: The e164s that should be saved.
    func save(newToken: Data, clearE164s: Bool, newE164s: Set<E164>) throws

    /// Reset the token.
    ///
    /// The next call to `load()` will return `nil`.
    func reset()
}

// MARK: -

final class ContactDiscoveryV2Operation {

    let e164sToLookup: Set<E164>

    let compatibilityMode: CompatibilityMode
    enum CompatibilityMode {
        /// Send a request that returns a CDSv1-equivalent response.
        case fetchAllACIs

        /// Send a PNP-aware request. Requires full support for PNI-only contacts.
        case fetchKnownACIs
    }

    /// If non-nil, requests will include prevE164s & a token, so we'll only
    /// consume quota for new E164s.
    ///
    /// If nil, requests will *always* consume quota, which risks exhausting all
    /// available quota. This should be used only for one-time requests
    /// initiated directly by the user. This ensures automated processes don't
    /// consume too much quota without the user's consent.
    let persistentState: ContactDiscoveryV2PersistentState?

    let connectionFactory: SgxWebsocketConnectionFactory

    init(
        e164sToLookup: Set<E164>,
        compatibilityMode: CompatibilityMode,
        persistentState: ContactDiscoveryV2PersistentState?,
        connectionFactory: SgxWebsocketConnectionFactory
    ) {
        self.e164sToLookup = e164sToLookup
        self.compatibilityMode = compatibilityMode
        self.persistentState = persistentState
        self.connectionFactory = connectionFactory
    }

    convenience init(
        e164sToLookup: Set<E164>,
        mode: ContactDiscoveryMode,
        compatibilityMode: CompatibilityMode,
        websocketFactory: WebSocketFactory
    ) {
        let persistentState: ContactDiscoveryV2PersistentState?
        if mode == .oneOffUserRequest {
            persistentState = nil
        } else {
            persistentState = ContactDiscoveryV2PersistentStateImpl()
        }
        self.init(
            e164sToLookup: e164sToLookup,
            compatibilityMode: compatibilityMode,
            persistentState: persistentState,
            connectionFactory: SgxWebsocketConnectionFactoryImpl(websocketFactory: websocketFactory)
        )
    }

    func perform(on queue: DispatchQueue) -> Promise<[DiscoveryResult]> {
        firstly(on: queue) {
            return self.connectionFactory.connectAndPerformHandshake(
                configurator: ContactDiscoveryV2WebsocketConfigurator(),
                on: queue
            )
        }.then(on: queue) { connection -> Promise<[DiscoveryResult]> in
            let initialRequest = self.buildRequest()
            return firstly { () -> Promise<CDSI_ClientResponse> in
                connection.sendRequestAndReadResponse(initialRequest.request)
            }.map(on: queue) { tokenResponse in
                // We need to persist the token & new e164s before dealing with the result.
                // If we don't, a interrupted request could lead to a corrupted token.
                try self.handle(tokenResponse: tokenResponse, initialRequest: initialRequest)
            }.then(on: queue) {
                connection.sendRequestAndReadAllResponses(self.buildTokenAck())
            }.map(on: queue) { responses in
                try self.handle(responses: responses)
            }.recover(on: queue) { error -> Promise<[DiscoveryResult]> in
                // We disconnect if there's an error. This might be a connection error, but
                // it also might be a locally-thrown error, and in that case, we need to
                // disconnect from the server. (The server disconnects in the happy path.)
                connection.disconnect(code: nil)
                throw error
            }
        }.recover(on: queue) { error -> Promise<[DiscoveryResult]> in
            let resolvedError = self.handle(error: error)
            Logger.warn("CDSv2: Failed with error: \(resolvedError)")
            throw resolvedError
        }
    }

    // MARK: - Request/Response

    private struct InitialRequest {
        /// Whether or not this request includes a token. If it doesn't, we clear
        /// our local state when saving the new token.
        var hasToken: Bool

        /// The set of e164s that needs to be persisted alongside the token we
        /// receive from the server. This may be empty, and it may contain only a
        /// few e164s in the common case.
        var newE164s: Set<E164>

        /// The proto to send to the server as part of the initial request.
        var request: CDSI_ClientRequest
    }

    private func buildRequest() -> InitialRequest {
        let prevToken: Data
        let prevE164s: Data
        let newE164s: Set<E164>

        if let priorFetchResult = persistentState?.load() {
            // We've got a valid token from a prior request. Use that.
            prevToken = priorFetchResult.token
            prevE164s = priorFetchResult.e164s.encodedValues
            newE164s = e164sToLookup.filter { !priorFetchResult.e164s.values.contains($0) }
        } else {
            // There's no token, or we're not using tokens, so mark all e164s as new.
            prevToken = Data()
            prevE164s = Data()
            newE164s = e164sToLookup
        }

        var request = CDSI_ClientRequest()
        request.token = prevToken
        request.prevE164S = prevE164s
        request.newE164S = ContactDiscoveryE164Collection(newE164s).encodedValues

        switch compatibilityMode {
        case .fetchAllACIs:
            request.returnAcisWithoutUaks = true
        case .fetchKnownACIs:
            request.returnAcisWithoutUaks = false
            // TODO: Fetch all ACI-UAK pairs.
        }

        return InitialRequest(
            hasToken: !prevToken.isEmpty,
            newE164s: newE164s,
            request: request
        )
    }

    private func handle(
        tokenResponse: CDSI_ClientResponse,
        initialRequest: InitialRequest
    ) throws {
        // If the server provides an empty token, we should reject it.
        guard !tokenResponse.token.isEmpty else {
            throw ContactDiscoveryError(
                kind: .genericServerError,
                debugDescription: "token response missing token",
                retryable: false,
                retryAfterDate: nil
            )
        }
        try persistentState?.save(
            newToken: tokenResponse.token,
            clearE164s: !initialRequest.hasToken,
            newE164s: initialRequest.newE164s
        )
    }

    private func buildTokenAck() -> CDSI_ClientRequest {
        var request = CDSI_ClientRequest()
        request.tokenAck = true
        return request
    }

    private func handle(responses: [CDSI_ClientResponse]) throws -> [DiscoveryResult] {
        var result = [DiscoveryResult]()
        for response in responses {
            Logger.info("CDSv2: Consumed \(response.debugPermitsUsed) tokens")
            result.append(contentsOf: try Self.decodePniAciResult(response.e164PniAciTriples))
        }
        return result
    }

    // MARK: - Errors

    // Close errors as described in the "CDSv2 Client Protocol" doc.
    private enum CloseError: Int {
        case rateLimitExceeded = 4008
        case invalidRateLimitToken = 4101
    }

    private func handle(error: Error) -> Error {
        guard let socketError = error as? WebSocketError else {
            return error
        }
        return handle(socketError: socketError)
    }

    private func handle(socketError: WebSocketError) -> ContactDiscoveryError {
        switch socketError {
        case .closeError(statusCode: CloseError.invalidRateLimitToken.rawValue, closeReason: _):
            // If the token is wrong, throw away the current token. The next request
            // will get a new, valid token, at the cost of consuming additional quota.
            persistentState?.reset()
            return ContactDiscoveryError(
                kind: .genericClientError,
                debugDescription: "invalid token",
                retryable: true,
                retryAfterDate: nil
            )

        case .closeError(statusCode: CloseError.rateLimitExceeded.rawValue, closeReason: let closeReason):
            let retryAfterDate = parseRetryAfter(closeReason: closeReason)
            Logger.warn("CDSv2: Rate limited until \(retryAfterDate)")
            return ContactDiscoveryError(
                kind: .rateLimit,
                debugDescription: "quota rate limit",
                retryable: true,
                retryAfterDate: retryAfterDate
            )

        case .closeError:
            return ContactDiscoveryError(
                kind: .genericServerError,
                debugDescription: "web socket error",
                retryable: false,
                retryAfterDate: nil
            )

        case .httpError(statusCode: 429, retryAfter: let retryAfter):
            // We're being rate-limited before opening the socket. This can happen if
            // we connect too frequently, regardless of how much quota is available.
            return ContactDiscoveryError(
                kind: .rateLimit,
                debugDescription: "http rate limit",
                retryable: true,
                retryAfterDate: retryAfter
            )

        case .httpError(statusCode: let statusCode, retryAfter: let retryAfter) where (500..<600).contains(statusCode):
            return ContactDiscoveryError(
                kind: .genericServerError,
                debugDescription: "http 5xx error",
                retryable: true,
                retryAfterDate: retryAfter
            )

        case .httpError:
            return ContactDiscoveryError(
                kind: .generic,
                debugDescription: "http error",
                retryable: false,
                retryAfterDate: nil
            )
        }
    }

    private struct QuotaExceededCloseReason: Decodable {
        var retryAfter: TimeInterval

        enum CodingKeys: String, CodingKey {
            case retryAfter = "retry_after"
        }
    }

    private func parseRetryAfter(closeReason: Data?) -> Date {
        if let closeReason {
            if let closeReasonObj = try? JSONDecoder().decode(QuotaExceededCloseReason.self, from: closeReason) {
                return Date(timeIntervalSinceNow: closeReasonObj.retryAfter)
            }
        }
        return Date(timeIntervalSinceNow: Constant.defaultRetryAfter)
    }

    // MARK: - Parsing the Response

    struct DiscoveryResult {
        var e164: E164

        /// If the lookup succeeds, we'll get back a PNI. If it doesn't succeed, the
        /// user with a particular e164 may not be registered, or they may have
        /// chosen to hide their phone number.
        var pni: UUID

        /// If we provide the correct ACI-UAK pair, we'll also get back the ACI
        /// associated with the e164/PNI.
        var aci: UUID?
    }

    static func decodePniAciResult(_ data: Data) throws -> [DiscoveryResult] {
        var result = [DiscoveryResult]()

        var remainingData = data
        while !remainingData.isEmpty {
            if let discoveryResult = try decodePniAciElement(&remainingData) {
                result.append(discoveryResult)
            }
        }

        return result
    }

    static func decodePniAciElement(_ remainingData: inout Data) throws -> DiscoveryResult? {
        guard let (rawE164, rawE164Count) = UInt64.from(bigEndianData: remainingData) else {
            throw ContactDiscoveryError.assertionError(description: "malformed e164/aci/pni triples")
        }
        remainingData = remainingData.dropFirst(rawE164Count)

        guard let (pni, pniCount) = UUID.from(data: remainingData) else {
            throw ContactDiscoveryError.assertionError(description: "malformed e164/aci/pni triples")
        }
        remainingData = remainingData.dropFirst(pniCount)

        guard let (aci, aciCount) = UUID.from(data: remainingData) else {
            throw ContactDiscoveryError.assertionError(description: "malformed e164/aci/pni triples")
        }
        remainingData = remainingData.dropFirst(aciCount)

        guard pni != UUID.allZeros else {
            return nil
        }
        guard let e164 = E164("+\(rawE164)") else {
            throw ContactDiscoveryError.assertionError(description: "malformed e164")
        }
        return DiscoveryResult(
            e164: e164,
            pni: pni,
            aci: aci == UUID.allZeros ? nil : aci
        )
    }
}

// MARK: - Persistent State

/// A CdsPreviousE164 represents an e164 that we've previously fetched.
struct CdsPreviousE164: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName: String = "CdsPreviousE164"

    var id: Int64?
    var e164: String

    mutating func didInsert(with rowID: Int64, for column: String?) {
        self.id = rowID
    }
}

private class ContactDiscoveryV2PersistentStateImpl: ContactDiscoveryV2PersistentState, Dependencies {
    private static let tokenStore = SDSKeyValueStore(collection: "CdsMetadata")
    private static let tokenKey = "token"

    func load() -> (token: Data, e164s: ContactDiscoveryE164Collection<Set<E164>>)? {
        databaseStorage.read { transaction in
            guard let existingToken = Self.tokenStore.getData(Self.tokenKey, transaction: transaction) else {
                return nil
            }
            let validatedE164s: ContactDiscoveryE164Collection<Set<E164>>
            do {
                let prevE164s = try CdsPreviousE164.fetchAll(transaction.unwrapGrdbRead.database).map {
                    guard let e164 = E164($0.e164) else {
                        throw ContactDiscoveryError.assertionError(description: "Found malformed E164 in database.")
                    }
                    return e164
                }
                validatedE164s = ContactDiscoveryE164Collection(Set(prevE164s))
            } catch {
                // If we find an invalid local value, it's very likely that our local
                // e164/token state is inconsistent. To recover from this scenario, we
                // ignore the local state and report all the e164s as new.
                Logger.warn("CDSv2: Found malformed CdsPreviousE164 value; resetting token")
                return nil
            }
            return (token: existingToken, e164s: validatedE164s)
        }
    }

    func save(newToken: Data, clearE164s: Bool, newE164s: Set<E164>) throws {
        try databaseStorage.write { transaction in
            let database = transaction.unwrapGrdbWrite.database

            Self.tokenStore.setData(newToken, key: Self.tokenKey, transaction: transaction)

            // If we didn't use an old token, clear any local e164s. On the initial
            // request, this should be a no-op. If we're trying to recover from a
            // malformed token/prev e164 value, there'll be values to clear.
            if clearE164s {
                try CdsPreviousE164.deleteAll(database)
                Logger.info("CDSv2: Clearing all CdsE164s")
            }

            for newE164 in newE164s {
                try CdsPreviousE164(e164: newE164.stringValue).insert(database)
            }

            Logger.info("CDSv2: Saved CDS token and \(newE164s.count) new CdsE164s")
        }
    }

    func reset() {
        Logger.warn("CDSv2: Resetting token")
        databaseStorage.write { transaction in
            Self.tokenStore.removeValue(forKey: Self.tokenKey, transaction: transaction)
        }
    }
}

extension UUID {
    static let allZeros: Self = {
        Self(data: Data(count: 16))!
    }()
}
