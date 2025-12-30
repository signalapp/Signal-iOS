//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum BackupAuthCredentialType: String, Codable, CaseIterable, CodingKeyRepresentable {
    case media
    case messages
}

public enum BackupAuthCredentialFetchError: Error {
    /// The server told us we had no existing backup id and therefore no backup credentials.
    case noExistingBackupId
}

public protocol BackupAuthCredentialManager {
    /// Fetch `BackupServiceAuth` for use during registration.
    ///
    /// - Important
    /// This API does not take any Backup entitlement-related actions, and so
    /// should not be expected to return paid-tier auth regardless of the local
    /// `BackupPlan` or the user's remote eligibility for the paid tier.
    ///
    /// Relatedly, this API does not cache fetched credentials.
    func fetchBackupServiceAuthForRegistration(
        key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth: ChatServiceAuth,
    ) async throws -> BackupServiceAuth

    /// Fetch `BackupServiceAuth`. Callers may assume that tier of the returned
    /// auth will match the tier the user is eligible for.
    ///
    /// For example, paid-tier auth should be returned if the user is eligible
    /// for the paid tier via IAP or AppAttest.
    ///
    /// - parameter forceRefreshUnlessCachedPaidCredential: Forces a refresh if we have a cached
    /// credential that isn't ``BackupLevel.paid``. Default false. Set this to true if intending to check whether a
    /// paid credential is available.
    func fetchBackupServiceAuth(
        key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth: ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool,
    ) async throws -> BackupServiceAuth

    func fetchSVRBAuthCredential(
        key: MessageRootBackupKey,
        chatServiceAuth: ChatServiceAuth,
        forceRefresh: Bool,
    ) async throws -> LibSignalClient.Auth
}

// MARK: -

class BackupAuthCredentialManagerImpl: BackupAuthCredentialManager {

    private let authCredentialStore: AuthCredentialStore
    private let backupIdService: BackupIdService
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let backupTestFlightEntitlementManager: BackupTestFlightEntitlementManager
    private let dateProvider: DateProvider
    private let db: any DB
    private let networkManager: NetworkManager
    private let serialTaskQueue = ConcurrentTaskQueue(concurrentLimit: 1)

    init(
        authCredentialStore: AuthCredentialStore,
        backupIdService: BackupIdService,
        backupSubscriptionManager: BackupSubscriptionManager,
        backupTestFlightEntitlementManager: BackupTestFlightEntitlementManager,
        dateProvider: @escaping DateProvider,
        db: any DB,
        networkManager: NetworkManager,
    ) {
        self.authCredentialStore = authCredentialStore
        self.backupIdService = backupIdService
        self.backupSubscriptionManager = backupSubscriptionManager
        self.backupTestFlightEntitlementManager = backupTestFlightEntitlementManager
        self.dateProvider = dateProvider
        self.db = db
        self.networkManager = networkManager
    }

    // MARK: -

    func fetchBackupServiceAuthForRegistration(
        key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth auth: ChatServiceAuth,
    ) async throws -> BackupServiceAuth {
        return try await serialTaskQueue.run {
            try await _fetchBackupServiceAuthForRegistration(
                key: key,
                localAci: localAci,
                chatServiceAuth: auth,
            )
        }
    }

    private func _fetchBackupServiceAuthForRegistration(
        key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth auth: ChatServiceAuth,
    ) async throws -> BackupServiceAuth {
        try await waitForAuthCredentialDependency(.registerBackupId(localAci: localAci, auth: auth))

        let (_, backupServiceAuth) = try await fetchNewAuthCredentials(
            localAci: localAci,
            key: key,
            auth: auth,
        )

        return backupServiceAuth
    }

    // MARK: -

