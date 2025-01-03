//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

/// It is possible that a user does not know their own PNI. However, in order to
/// be PNP-compatible, a user's PNI and PNI identity key must be synced between
/// the client and service. This manager handles syncing the PNI and related
/// keys as necessary.
public protocol LearnMyOwnPniManager {
    func learnMyOwnPniIfNecessary() async throws
}

final class LearnMyOwnPniManagerImpl: LearnMyOwnPniManager {
    fileprivate static let logger = PrefixedLogger(prefix: "LMOPMI")
    private var logger: PrefixedLogger { Self.logger }

    private let db: any DB
    private let registrationStateChangeManager: RegistrationStateChangeManager
    private let taskQueue: SerialTaskQueue
    private let tsAccountManager: TSAccountManager
    private let whoAmIManager: WhoAmIManager

    init(
        db: any DB,
        registrationStateChangeManager: RegistrationStateChangeManager,
        tsAccountManager: TSAccountManager,
        whoAmIManager: WhoAmIManager
    ) {
        self.db = db
        self.registrationStateChangeManager = registrationStateChangeManager
        self.taskQueue = SerialTaskQueue()
        self.tsAccountManager = tsAccountManager
        self.whoAmIManager = whoAmIManager
    }

    func learnMyOwnPniIfNecessary() async throws {
        try await taskQueue.enqueue {
            try await self._learnMyOwnPniIfNecessary()
        }.value
    }

    private func _learnMyOwnPniIfNecessary() async throws {
        let localIdentifiers: LocalIdentifiers? = db.read { tx in
            guard tsAccountManager.registrationState(tx: tx).isPrimaryDevice ?? true else {
                return nil
            }

            guard let localIdentifiers = tsAccountManager.localIdentifiers(tx: tx) else {
                logger.warn("Skipping PNI learning, no local identifiers!")
                return nil
            }

            return localIdentifiers
        }

        guard let localIdentifiers else {
            return
        }

        do {
            try await fetchMyPniIfNecessary(localIdentifiers: localIdentifiers)
        } catch let error {
            logger.error("Error learning local PNI! \(error)")
            throw error
        }
    }

    private func fetchMyPniIfNecessary(localIdentifiers: LocalIdentifiers) async throws {
        if localIdentifiers.pni != nil {
            return
        }

        let whoAmI = try await whoAmIManager.makeWhoAmIRequest()

        let remoteE164 = whoAmI.e164
        let remoteAci = whoAmI.aci
        let remotePni = whoAmI.pni

        logger.info("Successfully fetched PNI: \(remotePni)")

        guard
            localIdentifiers.aci == remoteAci,
            localIdentifiers.contains(phoneNumber: remoteE164)
        else {
            throw OWSGenericError(
                "Remote ACI \(remoteAci) and e164 \(remoteE164) were not present in local identifiers, skipping PNI save."
            )
        }

        await db.awaitableWrite { tx in
            registrationStateChangeManager.didUpdateLocalPhoneNumber(
                remoteE164,
                aci: remoteAci,
                pni: remotePni,
                tx: tx
            )
        }
    }
}
