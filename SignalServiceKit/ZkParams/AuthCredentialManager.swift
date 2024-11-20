//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public protocol AuthCredentialManager {
    func fetchGroupAuthCredential(localIdentifiers: LocalIdentifiers) async throws -> AuthCredentialWithPni
    func fetchCallLinkAuthCredential(localIdentifiers: LocalIdentifiers) async throws -> CallLinkAuthCredential
}

#if TESTABLE_BUILD

class MockAuthCrededentialManager: AuthCredentialManager {
    func fetchGroupAuthCredential(localIdentifiers: LocalIdentifiers) async throws -> AuthCredentialWithPni {
        throw OWSGenericError("Not implemented.")
    }
    func fetchCallLinkAuthCredential(localIdentifiers: LocalIdentifiers) async throws -> CallLinkAuthCredential {
        throw OWSGenericError("Not implemented.")
    }
}

#endif

class AuthCredentialManagerImpl: AuthCredentialManager {
    private let authCredentialStore: AuthCredentialStore
    private let callLinkPublicParams: GenericServerPublicParams
    private let dateProvider: DateProvider
    private let db: any DB

    init(
        authCredentialStore: AuthCredentialStore,
        callLinkPublicParams: GenericServerPublicParams,
        dateProvider: @escaping DateProvider,
        db: any DB
    ) {
        self.authCredentialStore = authCredentialStore
        self.callLinkPublicParams = callLinkPublicParams
        self.dateProvider = dateProvider
        self.db = db
    }

    private enum Constants {
        static let numberOfDaysToFetch = 7 as UInt64
    }

    // MARK: -

    func fetchGroupAuthCredential(localIdentifiers: LocalIdentifiers) async throws -> AuthCredentialWithPni {
        let redemptionTime = self.startOfTodayTimestamp()
        return try await fetchAuthCredential(
            for: redemptionTime,
            localIdentifiers: localIdentifiers,
            fetchCachedAuthCredential: self.authCredentialStore.groupAuthCredential(for:tx:),
            authCredentialsKeyPath: \.groupAuthCredentials
        )
    }

    func fetchCallLinkAuthCredential(localIdentifiers: LocalIdentifiers) async throws -> CallLinkAuthCredential {
        let redemptionTime = self.startOfTodayTimestamp()
        let authCredential = try await fetchAuthCredential(
            for: redemptionTime,
            localIdentifiers: localIdentifiers,
            fetchCachedAuthCredential: self.authCredentialStore.callLinkAuthCredential(for:tx:),
            authCredentialsKeyPath: \.callLinkAuthCredentials
        )
        return CallLinkAuthCredential(
            localAci: localIdentifiers.aci,
            redemptionTime: redemptionTime,
            serverParams: self.callLinkPublicParams,
            authCredential: authCredential
        )
    }

    private func fetchAuthCredential<T>(
        for redemptionTime: UInt64,
        localIdentifiers: LocalIdentifiers,
        fetchCachedAuthCredential: (UInt64, DBReadTransaction) throws -> T?,
        authCredentialsKeyPath: KeyPath<ReceivedAuthCredentials, [(redemptionTime: UInt64, authCredential: T)]>
    ) async throws -> T {
        do {
            let authCredential = try self.db.read { (tx) throws -> T? in
                return try fetchCachedAuthCredential(redemptionTime, tx)
            }
            if let authCredential {
                return authCredential
            }
        } catch {
            owsFailDebug("Error retrieving cached auth credential: \(error)")
            // fall through to fetch a new one…
        }

        let authCredentials = try await fetchNewAuthCredentials(
            startTimestamp: redemptionTime,
            localIdentifiers: localIdentifiers
        )

        await db.awaitableWrite { tx in
            self.authCredentialStore.removeAllGroupAuthCredentials(tx: tx)
            for (redemptionTime, authCredential) in authCredentials.groupAuthCredentials {
                self.authCredentialStore.setGroupAuthCredential(
                    authCredential,
                    for: redemptionTime,
                    tx: tx
                )
            }

            self.authCredentialStore.removeAllCallLinkAuthCredentials(tx: tx)
            for (redemptionTime, authCredential) in authCredentials.callLinkAuthCredentials {
                self.authCredentialStore.setCallLinkAuthCredential(
                    authCredential,
                    for: redemptionTime,
                    tx: tx
                )
            }
        }

        let authCredential = authCredentials[keyPath: authCredentialsKeyPath].first(
            where: { $0.redemptionTime == redemptionTime }
        )?.authCredential
        guard let authCredential else {
            throw OWSAssertionError("The server didn't give us the credential we requested")
        }

        return authCredential
    }

