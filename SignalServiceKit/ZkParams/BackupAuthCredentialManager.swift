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
        for key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth auth: ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool
    ) async throws -> BackupAuthCredential

    func fetchSvr🐝AuthCredential(
        key: MessageRootBackupKey,
        chatServiceAuth auth: ChatServiceAuth,
        forceRefresh: Bool,
    ) async throws -> LibSignalClient.Auth
}

public struct BackupAuthCredentialManagerImpl: BackupAuthCredentialManager {

    private enum Constants {
        static let numberOfDaysToFetchInSeconds: TimeInterval = 7 * .day
        static let numberOfDaysRemainingFutureCredentialsInSeconds: TimeInterval = 4 * .day
        static let keyValueStoreCollectionName = "MessageBackupAuthCredentialManager"
    }

    private let authCredentialStore: AuthCredentialStore
    private let backupIdService: BackupIdService
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let backupTestFlightEntitlementManager: BackupTestFlightEntitlementManager
    private let dateProvider: DateProvider
    private let db: any DB
    private let kvStore: KeyValueStore
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
        self.kvStore = KeyValueStore(collection: Constants.keyValueStoreCollectionName)
        self.networkManager = networkManager
    }

    public func fetchBackupCredential(
        for key: BackupKeyMaterial,
        localAci: Aci,
        chatServiceAuth auth: ChatServiceAuth,
        forceRefreshUnlessCachedPaidCredential: Bool
    ) async throws -> BackupAuthCredential {

        // Wait for steps whose side-effects affect Backup auth credentials.
        try await waitForAuthCredentialDependencies(localAci: localAci, auth: auth)

        let redemptionTime = self.dateProvider().startOfTodayUTCTimestamp()
        let futureRedemptionTime = redemptionTime + UInt64(Constants.numberOfDaysRemainingFutureCredentialsInSeconds)

        let authCredential = db.read { tx -> BackupAuthCredential? in
            // Check there are more than 4 days of credentials remaining.
            // If not, return nil and trigger a credential fetch.
            guard let _ = self.authCredentialStore.backupAuthCredential(
                for: key.credentialType,
                redemptionTime: futureRedemptionTime,
                tx: tx
            ) else {
                return nil
            }

            if let backupAuthCredential = self.authCredentialStore.backupAuthCredential(
                for: key.credentialType,
                redemptionTime: redemptionTime,
                tx: tx
            ) {
                switch backupAuthCredential.backupLevel {
                case .free where forceRefreshUnlessCachedPaidCredential:
                    // Force a refresh if the cached credential is free
                    // and we deliberately want to check for paid credentials.
                    return nil
                case .free, .paid:
                    return backupAuthCredential
                }
            } else {
                owsFailDebug("Error retrieving cached auth credential")
            }

            return nil
        }

        if let authCredential {
            return authCredential
        }

        let authCredentials = try await fetchNewAuthCredentials(localAci: localAci, for: key, auth: auth)

        await db.awaitableWrite { tx in
            // Fetch both credential types if either is needed.
            BackupAuthCredentialType.allCases.forEach { credentialType in
                guard let receivedCredentials = authCredentials[credentialType] else {
                    if credentialType == credentialType {
                        // If the requested media type fails, make some noise about it.
                        owsFailDebug("Failed to retrieve credentials for \(credentialType.rawValue)")
                    }
                    return
                }
                self.authCredentialStore.removeAllBackupAuthCredentials(ofType: credentialType, tx: tx)
                for receivedCredential in receivedCredentials {
                    self.authCredentialStore.setBackupAuthCredential(
                        receivedCredential.credential,
                        for: credentialType,
                        redemptionTime: receivedCredential.redemptionTime,
                        tx: tx
                    )
                }
            }
        }

        guard let authCredential = authCredentials[key.credentialType]?.first?.credential else {
            throw OWSAssertionError("The server didn't give us any auth credentials.")
        }

        return authCredential
    }

    public func fetchSvr🐝AuthCredential(
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
            for: key,
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

    /// Aggregates steps that should happen before we try and fetch auth
    /// credentials, because they have side-effects that affect our ability to
    /// fetch said credentials.
    private func waitForAuthCredentialDependencies(
        localAci: Aci,
        auth: ChatServiceAuth,
    ) async throws {
        var dependencyStepFailed = false

        do {
            // We can't fetch Backup auth credentials without having registered
            // our Backup ID. Normally this will have already happened, making
            // this call a no-op; however, it's possible it never succeeded or
            // we need to run it again.
            try await backupIdService.registerBackupIDIfNecessary(localAci: localAci, auth: auth)
        } catch {
            Logger.warn("Failed to register Backup-ID! \(error)")
            dependencyStepFailed = true
        }

        do {
            // Redeem our subscription if necessary, to ensure we have our
            // server-side Backup entitlement in place so we correctly fetch
            // paid-ter credentials.
            try await backupSubscriptionManager.redeemSubscriptionIfNecessary()
        } catch {
            Logger.warn("Failed to redeem IAP Backup subscription! \(error)")
            dependencyStepFailed = true
        }

        do {
            // Same motivation as redeeming our subscription above, but for
            // TestFlight builds.
            try await backupTestFlightEntitlementManager.renewEntitlementIfNecessary()
        } catch {
            Logger.warn("Failed to renew entitlement for TestFlight! \(error)")
            dependencyStepFailed = true
        }

        if dependencyStepFailed {
            struct AuthCredentialDependencyError: Error {}
            throw AuthCredentialDependencyError()
        }
    }

    private func fetchNewAuthCredentials(
        localAci: Aci,
        for key: BackupKeyMaterial,
        auth: ChatServiceAuth
    ) async throws -> [BackupAuthCredentialType: [ReceivedBackupAuthCredentials]] {

        let startTimestamp = self.dateProvider().startOfTodayUTCTimestamp()
        let endTimestamp = startTimestamp + UInt64(Constants.numberOfDaysToFetchInSeconds)
        let timestampRange = startTimestamp...endTimestamp

        let request = OWSRequestFactory.backupAuthenticationCredentialRequest(
            from: startTimestamp,
            to: endTimestamp,
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

        let backupServerPublicParams = try GenericServerPublicParams(contents: TSConstants.backupServerPublicParams)
        return try authCredentialRepsonse.credentials.reduce(into: [BackupAuthCredentialType: [ReceivedBackupAuthCredentials]]()) { result, element in
            let type = element.key
            result[type] = try element.value.compactMap {
                guard timestampRange.contains($0.redemptionTime) else {
                    owsFailDebug("Dropping \(type.rawValue) backup credential we didn't ask for")
                    return nil
                }
                do {
                    let redemptionDate = Date(timeIntervalSince1970: TimeInterval($0.redemptionTime))
                    let backupRequestContext = BackupAuthCredentialRequestContext.create(
                        backupKey: key.backupKey.serialize(),
                        aci: localAci.rawUUID
                    )
                    let backupAuthResponse = try BackupAuthCredentialResponse(contents: $0.credential)
                    let credential = try backupRequestContext.receive(
                        backupAuthResponse,
                        timestamp: redemptionDate,
                        params: backupServerPublicParams
                    )
                    return ReceivedBackupAuthCredentials(redemptionTime: $0.redemptionTime, credential: credential)
                } catch SignalError.verificationFailed where type != key.credentialType {
                    // If the message backup key is missing and the caller is asking for
                    // media credentials, ignore the error
                    return nil
                } catch SignalError.verificationFailed where type != key.credentialType {
                    // Similarly, If the media backup key is missing and the caller is
                    // asking for message credentials, ignore the error.  This will happen,
                    // for example, during registration when restoring from backup - the
                    // user will have entered a message backup key, but the media root backup
                    // key won't be available until after downloading and reading the backup info.
                    return nil
                } catch {
                    owsFailDebug("Error creating credential! \(error)")
                    throw error
                }
            }
        }
    }

    private struct BackupCredentialResponse: Decodable {
        var credentials: [BackupAuthCredentialType: [AuthCredential]]

        struct AuthCredential: Decodable {
            var redemptionTime: UInt64
            var credential: Data
        }
    }

    private struct ReceivedBackupAuthCredentials {
        var redemptionTime: UInt64
        var credential: BackupAuthCredential
    }

    // swiftlint:disable:next type_name
    public struct ReceivedSVR🐝AuthCredentials: Codable {
        let username: String
        let password: String
    }
}

fileprivate extension Date {
    /// The "start of today", i.e. midnight at the beginning of today, in epoch seconds.
    func startOfTodayUTCTimestamp() -> UInt64 {
        return UInt64(self.timeIntervalSince1970 / .day) * UInt64(TimeInterval.day)
    }
}
