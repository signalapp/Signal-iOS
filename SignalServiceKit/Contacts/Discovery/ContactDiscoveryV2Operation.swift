//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import GRDB
import Foundation
import LibSignalClient

// MARK: -

protocol ContactDiscoveryV2PersistentState {
    /// Load the token & e164s represented by the token.
    ///
    /// If the data isn't available, can't be read, or is corrupted, return
    /// `nil` to reset the token.
    func load() -> (token: Data, e164s: Set<E164>)?

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

protocol ContactDiscoveryTokenResult {
    var token: Data { get }
}

struct ContactDiscoveryLookupRequest {
    var newE164s: Set<E164>
    var prevE164s: Set<E164>
    var acisAndAccessKeys: [AciAndAccessKey]
    var token: Data?
}

protocol ContactDiscoveryConnection {
    associatedtype TokenResult: ContactDiscoveryTokenResult

    func performRequest(_ request: ContactDiscoveryLookupRequest, auth: Auth) async throws -> TokenResult
    func continueRequest(afterAckingToken tokenResult: TokenResult) async throws -> [ContactDiscoveryResult]
}

extension LibSignalClient.Net: ContactDiscoveryConnection {
    func performRequest(_ request: ContactDiscoveryLookupRequest, auth: Auth) async throws -> CdsiLookup {
        return try await self.cdsiLookup(auth: auth, request: CdsiLookupRequest(
            e164s: request.newE164s.map(\.stringValue),
            prevE164s: request.prevE164s.map(\.stringValue),
            acisAndAccessKeys: request.acisAndAccessKeys,
            token: request.token,
            returnAcisWithoutUaks: true
        ))
    }

    func continueRequest(afterAckingToken tokenResult: CdsiLookup) async throws -> [ContactDiscoveryResult] {
        let response = try await tokenResult.complete()
        Logger.info("CDSv2: Consumed \(response.debugPermitsUsed) tokens")
        return try response.entries.compactMap {entry in
            guard let pni = entry.pni else {
                return nil
            }
            guard let e164 = E164("+\(entry.e164)") else {
                throw ContactDiscoveryError.assertionError(description: "malformed e164")
            }
            return ContactDiscoveryResult(e164: e164, pni: pni, aci: entry.aci)
        }
    }
}

extension LibSignalClient.CdsiLookup: ContactDiscoveryTokenResult {}

// MARK: -

final class ContactDiscoveryV2Operation<ConnectionType: ContactDiscoveryConnection> {

    let e164sToLookup: Set<E164>

    /// If non-nil, requests will include prevE164s & a token, so we'll only
    /// consume quota for new E164s.
    ///
    /// If nil, requests will *always* consume quota, which risks exhausting all
    /// available quota. This should be used only for one-time requests
    /// initiated directly by the user. This ensures automated processes don't
    /// consume too much quota without the user's consent.
    let persistentState: ContactDiscoveryV2PersistentState?

    let udManager: Shims.UDManager

    private let connectionImpl: ConnectionType

    private let remoteAttestation: Shims.RemoteAttestation

    convenience init(
        e164sToLookup: Set<E164>,
        mode: ContactDiscoveryMode,
        udManager: any Shims.UDManager,
        connectionImpl: ConnectionType,
        remoteAttestation: any Shims.RemoteAttestation
    ) {
        self.init(
            e164sToLookup: e164sToLookup,
            persistentState: mode == .oneOffUserRequest ? nil : ContactDiscoveryV2PersistentStateImpl(),
            udManager: udManager,
            connectionImpl: connectionImpl,
            remoteAttestation: remoteAttestation
        )
    }

    init(
        e164sToLookup: Set<E164>,
        persistentState: (any ContactDiscoveryV2PersistentState)?,
        udManager: any Shims.UDManager,
        connectionImpl: ConnectionType,
        remoteAttestation: any Shims.RemoteAttestation
    ) {
        self.e164sToLookup = e164sToLookup
        self.persistentState = persistentState
        self.udManager = udManager
        self.connectionImpl = connectionImpl
        self.remoteAttestation = remoteAttestation
    }

