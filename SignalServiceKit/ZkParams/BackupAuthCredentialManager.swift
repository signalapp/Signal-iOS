//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum BackupAuthCredentialType: String, Codable, CaseIterable, CodingKeyRepresentable  {
    case media
    case messages
}

public enum BackupAuthCredentialFetchError: Error {
    /// The server told us we had no existing backup id and therefore no backup credentials.
    case noExistingBackupId
}

public protocol BackupAuthCredentialManager {

    /// - parameter forceRefreshUnlessCachedPaidCredential: Forces a refresh if we have a cached
    /// credential that isn't ``BackupLevel.paid``. Default false. Set this to true if intending to check whether a
    /// paid credential is available.
    func fetchBackupCredential(
        key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth: ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool
    ) async throws -> BackupAuthCredential

    func fetchSvr🐝AuthCredential(
        key: MessageRootBackupKey,
        chatServiceAuth: ChatServiceAuth,
        forceRefresh: Bool,
    ) async throws -> LibSignalClient.Auth
}

struct BackupAuthCredentialManagerImpl: BackupAuthCredentialManager {

    private let authCredentialStore: AuthCredentialStore
    private let backupIdService: BackupIdService
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let backupTestFlightEntitlementManager: BackupTestFlightEntitlementManager
    private let dateProvider: DateProvider
    private let db: any DB
    private let networkManager: NetworkManager

