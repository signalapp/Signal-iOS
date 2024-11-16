//
// Copyright 2024 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
public import LibSignalClient

public enum MessageBackupAuthCredentialType: String, Codable, CaseIterable, CodingKeyRepresentable  {
    case media
    case messages
}

public protocol MessageBackupAuthCredentialManager {
    func fetchBackupCredential(
        for credentialType: MessageBackupAuthCredentialType,
        localAci: Aci,
        chatServiceAuth auth: ChatServiceAuth
    ) async throws -> BackupAuthCredential
}

public struct MessageBackupAuthCredentialManagerImpl: MessageBackupAuthCredentialManager {

    private enum Constants {
        static let numberOfDaysToFetchInSeconds: TimeInterval = 7 * kDayInterval
        static let numberOfDaysRemainingFutureCredentialsInSeconds: TimeInterval = 4 * kDayInterval
        static let keyValueStoreCollectionName = "MessageBackupAuthCredentialManager"
    }

    private let authCredentialStore: AuthCredentialStore
    private let dateProvider: DateProvider
    private let db: any DB
    private let kvStore: KeyValueStore
    private let messageBackupKeyMaterial: MessageBackupKeyMaterial
    private let networkManager: NetworkManager

    init(
        authCredentialStore: AuthCredentialStore,
        dateProvider: @escaping DateProvider,
        db: any DB,
        messageBackupKeyMaterial: MessageBackupKeyMaterial,
        networkManager: NetworkManager
    ) {
        self.authCredentialStore = authCredentialStore
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = KeyValueStore(collection: Constants.keyValueStoreCollectionName)
        self.messageBackupKeyMaterial = messageBackupKeyMaterial
        self.networkManager = networkManager
    }

    public func fetchBackupCredential(
        for credentialType: MessageBackupAuthCredentialType,
        localAci: Aci,
        chatServiceAuth auth: ChatServiceAuth
    ) async throws -> BackupAuthCredential {
        let redemptionTime = self.dateProvider().startOfTodayUTCTimestamp()
        let futureRedemptionTime = redemptionTime + UInt64(Constants.numberOfDaysRemainingFutureCredentialsInSeconds)

        let authCredential = db.read { tx -> BackupAuthCredential? in
            // Check there are more than 4 days of credentials remaining.
            // If not, return nil and trigger a credential fetch.
            guard let _ = self.authCredentialStore.backupAuthCredential(
                for: credentialType,
                redemptionTime: futureRedemptionTime,
                tx: tx
            ) else {
                return nil
            }

            if let backupAuthCredential = self.authCredentialStore.backupAuthCredential(
                for: credentialType,
                redemptionTime: redemptionTime,
                tx: tx
            ) {
                return backupAuthCredential
            } else {
                owsFailDebug("Error retrieving cached auth credential")
            }

            return nil
        }

        if let authCredential {
            return authCredential
        }

        let authCredentials = try await fetchNewAuthCredentials(localAci: localAci, for: credentialType, auth: auth)

        await db.awaitableWrite { tx in
            // Fetch both credential types if either is needed.
            MessageBackupAuthCredentialType.allCases.forEach { credentialType in
                guard let receivedCredentials = authCredentials[credentialType] else {
                    if credentialType == credentialType {
                        // If the requested media type fails, make some noise about it.
                        owsFailDebug("Failed to retrieve credentials for \(credentialType.rawValue)")
                    }
                    return
                }
                self.authCredentialStore.removeAllBackupAuthCredentials(for: credentialType, tx: tx)
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

        guard let authCredential = authCredentials[credentialType]?.first?.credential else {
            throw OWSAssertionError("The server didn't give us any auth credentials.")
        }

        return authCredential
    }

    private func fetchNewAuthCredentials(
        localAci: Aci,
        for credentialType: MessageBackupAuthCredentialType,
        auth: ChatServiceAuth
    ) async throws -> [MessageBackupAuthCredentialType: [ReceivedBackupAuthCredentials]] {

        let startTimestamp = self.dateProvider().startOfTodayUTCTimestamp()
        let endTimestamp = startTimestamp + UInt64(Constants.numberOfDaysToFetchInSeconds)
        let timestampRange = startTimestamp...endTimestamp

        let request = OWSRequestFactory.backupAuthenticationCredentialRequest(
            from: startTimestamp,
            to: endTimestamp,
            auth: auth
        )

        // TODO: Switch this back to true when reg supports websockets
        let response = try await networkManager.asyncRequest(request, canUseWebSocket: false)
        guard let data = response.responseBodyData else {
            throw OWSAssertionError("Missing response body data")
        }

        let authCredentialRepsonse = try JSONDecoder().decode(BackupCredentialResponse.self, from: data)

        let backupServerPublicParams = try GenericServerPublicParams(contents: [UInt8](TSConstants.backupServerPublicParams))
        return try authCredentialRepsonse.credentials.reduce(into: [MessageBackupAuthCredentialType: [ReceivedBackupAuthCredentials]]()) { result, element in
            let type = element.key
            result[type] = try element.value.compactMap {
                guard timestampRange.contains($0.redemptionTime) else {
                    owsFailDebug("Dropping \(type.rawValue) backup credential we didn't ask for")
                    return nil
                }
                do {
                    let redemptionDate = Date(timeIntervalSince1970: TimeInterval($0.redemptionTime))
                    let backupRequestContext = try db.read { tx in
                        let backupKey = try messageBackupKeyMaterial.backupKey(type: type, tx: tx)
                        return BackupAuthCredentialRequestContext.create(backupKey: backupKey.serialize(), aci: localAci.rawUUID)
                    }
                    let backupAuthResponse = try BackupAuthCredentialResponse(contents: [UInt8]($0.credential))
                    let credential = try backupRequestContext.receive(
                        backupAuthResponse,
                        timestamp: redemptionDate,
                        params: backupServerPublicParams
                    )
                    return ReceivedBackupAuthCredentials(redemptionTime: $0.redemptionTime, credential: credential)
                } catch MessageBackupKeyMaterialError.missingMasterKey where type != credentialType {
                    return nil
                } catch {
                    owsFailDebug("Error creating credential")
                    throw error
                }
            }
        }
    }

    private struct BackupCredentialResponse: Decodable {
        var credentials: [MessageBackupAuthCredentialType: [AuthCredential]]

        struct AuthCredential: Decodable {
            var redemptionTime: UInt64
            var credential: Data
        }
    }

    private struct ReceivedBackupAuthCredentials {
        var redemptionTime: UInt64
        var credential: BackupAuthCredential
    }
}

fileprivate extension Date {
    /// The "start of today", i.e. midnight at the beginning of today, in epoch seconds.
    func startOfTodayUTCTimestamp() -> UInt64 {
        return UInt64(self.timeIntervalSince1970 / kDayInterval) * UInt64(kDayInterval)
    }
}