    private struct ReceivedAuthCredentials {
        var groupAuthCredentials = [(redemptionTime: UInt64, authCredential: AuthCredentialWithPni)]()
        var callLinkAuthCredentials = [(redemptionTime: UInt64, authCredential: LibSignalClient.CallLinkAuthCredential)]()
    }

    private func fetchNewAuthCredentials(
        startTimestamp: UInt64,
        localIdentifiers: LocalIdentifiers
    ) async throws -> ReceivedAuthCredentials {
        let endTimestamp = startTimestamp + Constants.numberOfDaysToFetch * UInt64(kDayInterval)
        let timestampRange = startTimestamp...endTimestamp

        let request = OWSRequestFactory.authCredentialRequest(from: startTimestamp, to: endTimestamp)

        let response = try await SSKEnvironment.shared.networkManagerRef.asyncRequest(request, canUseWebSocket: true)

        guard let bodyData = response.responseBodyData else {
            throw OWSAssertionError("Missing or invalid JSON")
        }

        let authCredentialResponse = try JSONDecoder().decode(AuthCredentialResponse.self, from: bodyData)

        if let localPni = localIdentifiers.pni, authCredentialResponse.pni != localPni {
            Logger.warn("Auth credential \(authCredentialResponse.pni) didn't match local \(localPni)")
        }

        let serverPublicParams = GroupsV2Protos.serverPublicParams()
        let clientZkAuthOperations = ClientZkAuthOperations(serverPublicParams: serverPublicParams)
        var result = ReceivedAuthCredentials()
        for fetchedValue in authCredentialResponse.groupAuthCredentials {
            guard timestampRange.contains(fetchedValue.redemptionTime) else {
                owsFailDebug("Dropping auth credential we didn't ask for")
                continue
            }
            let receivedValue = try clientZkAuthOperations.receiveAuthCredentialWithPniAsServiceId(
                aci: localIdentifiers.aci,
                pni: authCredentialResponse.pni,
                redemptionTime: fetchedValue.redemptionTime,
                authCredentialResponse: AuthCredentialWithPniResponse(contents: [UInt8](fetchedValue.credential))
            )
            result.groupAuthCredentials.append((fetchedValue.redemptionTime, receivedValue))
        }
        for fetchedValue in authCredentialResponse.callLinkAuthCredentials {
            guard timestampRange.contains(fetchedValue.redemptionTime) else {
                owsFailDebug("Dropping call link credential we didn't ask for")
                continue
            }
            let receivedValue = try CallLinkAuthCredentialResponse(
                contents: [UInt8](fetchedValue.credential)
            ).receive(
                userId: localIdentifiers.aci,
                redemptionTime: Date(timeIntervalSince1970: TimeInterval(fetchedValue.redemptionTime)),
                params: callLinkPublicParams
            )
            result.callLinkAuthCredentials.append((fetchedValue.redemptionTime, receivedValue))
        }
        return result
    }

    /// The "start of today", i.e. midnight at the beginning of today, in epoch seconds.
    private func startOfTodayTimestamp() -> UInt64 {
        let now = self.dateProvider()
        return UInt64(now.timeIntervalSince1970 / kDayInterval) * UInt64(kDayInterval)
    }

    private struct AuthCredentialResponse: Decodable {
        enum CodingKeys: String, CodingKey {
            case pni
            case groupAuthCredentials = "credentials"
            case callLinkAuthCredentials
        }

        @PniUuid var pni: Pni
        var groupAuthCredentials: [AuthCredential]
        var callLinkAuthCredentials: [AuthCredential]

        struct AuthCredential: Decodable {
            var redemptionTime: UInt64
            var credential: Data
        }
    }
}