    func perform(on queue: DispatchQueue) -> Promise<[ContactDiscoveryResult]> {
        return firstly(on: queue) {
            return self.remoteAttestation.authForCDSI()
        }.then(on: queue) { cdsiAuth in
            let request = try self.buildRequest()
            let auth = LibSignalClient.Auth(username: cdsiAuth.username, password: cdsiAuth.password)
            return Promise.wrapAsync {
                try await self.connectionImpl.performRequest(request, auth: auth)
            }.then(on: queue) { tokenResult in
                // We need to persist the token & new e164s before dealing with the result.
                // If we don't, a interrupted request could lead to a corrupted token.
                try self.handle(
                    token: tokenResult.token,
                    initialRequestHadToken: request.token != nil,
                    newE164s: request.newE164s
                )
                return Promise.wrapAsync {
                    try await self.connectionImpl.continueRequest(afterAckingToken: tokenResult)
                }
            }
        }.recover(on: queue) { error -> Promise<[ContactDiscoveryResult]> in
            let resolvedError = self.handle(error: error)
            Logger.warn("CDSv2: Failed with error: \(resolvedError)")
            throw resolvedError
        }
    }

    // MARK: - Request/Response

    private func buildRequest() throws -> ContactDiscoveryLookupRequest {
        let prevToken: Data?
        let prevE164s: Set<E164>
        let newE164s: Set<E164>

        if let priorFetchResult = persistentState?.load() {
            // We've got a valid token from a prior request. Use that.
            prevToken = priorFetchResult.token
            prevE164s = priorFetchResult.e164s
            newE164s = e164sToLookup.filter { !priorFetchResult.e164s.contains($0) }
        } else {
            // There's no token, or we're not using tokens, so mark all e164s as new.
            prevToken = nil
            prevE164s = Set()
            newE164s = e164sToLookup
        }

        let acisAndAccessKeys = udManager.fetchAllAciUakPairsWithSneakyTransaction().map { aci, uak in
            LibSignalClient.AciAndAccessKey(aci: aci, accessKey: uak.keyData)
        }

        return ContactDiscoveryLookupRequest(
            newE164s: newE164s,
            prevE164s: prevE164s,
            acisAndAccessKeys: acisAndAccessKeys,
            token: prevToken
        )
    }

    private func handle(
        token: Data,
        initialRequestHadToken: Bool,
        newE164s: Set<E164>
    ) throws {
        try persistentState?.save(
            newToken: token,
            clearE164s: !initialRequestHadToken,
            newE164s: newE164s
        )
    }

    // MARK: - Errors

    private func handle(error: Error) -> Error {
        switch error {
        case let libSignalError as LibSignalClient.SignalError:
            return handle(libSignalError: libSignalError)
        default:
            return error
        }
    }

    private func handle(libSignalError: LibSignalClient.SignalError) -> ContactDiscoveryError {
        switch libSignalError {
        case .rateLimitedError(retryAfter: let retryAfter, message: let message):
            let retryAfterDate = Date(timeIntervalSinceNow: retryAfter)
            Logger.warn("CDSv2: Rate limited until \(retryAfterDate): \(message)")
            return ContactDiscoveryError(
                kind: .rateLimit,
                debugDescription: "quota rate limit",
                retryable: true,
                retryAfterDate: retryAfterDate
            )
        case .cdsiInvalidToken:
            // If the token is wrong, throw away the current token. The next request
            // will get a new, valid token, at the cost of consuming additional quota.
            persistentState?.reset()
            return ContactDiscoveryError(
                kind: .genericClientError,
                debugDescription: "invalid token",
                retryable: true,
                retryAfterDate: nil
            )
        case .networkProtocolError(let message):
            return ContactDiscoveryError(
                kind: .genericClientError,
                debugDescription: "protocol error: \(message)",
                retryable: true,
                retryAfterDate: nil
            )
        case .webSocketError(let message):
            return ContactDiscoveryError(
                kind: .genericServerError,
                debugDescription: "web socket error: \(message)",
                retryable: true,
                retryAfterDate: nil
            )
        default:
            return ContactDiscoveryError(
                kind: .generic,
                debugDescription: "libsignal-net error: \(libSignalError)",
                retryable: false,
                retryAfterDate: nil
            )
        }
    }
}

// MARK: - Parsing the Response

struct ContactDiscoveryResult {
    var e164: E164