    func fetchBackupServiceAuth(
        key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth auth: ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool,
    ) async throws -> BackupServiceAuth {
        return try await serialTaskQueue.run {
            try await _fetchBackupServiceAuth(
                key: key,
                localAci: localAci,
                chatServiceAuth: auth,
                forceRefreshUnlessCachedPaidCredential: forceRefreshUnlessCachedPaidCredential,
            )
        }
    }

    private func _fetchBackupServiceAuth(
        key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth auth: ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool,
    ) async throws -> BackupServiceAuth {

        try await waitForAuthCredentialDependency(.registerBackupId(localAci: localAci, auth: auth))
        try await waitForAuthCredentialDependency(.renewBackupEntitlementForTestFlight)
        try await waitForAuthCredentialDependency(.redeemBackupSubscriptionViaIAP)

        if
            let cachedServiceAuth = readCachedServiceAuth(
                key: key,
                localAci: localAci,
                forceRefreshUnlessCachedPaidCredential: forceRefreshUnlessCachedPaidCredential,
            )
        {
            return cachedServiceAuth
        }

        let (
            authCredentialsOfKeyType,
            backupServiceAuth,
        ) = try await fetchNewAuthCredentials(localAci: localAci, key: key, auth: auth)

        await db.awaitableWrite { tx in
            cacheReceivedAuthCredentials(
                authCredentialsOfKeyType,
                credentialType: key.credentialType,
                tx: tx,
            )
        }

        return backupServiceAuth
    }

    // MARK: -

    func fetchSVRBAuthCredential(
        key: MessageRootBackupKey,
        chatServiceAuth auth: ChatServiceAuth,
        forceRefresh: Bool,
    ) async throws -> LibSignalClient.Auth {
        try await serialTaskQueue.run {
            try await _fetchSVRBAuthCredential(
                key: key,
                chatServiceAuth: auth,
                forceRefresh: forceRefresh,
            )
        }
    }

    private func _fetchSVRBAuthCredential(
        key: MessageRootBackupKey,
        chatServiceAuth auth: ChatServiceAuth,
        forceRefresh: Bool,
    ) async throws -> LibSignalClient.Auth {
        if
            !forceRefresh,
            let cachedCredential = db.read(block: authCredentialStore.svrBAuthCredential(tx:))
        {
            return cachedCredential
        }

        let backupServiceAuth = try await _fetchBackupServiceAuth(
            key: key,
            localAci: key.aci,
            chatServiceAuth: auth,
            forceRefreshUnlessCachedPaidCredential: false,
        )
        let response = try await networkManager.asyncRequest(
            OWSRequestFactory.fetchSVRBAuthCredential(auth: backupServiceAuth),
        )
        guard let bodyData = response.responseBodyData else {
            throw OWSAssertionError("Missing body data")
        }
        let receivedSVRBAuthCredential = try JSONDecoder().decode(ReceivedSVRBAuthCredentials.self, from: bodyData)
        let svrBAuth = LibSignalClient.Auth(
            username: receivedSVRBAuthCredential.username,
            password: receivedSVRBAuthCredential.password,
        )

        await db.awaitableWrite { tx in
            authCredentialStore.setSVRBAuthCredential(svrBAuth, tx: tx)
        }

        return svrBAuth
    }

    // MARK: -

    /// Represents an action that should happen before we try and fetch auth
    /// credentials, because they have side-effects that affect our ability to
    /// fetch said credentials.
    private enum BackupAuthCredentialDependency: Hashable {
        case registerBackupId(localAci: Aci, auth: ChatServiceAuth)
        case redeemBackupSubscriptionViaIAP
        case renewBackupEntitlementForTestFlight
    }

