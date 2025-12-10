//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient

public protocol RegistrationIdMismatchManager {
    func validateRegistrationIds() async
}

public class RegistrationIdMismatchManagerImpl: RegistrationIdMismatchManager {

    private enum Constants {
        static let collection = "RegistrationIdMismatchManagerImpl"
        static let hasRecordedSuspectedIssue = "hasRecordedSuspectedIssue"
        static let haveRegistrationIdsBeenChecked = "haveRegistrationIdsBeenChecked"
    }

    private let db: DB
    private let kvStore: KeyValueStore = KeyValueStore(collection: Constants.collection)
    private let tsAccountManager: TSAccountManager
    private let udManager: OWSUDManager
    public init(db: DB, tsAccountManager: TSAccountManager, udManager: OWSUDManager) {
        self.db = db
        self.tsAccountManager = tsAccountManager
        self.udManager = udManager
    }

    public func validateRegistrationIds() async {
        guard !db.read(block: {
            kvStore.getBool(Constants.haveRegistrationIdsBeenChecked, defaultValue: false, transaction: $0)
        }) else {
            return
        }

        guard let registeredState = db.read(block: { tx in
            return try? tsAccountManager.registeredState(tx: tx)
        }) else {
            Logger.warn("Attempting to check registrationId while unregistered.")
            return
        }

        do {
            // Check ACI
            try await _checkRegistrationIdMatches(identity: .aci, serviceId: registeredState.localIdentifiers.aci)

            // Check PNI
            if let pni = registeredState.localIdentifiers.pni {
                try await _checkRegistrationIdMatches(identity: .pni, serviceId: pni)
            } else {
                owsFailDebug("Missing PNI during registrationId check")
            }

            await db.awaitableWrite {
                kvStore.setBool(true, key: Constants.haveRegistrationIdsBeenChecked, transaction: $0)
            }
        } catch {
            owsFailDebug("Failed to validate registration IDs: \(error)")
            return
        }
    }

    private func _checkRegistrationIdMatches(identity: OWSIdentity, serviceId: ServiceId) async throws {

        let (udAccess, deviceId) = db.read { tx in (
            (serviceId as? Aci).flatMap { udManager.udAccess(for: $0, tx: tx) },
            tsAccountManager.storedDeviceId(tx: tx),
        )}

        // Fetch a key bundle for yourself.
        let requestMaker = RequestMaker(
            label: "RegistrtationId Prekey Fetch",
            serviceId: serviceId,
            canUseStoryAuth: false,
            accessKey: udAccess,
            endorsement: nil,
            authedAccount: .implicit(),
            options: [.allowIdentifiedFallback]
        )

        let result = try await requestMaker.makeRequest {
            return OWSRequestFactory.recipientPreKeyRequest(
                serviceId: serviceId,
                deviceId: deviceId.description,
                auth: $0
            )
        }

        guard let responseData = result.response.responseBodyData else {
            throw OWSAssertionError("Prekey fetch missing response object.")
        }
        guard let bundle = try? JSONDecoder().decode(SignalServiceKit.PreKeyBundle.self, from: responseData) else {
            throw OWSAssertionError("Prekey fetch returned an invalid bundle.")
        }
        guard let registrationId = bundle.devices.first?.registrationId else {
            throw OWSAssertionError("Prekey fetch missing registration Id")
        }

        if let localRegistrationId = db.read(block: { tsAccountManager.getRegistrationId(for: identity, tx: $0) }) {
            // Fetch local registration Id
            // Check if it's out of sync.
            if localRegistrationId == registrationId {
                // Everything matches, return
                Logger.info("\(identity) registrationId matches the server's understanding.")
                return
            }
            Logger.warn("\(identity) registrationId out of sync")
        } else {
            Logger.warn("\(identity) missing registrationId.")
        }

        await db.awaitableWrite {
            // update local state to match remote
            Logger.warn("Updating local \(identity) registrationId to match remote.")
            self.tsAccountManager.setRegistrationId(registrationId, for: identity, tx: $0)
            self.kvStore.setBool(true, key: Constants.hasRecordedSuspectedIssue, transaction: $0)
        }
    }
}
