//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import LibSignalClient

protocol AuthCredentialManager {
    func fetchGroupAuthCredential(localIdentifiers: LocalIdentifiers) async throws -> AuthCredentialWithPni
}

class AuthCredentialManagerImpl: AuthCredentialManager {
    private let authCredentialStore: AuthCredentialStore
    private let dateProvider: DateProvider
    private let db: any DB

    init(
        authCredentialStore: AuthCredentialStore,
        dateProvider: @escaping DateProvider,
        db: any DB
    ) {
        self.authCredentialStore = authCredentialStore
        self.dateProvider = dateProvider
        self.db = db
    }

    private enum Constants {
        static let numberOfDaysToFetch = 7 as UInt64
    }

    // MARK: -

    func fetchGroupAuthCredential(localIdentifiers: LocalIdentifiers) async throws -> AuthCredentialWithPni {
        do {
            let redemptionTime = self.startOfTodayTimestamp()
            let authCredential = try self.db.read { (tx) throws -> AuthCredentialWithPni? in
                return try self.authCredentialStore.groupAuthCredential(for: redemptionTime, tx: tx)
            }
            if let authCredential {
                return authCredential
            }
        } catch {
            owsFailDebug("Error retrieving cached auth credential: \(error)")
            // fall through to fetch a new one…
        }

        let authCredentials = try await fetchNewAuthCredentials(localIdentifiers: localIdentifiers)

        await db.awaitableWrite { tx in
            // Remove stale auth credentials.
            self.authCredentialStore.removeAllGroupAuthCredentials(tx: tx)

            // Store new auth credentials.
            for (redemptionTime, authCredential) in authCredentials.groupAuthCredentials {
                self.authCredentialStore.setGroupAuthCredential(
                    authCredential,
                    for: redemptionTime,
                    tx: tx
                )
            }
        }

        guard let authCredential = authCredentials.groupAuthCredentials.first?.authCredential else {
            throw OWSAssertionError("The server didn't give us any auth credentials.")
        }

        return authCredential
    }

    private struct ReceivedAuthCredentials {
        var groupAuthCredentials = [(redemptionTime: UInt64, authCredential: AuthCredentialWithPni)]()
    }

    private func fetchNewAuthCredentials(localIdentifiers: LocalIdentifiers) async throws -> ReceivedAuthCredentials {
        let startTimestamp = self.startOfTodayTimestamp()
        let endTimestamp = startTimestamp + Constants.numberOfDaysToFetch * UInt64(kDayInterval)

        let request = OWSRequestFactory.groupAuthenticationCredentialRequest(
            fromRedemptionSeconds: startTimestamp,
            toRedemptionSeconds: endTimestamp
        )

        let response = try await NSObject.networkManager.makePromise(
            request: request,
            canUseWebSocket: true
        ).awaitable()

        guard let bodyData = response.responseBodyData else {
            throw OWSAssertionError("Missing or invalid JSON")
        }

        let authCredentialResponse = try JSONDecoder().decode(AuthCredentialResponse.self, from: bodyData)

        if let localPni = localIdentifiers.pni, authCredentialResponse.pni != localPni {
            Logger.warn("Auth credential \(authCredentialResponse.pni) didn't match local \(localPni)")
        }

        let serverPublicParams = try GroupsV2Protos.serverPublicParams()
        let clientZkAuthOperations = ClientZkAuthOperations(serverPublicParams: serverPublicParams)
        var result = ReceivedAuthCredentials()
        for fetchedValue in authCredentialResponse.groupAuthCredentials {
            // Verify the credentials.
            let receivedValue = try clientZkAuthOperations.receiveAuthCredentialWithPniAsServiceId(
                aci: localIdentifiers.aci,
                pni: authCredentialResponse.pni,
                redemptionTime: fetchedValue.redemptionTime,
                authCredentialResponse: AuthCredentialWithPniResponse(contents: [UInt8](fetchedValue.credential))
            )
            result.groupAuthCredentials.append((fetchedValue.redemptionTime, receivedValue))
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
        }

        @PniUuid var pni: Pni
        var groupAuthCredentials: [AuthCredential]

        struct AuthCredential: Decodable {
            var redemptionTime: UInt64
            var credential: Data
        }
    }
}