    private func waitForAuthCredentialDependency(
        _ dependency: BackupAuthCredentialDependency,
    ) async throws {
        let label: String
        let block: () async throws -> Void
        switch dependency {
        case .registerBackupId(let localAci, let auth):
            label = "registerBackupId"
            block = {
                // We can't fetch Backup auth credentials without having registered
                // our Backup ID. Normally this will have already happened, making
                // this call a no-op; however, it's possible it never succeeded or
                // we need to run it again.
                try await self.backupIdService.registerBackupIDIfNecessary(localAci: localAci, auth: auth)
            }
        case .redeemBackupSubscriptionViaIAP:
            label = "redeemBackupSubscription"
            block = {
                // Redeem our subscription if necessary, to ensure we have our
                // server-side Backup entitlement in place so we correctly fetch
                // paid-ter credentials.
                try await self.backupSubscriptionManager.redeemSubscriptionIfNecessary()
            }
        case .renewBackupEntitlementForTestFlight:
            label = "testFlightEntitlement"
            block = {
                // Same motivation as redeeming our subscription above, but for
                // TestFlight builds.
                try await self.backupTestFlightEntitlementManager.renewEntitlementIfNecessary()
            }
        }

        do {
            try await block()
        } catch {
            Logger.warn("Failed auth credential dependency step: \(label)! \(error)")
            throw error
        }
    }

    // MARK: -

    private func readCachedAuthCredential(
        key: BackupKeyMaterial,
    ) -> BackupAuthCredential? {
        return db.read { tx -> BackupAuthCredential? in
            let redemptionTime = dateProvider().epochSecondsSinceStartOfToday

            // Check there are more than 4 days of credentials remaining.
            // If not, return nil and trigger a credential fetch.
            guard
                let _ = self.authCredentialStore.backupAuthCredential(
                    for: key.credentialType,
                    redemptionTime: redemptionTime + 4 * .dayInSeconds,
                    tx: tx,
                )
            else {
                return nil
            }

            guard
                let authCredential = self.authCredentialStore.backupAuthCredential(
                    for: key.credentialType,
                    redemptionTime: redemptionTime,
                    tx: tx,
                )
            else {
                owsFailDebug("Unexpectedly missing auth credential for now, but had one for a future date!")
                return nil
            }

            return authCredential
        }
    }

    private let backupServiceAuthCache = LRUCache<Data, BackupServiceAuth>(maxSize: 4)
    private func readCachedServiceAuth(
        key: BackupKeyMaterial,
        localAci: Aci,
        forceRefreshUnlessCachedPaidCredential: Bool,
    ) -> BackupServiceAuth? {
        guard let cachedAuthCredential = readCachedAuthCredential(key: key) else {
            return nil
        }

        switch cachedAuthCredential.backupLevel {
        case .free where forceRefreshUnlessCachedPaidCredential:
            return nil
        case .free, .paid:
            break
        }

        // Use the credential as the service auth cache key, so if the
        // credential changes externally we skip the service auth cache.
        let cacheKey = cachedAuthCredential.serialize()

        if let cachedServiceAuth = backupServiceAuthCache[cacheKey] {
            return cachedServiceAuth
        } else {
            let backupServiceAuth = BackupServiceAuth(
                privateKey: key.deriveEcKey(aci: localAci),
                authCredential: cachedAuthCredential,
                type: key.credentialType,
            )
            backupServiceAuthCache[cacheKey] = backupServiceAuth
            return backupServiceAuth
        }
    }

    private func cacheReceivedAuthCredentials(
        _ receivedAuthCredentials: [ReceivedBackupAuthCredential],
        credentialType: BackupAuthCredentialType,
        tx: DBWriteTransaction,
    ) {
        if receivedAuthCredentials.isEmpty {
            owsFailDebug("Attempting to cache credentials, but none present!")
            return
        }

        authCredentialStore.removeAllBackupAuthCredentials(ofType: credentialType, tx: tx)

        for receivedCredential in receivedAuthCredentials {
            authCredentialStore.setBackupAuthCredential(
                receivedCredential.credential,
                for: credentialType,
                redemptionTime: receivedCredential.redemptionTime,
                tx: tx,
            )
        }
    }