    /// If the lookup succeeds, we'll get back a PNI. If it doesn't succeed, the
    /// user with a particular e164 may not be registered, or they may have
    /// chosen to hide their phone number.
    var pni: Pni

    /// If we provide the correct ACI-UAK pair, we'll also get back the ACI
    /// associated with the e164/PNI.
    var aci: Aci?
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

private class ContactDiscoveryV2PersistentStateImpl: ContactDiscoveryV2PersistentState {
    private static let tokenStore = SDSKeyValueStore(collection: "CdsMetadata")
    private static let tokenKey = "token"

    func load() -> (token: Data, e164s: Set<E164>)? {
        SSKEnvironment.shared.databaseStorageRef.read { transaction in
            guard let existingToken = Self.tokenStore.getData(Self.tokenKey, transaction: transaction) else {
                return nil
            }
            let validatedE164s: Set<E164>
            do {
                let prevE164s = try CdsPreviousE164.fetchAll(transaction.unwrapGrdbRead.database).map {
                    guard let e164 = E164($0.e164) else {
                        throw ContactDiscoveryError.assertionError(description: "Found malformed E164 in database.")
                    }
                    return e164
                }
                validatedE164s = Set(prevE164s)
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
        try SSKEnvironment.shared.databaseStorageRef.write { transaction in
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
        SSKEnvironment.shared.databaseStorageRef.write { transaction in
            Self.tokenStore.removeValue(forKey: Self.tokenKey, transaction: transaction)
        }
    }
}

// MARK: - Shims

extension ContactDiscoveryV2Operation {
    enum Shims {
        typealias UDManager = _ContactDiscoveryV2Operation_UDManagerShim
        typealias RemoteAttestation = _ContactDiscoveryV2Operation_RemoteAttestationShim
    }

    enum Wrappers {
        typealias UDManager = _ContactDiscoveryV2Operation_UDManagerWrapper
        typealias RemoteAttestation = _ContactDiscoveryV2Operation_RemoteAttestationWrapper
    }
}

protocol _ContactDiscoveryV2Operation_UDManagerShim {
    func fetchAllAciUakPairsWithSneakyTransaction() -> [Aci: SMKUDAccessKey]
}

class _ContactDiscoveryV2Operation_UDManagerWrapper: _ContactDiscoveryV2Operation_UDManagerShim {
    private let db: any DB
    private let udManager: OWSUDManager

    init(db: any DB, udManager: OWSUDManager) {
        self.db = db
        self.udManager = udManager
    }

    func fetchAllAciUakPairsWithSneakyTransaction() -> [Aci: SMKUDAccessKey] {
        db.read { tx in udManager.fetchAllAciUakPairs(tx: SDSDB.shimOnlyBridge(tx)) }
    }
}

protocol _ContactDiscoveryV2Operation_RemoteAttestationShim {
    func authForCDSI() -> Promise<RemoteAttestation.Auth>
}

class _ContactDiscoveryV2Operation_RemoteAttestationWrapper: _ContactDiscoveryV2Operation_RemoteAttestationShim {
    init() {}

    func authForCDSI() -> Promise<RemoteAttestation.Auth> {
        return RemoteAttestation.authForCDSI()
    }
}