    init(
        authCredentialStore: AuthCredentialStore,
        backupIdService: BackupIdService,
        backupSubscriptionManager: BackupSubscriptionManager,
        backupTestFlightEntitlementManager: BackupTestFlightEntitlementManager,
        dateProvider: @escaping DateProvider,
        db: any DB,
        networkManager: NetworkManager
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

    func fetchBackupCredential(
        key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth auth: ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool
    ) async throws -> BackupAuthCredential {

        try await waitForAuthCredentialDependency(.registerBackupId(localAci: localAci, auth: auth))
        try await waitForAuthCredentialDependency(.renewBackupEntitlementForTestFlight)
        try await waitForAuthCredentialDependency(.redeemBackupSubscriptionViaIAP)

        if let cachedAuthCredential = readCachedAuthCredential(
            key: key,
            requirePaidCredential: forceRefreshUnlessCachedPaidCredential,
        ) {
            return cachedAuthCredential
        }

        let authCredentialsOfKeyType = try await fetchNewAuthCredentials(localAci: localAci, key: key, auth: auth)

        await db.awaitableWrite { tx in
            cacheReceivedAuthCredentials(
                authCredentialsOfKeyType,
                credentialType: key.credentialType,
                tx: tx,
            )
        }

        guard let authCredential = authCredentialsOfKeyType.first?.credential else {
            throw OWSAssertionError("Fetched credentials were empty!")
        }

        return authCredential
    }

    func fetchSvr🐝AuthCredential(
        key: MessageRootBackupKey,
        chatServiceAuth auth: ChatServiceAuth,
        forceRefresh: Bool,
    ) async throws -> LibSignalClient.Auth {
        if
            !forceRefresh,
            let cachedCredential = db.read(block: authCredentialStore.svr🐝AuthCredential(tx:))
        {
            return cachedCredential
        }

        let backupAuthCredential = try await self.fetchBackupCredential(
            key: key,
            localAci: key.aci,
            chatServiceAuth: auth,
            forceRefreshUnlessCachedPaidCredential: false
        )
        let privateKey = key.deriveEcKey(aci: key.aci)
        let backupAuth = try BackupServiceAuth(
            privateKey: privateKey,
            authCredential: backupAuthCredential,
            type: key.credentialType
        )
        let response = try await networkManager.asyncRequest(
            OWSRequestFactory.fetchSVR🐝AuthCredential(auth: backupAuth),
            canUseWebSocket: FeatureFlags.postRegWebSocket
        )
        guard let bodyData = response.responseBodyData else {
            throw OWSAssertionError("Missing body data")
        }
        let svr🐝Auth = try JSONDecoder().decode(ReceivedSVR🐝AuthCredentials.self, from: bodyData)
        return LibSignalClient.Auth(
            username: svr🐝Auth.username,
            password: svr🐝Auth.password
        )
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
                try await backupIdService.registerBackupIDIfNecessary(localAci: localAci, auth: auth)
            }
        case .redeemBackupSubscriptionViaIAP:
            label = "redeemBackupSubscription"
            block = {
                // Redeem our subscription if necessary, to ensure we have our
                // server-side Backup entitlement in place so we correctly fetch
                // paid-ter credentials.
                try await backupSubscriptionManager.redeemSubscriptionIfNecessary()
            }
        case .renewBackupEntitlementForTestFlight:
            label = "testFlightEntitlement"
            block = {
                // Same motivation as redeeming our subscription above, but for
                // TestFlight builds.
                try await backupTestFlightEntitlementManager.renewEntitlementIfNecessary()
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
        requirePaidCredential: Bool,
    ) -> BackupAuthCredential? {
        return db.read { tx -> BackupAuthCredential? in
            let redemptionTime = dateProvider().epochSecondsSinceStartOfToday

            // Check there are more than 4 days of credentials remaining.
            // If not, return nil and trigger a credential fetch.
            guard let _ = self.authCredentialStore.backupAuthCredential(
                for: key.credentialType,
                redemptionTime: redemptionTime + 4 * .dayInSeconds,
                tx: tx
            ) else {
                return nil
            }

            if let authCredential = self.authCredentialStore.backupAuthCredential(
                for: key.credentialType,
                redemptionTime: redemptionTime,
                tx: tx
            ) {
                switch authCredential.backupLevel {
                case .free where requirePaidCredential:
                    break
                case .free, .paid:
                    return authCredential
                }
            } else {
                owsFailDebug("Unexpectedly missing auth credential for now, but had one for a future date!")
            }

            return nil
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
        auth: ChatServiceAuth
    ) async throws -> [ReceivedBackupAuthCredential] {

        // Always fetch 7d worth of credentials at once.
        let startTimestampSeconds = dateProvider().epochSecondsSinceStartOfToday
        let endTimestampSeconds = startTimestampSeconds + 7 * .dayInSeconds
        let timestampRange = startTimestampSeconds...endTimestampSeconds

        let request = OWSRequestFactory.backupAuthenticationCredentialRequest(
            from: startTimestampSeconds,
            to: endTimestampSeconds,
            auth: auth
        )

        let response: HTTPResponse
        do {
            response = try await networkManager.asyncRequest(request, canUseWebSocket: FeatureFlags.postRegWebSocket)
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

        return try authCredentialsOfKeyType.compactMap { credential -> ReceivedBackupAuthCredential? in
            guard timestampRange.contains(credential.redemptionTime) else {
                owsFailDebug("Dropping backup credential outside of requested time range! \(key.credentialType)")
                return nil
            }

            do {
                let backupRequestContext = BackupAuthCredentialRequestContext.create(
                    backupKey: key.serialize(),
                    aci: localAci.rawUUID
                )

                let backupAuthResponse = try BackupAuthCredentialResponse(contents: credential.credential)
                let redemptionDate = Date(timeIntervalSince1970: TimeInterval(credential.redemptionTime))
                let receivedCredential = try backupRequestContext.receive(
                    backupAuthResponse,
                    timestamp: redemptionDate,
                    params: backupServerPublicParams
                )

                return ReceivedBackupAuthCredential(
                    redemptionTime: credential.redemptionTime,
                    credential: receivedCredential
                )
            } catch {
                owsFailDebug("Error creating credential! \(error)")
                throw error
            }
        }
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

    // swiftlint:disable:next type_name
    private struct ReceivedSVR🐝AuthCredentials: Codable {
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