    private func fetchNewAuthCredentials(
        localAci: Aci,
        key: BackupKeyMaterial,
        auth: ChatServiceAuth,
    ) async throws -> ([ReceivedBackupAuthCredential], first: BackupServiceAuth) {

        // Always fetch 7d worth of credentials at once.
        let startTimestampSeconds = dateProvider().epochSecondsSinceStartOfToday
        let endTimestampSeconds = startTimestampSeconds + 7 * .dayInSeconds
        let timestampRange = startTimestampSeconds...endTimestampSeconds

        let request = OWSRequestFactory.backupAuthenticationCredentialRequest(
            from: startTimestampSeconds,
            to: endTimestampSeconds,
            auth: auth,
        )

        let response: HTTPResponse
        do {
            response = try await networkManager.asyncRequest(request)
        } catch let error {
            if error.httpStatusCode == 404 {
                throw BackupAuthCredentialFetchError.noExistingBackupId
            } else {
                throw error
            }
        }
        guard let data = response.responseBodyData else {
            throw OWSAssertionError("Missing response body data")
        }

        let authCredentialRepsonse = try JSONDecoder().decode(BackupCredentialResponse.self, from: data)

        guard
            let authCredentialsOfKeyType = authCredentialRepsonse.credentials[key.credentialType],
            !authCredentialsOfKeyType.isEmpty
        else {
            throw OWSAssertionError("Missing auth credentials of type \(key.credentialType) in response!")
        }

        let backupServerPublicParams = try GenericServerPublicParams(contents: TSConstants.backupServerPublicParams)

        let receivedAuthCredentials = try authCredentialsOfKeyType.compactMap { credential -> ReceivedBackupAuthCredential? in
            guard timestampRange.contains(credential.redemptionTime) else {
                owsFailDebug("Dropping backup credential outside of requested time range! \(key.credentialType)")
                return nil
            }

            do {
                let backupRequestContext = BackupAuthCredentialRequestContext.create(
                    backupKey: key.serialize(),
                    aci: localAci.rawUUID,
                )

                let backupAuthResponse = try BackupAuthCredentialResponse(contents: credential.credential)
                let redemptionDate = Date(timeIntervalSince1970: TimeInterval(credential.redemptionTime))
                let receivedCredential = try backupRequestContext.receive(
                    backupAuthResponse,
                    timestamp: redemptionDate,
                    params: backupServerPublicParams,
                )

                return ReceivedBackupAuthCredential(
                    redemptionTime: credential.redemptionTime,
                    credential: receivedCredential,
                )
            } catch {
                Logger.warn("Error creating credential! \(error)")
                throw error
            }
        }

        guard let firstAuthCredential = receivedAuthCredentials.first?.credential else {
            throw OWSAssertionError("Unexpectedly missing auth credentials after parsing!")
        }

        return (
            receivedAuthCredentials,
            first: BackupServiceAuth(
                privateKey: key.deriveEcKey(aci: localAci),
                authCredential: firstAuthCredential,
                type: key.credentialType,
            ),
        )
    }

    // MARK: -

    private struct BackupCredentialResponse: Decodable {
        var credentials: [BackupAuthCredentialType: [AuthCredential]]

        struct AuthCredential: Decodable {
            var redemptionTime: UInt64
            var credential: Data
        }
    }

    private struct ReceivedBackupAuthCredential {
        var redemptionTime: UInt64
        var credential: BackupAuthCredential
    }

    private struct ReceivedSVRBAuthCredentials: Codable {
        let username: String
        let password: String
    }
}

// MARK: -

private extension UInt64 {
    static var dayInSeconds: UInt64 {
        UInt64(TimeInterval.day)
    }
}

private extension Date {
    /// The "start of today", i.e. midnight at the beginning of today, in epoch seconds.
    var epochSecondsSinceStartOfToday: UInt64 {
        let daysSince1970 = UInt64(timeIntervalSince1970) / .dayInSeconds
        return daysSince1970 * .dayInSeconds
    }
}
