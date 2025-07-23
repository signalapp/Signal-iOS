//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import DeviceCheck

/// Responsible for managing paid-tier Backup entitlements for TestFlight users,
/// who aren't able to use StoreKit or perform real-money transactions.
public final class BackupTestFlightEntitlementManager {
    private enum StoreKeys {
        static let lastEntitlementRenewalDate = "lastEntitlementRenewalDate"
    }

    private let appAttestManager: AppAttestManager
    private let backupPlanManager: BackupPlanManager
    private let dateProvider: DateProvider
    private let db: DB
    private let logger: PrefixedLogger
    private let kvStore: KeyValueStore

    init(
        backupPlanManager: BackupPlanManager,
        dateProvider: @escaping DateProvider,
        db: DB,
        networkManager: NetworkManager,
    ) {
        self.logger = PrefixedLogger(prefix: "[Backups]")

        self.appAttestManager = AppAttestManager(
            attestationService: .shared,
            db: db,
            logger: logger,
            networkManager: networkManager
        )
        self.backupPlanManager = backupPlanManager
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = KeyValueStore(collection: "BackupTestFlightEntitlementManager")
    }

    // MARK: -

    public func acquireEntitlement() async throws {
        owsPrecondition(FeatureFlags.Backups.avoidStoreKitForTesters)

        guard TSConstants.isUsingProductionService else {
            // If we're on Staging, no need to do anything – all accounts on
            // Staging get the entitlement automatically.
            logger.info("Skipping acquiring Backup entitlement: on Staging!")
            return
        }

        try await appAttestManager.performAttestationAction(.acquireBackupEntitlement)

        logger.info("Successfully acquired Backup entitlement!")
    }

    // MARK: -

    public func renewEntitlementIfNecessary() async throws {
        let isCurrentlyTesterBuild = FeatureFlags.Backups.avoidStoreKitForTesters
        let (
            currentBackupPlan,
            lastEntitlementRenewalDate
        ): (
            BackupPlan,
            Date?
        ) = db.read { tx in
            (
                backupPlanManager.backupPlan(tx: tx),
                kvStore.getDate(StoreKeys.lastEntitlementRenewalDate, transaction: tx)
            )
        }

        switch currentBackupPlan {
        case .disabled, .disabling, .free, .paid, .paidExpiringSoon:
            // If we're not a paid-tier tester, nothing to do.
            return
        case .paidAsTester:
            break
        }

        guard isCurrentlyTesterBuild else {
            // Uh oh: we think we're a paid-tier tester, but our current build
            // isn't a tester build. We likely downgraded to prod builds, so
            // correspondingly downgrade our BackupPlan to free.
            try await db.awaitableWriteWithRollbackIfThrows { tx in
                try backupPlanManager.setBackupPlan(.free, tx: tx)
            }
            return
        }

        if
            let lastEntitlementRenewalDate,
            lastEntitlementRenewalDate.addingTimeInterval(3 * .day) > dateProvider()
        {
            logger.info("Not renewing; we did so recently.")
            return
        }

        try await acquireEntitlement()

        await db.awaitableWrite { tx in
            kvStore.setDate(
                dateProvider(),
                key: StoreKeys.lastEntitlementRenewalDate,
                transaction: tx
            )
        }
    }
}

// MARK: -

/// Responsible for using the `AppAttest` feature of Apple's `DeviceCheck`
/// framework to perform actions that are restricted to first-party instances of
/// Signal iOS.
///
/// For example, `StoreKit` on TestFlight builds is restricted to the Sandbox
/// environment, which makes it impossible for TestFlight users to pay for and
/// redeem a Backups subscription. As a workaround, we use the `AppAttest`
/// to make a request that gets us a paid-tier Backups entitlement without
/// requiring a paid `StoreKit` subscription.
///
/// However, to prevent abuse we need to restrict these requests to first-party
/// TestFlight builds. We do this by gating the request with `AppAttest`, and
/// then limit the requests to TestFlight-flavored builds using a `FeatureFlag`.
private struct AppAttestManager {

    /// Actions that require `DeviceCheck` attestation.
    enum AttestationAction: String {
        /// Add the "backup" entitlement to our account, as if we had redeemed a
        /// Backups subscription.
        case acquireBackupEntitlement = "backup"
    }

    enum AttestationError: Error {
        /// Attestation is not supported on this device or app instance.
        case notSupported
        case networkError
        case genericError
    }

    /// Represents a key, stored on this device in the Secure Enclave, which
    /// has been both attested by Apple and verified by Signal servers.
    ///
    /// Attestation by Apple requires a first-party instance of the app. Once
    /// attested/verified, a key can be used to generate "assertions" for
    /// requests, thereby proving the request originated from a first-party
    /// instance of the app.
    private struct AttestedKey {
        let identifier: String
    }

    /// Represents a network request for which we've generated an assertion.
    private struct RequestAssertion {
        let requestData: Data
        let assertion: Data
    }

    // MARK: -

    private let attestationService: DCAppAttestService
    private let db: DB
    private let kvStore: KeyValueStore
    private let logger: PrefixedLogger
    private let networkManager: NetworkManager

    init(
        attestationService: DCAppAttestService,
        db: DB,
        logger: PrefixedLogger,
        networkManager: NetworkManager
    ) {
        self.attestationService = attestationService
        self.db = db
        self.kvStore = KeyValueStore(collection: "AppAttestationManager")
        self.logger = logger
        self.networkManager = networkManager
    }

    private func parseDCError(_ dcError: DCError) -> AttestationError {
        switch dcError.code {
        case .featureUnsupported:
            return .notSupported
        case .serverUnavailable:
            return .networkError
        case .unknownSystemFailure, .invalidInput, .invalidKey:
            fallthrough
        @unknown default:
            owsFailDebug("Unexpected DCError code: \(dcError.code)", logger: logger)
            return .genericError
        }
    }

    // MARK: -

    /// Perform the given attestation action.
    ///
    /// This involves generating and attesting a key that is registered with
    /// Signal servers, then using that key to generate an assertion for a
    /// request to Signal servers to perform the given action. That assertion
    /// is sent alongside the request to Signal servers, who upon validating the
    /// assertion will perform the action.
    public func performAttestationAction(
        _ action: AttestationAction,
    ) async throws(AttestationError) {
        guard attestationService.isSupported else {
            throw .notSupported
        }

        logger.info("Getting attested key.")
        let attestedKey = try await getOrGenerateAttestedKey()

        logger.info("Generating assertion.")
        let requestAssertion = try await generateAssertionForAction(
            action,
            attestedKey: attestedKey
        )

        logger.info("Performing attestation action with assertion.")
        try await _performAttestationAction(
            keyId: attestedKey.identifier,
            requestAssertion: requestAssertion
        )
    }

    private func _performAttestationAction(
        keyId: String,
        requestAssertion: RequestAssertion,
    ) async throws(AttestationError) {
        guard let keyIdData = Data(base64Encoded: keyId) else {
            owsFailDebug("Failed to convert keyId to data performing attestation action!")
            throw .genericError
        }

        let response: HTTPResponse
        do {
            response = try await networkManager.asyncRequest(.performAttestationAction(
                keyIdData: keyIdData,
                assertedRequestData: requestAssertion.requestData,
                assertion: requestAssertion.assertion
            ))
        } catch where error.isNetworkFailureOrTimeout {
            throw .networkError
        } catch {
            owsFailDebug("Unexpected error performing attestation action! \(error)", logger: logger)
            throw .genericError
        }

        switch response.responseStatusCode {
        case 204:
            break
        default:
            owsFailDebug("Unexpected status code performing attestation action! \(response.responseStatusCode)", logger: logger)
            throw .genericError
        }
    }

    // MARK: - Attestation

    /// Returns an identifier for a attested key. Generates and attests a new
    /// key if necessary, or returns an existing key if attestation was
    /// performed in the past.
    private func getOrGenerateAttestedKey() async throws(AttestationError) -> AttestedKey {
        if let attestedKeyId = readAttestedKeyId() {
            logger.info("Using previously-attested key.")
            return AttestedKey(identifier: attestedKeyId)
        }

        // Generate a new key that we'll then attempt to attest and register
        // with the Signal service.
        let newKeyId: String
        do {
            newKeyId = try await attestationService.generateKey()
        } catch let dcError as DCError {
            throw parseDCError(dcError)
        } catch {
            owsFailDebug("Unexpected error generating key! \(error)", logger: logger)
            throw .genericError
        }

        logger.info("Attesting and registering new key.")
        return try await attestAndRegisterKey(newKeyId: newKeyId)
    }

    /// Perform attestation on a newly-generated key, and register it with
    /// Signal servers.
    ///
    /// This involves requesting a challenge from Signal, having Apple sign that
    /// challenge using our new key, and finally having Signal validate that
    /// signature and thereafter saving our new key.
    ///
    /// Once a key has been attested and registered, it can be used to perform
    /// assertions on future requests.
    private func attestAndRegisterKey(newKeyId: String) async throws(AttestationError) -> AttestedKey {
        // Get a challenge from Signal servers.
        let keyAttestationChallenge: String = try await getKeyAttestationChallenge()

        guard
            let keyAttestationChallengeHash = keyAttestationChallenge
                .data(using: .utf8)
                .map({ Data(SHA256.hash(data: $0)) })
        else {
            owsFailDebug("Failed to hash challenge string!", logger: logger)
            throw .genericError
        }

        // Sign the challenge-known-to-Signal-servers using our new key (aka,
        // generate an attestation for this key).
        let keyAttestation: Data
        do {
            keyAttestation = try await attestationService.attestKey(
                newKeyId,
                clientDataHash: keyAttestationChallengeHash
            )
        } catch let dcError as DCError {
            throw parseDCError(dcError)
        } catch {
            owsFailDebug("Unexpected error attesting key with Apple! \(error)", logger: logger)
            throw .genericError
        }

        // Give the signed challenge to Signal servers, who will validate that
        // the signature/attestation (and therefore the key) is valid. If this
        // succeeds, the Signal servers will record this key so we can use it
        // to generate assertions for future requests.
        try await _attestAndRegisterKey(
            keyId: newKeyId,
            keyAttestation: keyAttestation
        )

        // Hurray! The key is valid, and reigstered with Signal servers. We can
        // now save it, so we can use it to sign future requests.
        await saveAttestedKeyId(newKeyId)

        return AttestedKey(identifier: newKeyId)
    }

    /// Get a challenge from Signal servers that we can use to attest that a new
    /// key is valid.
    private func getKeyAttestationChallenge() async throws(AttestationError) -> String {
        let response: HTTPResponse
        do {
            response = try await networkManager.asyncRequest(.getAttestationChallenge())
        } catch where error.isNetworkFailureOrTimeout {
            throw .networkError
        } catch {
            owsFailDebug("Unexpected error fetching attestation challenge! \(error)", logger: logger)
            throw .genericError
        }

        switch response.responseStatusCode {
        case 200:
            break
        default:
            owsFailDebug("Unexpected status code fetching attestation challenge! \(response.responseStatusCode)", logger: logger)
            throw .genericError
        }

        guard let responseBodyData = response.responseBodyData else {
            owsFailDebug("Missing response body data fetching attestation challenge!", logger: logger)
            throw .genericError
        }

        struct AttestationChallengeResponseBody: Decodable {
            let challenge: String
        }
        let responseBody: AttestationChallengeResponseBody
        do {
            responseBody = try JSONDecoder().decode(
                AttestationChallengeResponseBody.self,
                from: responseBodyData
            )
        } catch {
            owsFailDebug("Failed to decode response body fetching attestation challenge! \(error)", logger: logger)
            throw .genericError
        }

        return responseBody.challenge
    }

    /// Validate an attestation, or challenge signed by a new key, with Signal
    /// servers. If this succeeds, Signal servers will record this key so it can
    /// be used to generate assertions for future requests.
    private func _attestAndRegisterKey(
        keyId: String,
        keyAttestation: Data,
    ) async throws(AttestationError) {
        guard let keyIdData = Data(base64Encoded: keyId) else {
            owsFailDebug("Failed to base64-decode keyId validating key attestation!")
            throw .genericError
        }

        let response: HTTPResponse
        do {
            response = try await networkManager.asyncRequest(.attestAndRegisterKey(
                keyIdData: keyIdData,
                keyAttestation: keyAttestation
            ))
        } catch where error.isNetworkFailureOrTimeout {
            throw .networkError
        } catch {
            owsFailDebug("Unexpected error validating key attestation! \(error)", logger: logger)
            throw .genericError
        }

        switch response.responseStatusCode {
        case 204:
            break
        default:
            owsFailDebug("Unexpected status code validating key attestation! \(response.responseStatusCode)", logger: logger)
            throw .genericError
        }
    }

    // MARK: - Assertions

    /// Generate an assertion to perform the given action.
    ///
    /// This involves requesting a challenge from Signal, merging the challenge
    /// with the action into a request body, and using a previously-attested key
    /// to generate an assertion for the request.
    private func generateAssertionForAction(
        _ action: AttestationAction,
        attestedKey: AttestedKey,
    ) async throws(AttestationError) -> RequestAssertion {
        struct AssertableAttestationAction: Encodable {
            let action: String
            let challenge: String
        }
        let assertableAction = AssertableAttestationAction(
            action: action.rawValue,
            challenge: try await getRequestAssertionChallenge(action: action)
        )

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(assertableAction)
        } catch {
            owsFailDebug("Failed to encode request parameters for assertion! \(error)", logger: logger)
            throw .genericError
        }

        let assertion: Data
        do {
            assertion = try await attestationService.generateAssertion(
                attestedKey.identifier,
                clientDataHash: Data(SHA256.hash(data: requestData))
            )
        } catch let dcError as DCError {
            throw parseDCError(dcError)
        } catch {
            owsFailDebug("Unexpected error generating assertion! \(error)", logger: logger)
            throw .genericError
        }

        return RequestAssertion(
            requestData: requestData,
            assertion: assertion
        )
    }

    /// Request a challenge from Signal servers to generate an assertion to
    /// perform the given action.
    private func getRequestAssertionChallenge(
        action: AttestationAction,
    ) async throws(AttestationError) -> String {
        let response: HTTPResponse
        do {
            response = try await networkManager.asyncRequest(.getAssertionChallenge(
                action: action
            ))
        } catch where error.isNetworkFailureOrTimeout {
            throw .networkError
        } catch {
            owsFailDebug("Unexpected error fetching assertion challenge! \(error)", logger: logger)
            throw .genericError
        }

        switch response.responseStatusCode {
        case 200:
            break
        default:
            owsFailDebug("Unexpected status code fetching assertion challenge! \(response.responseStatusCode)", logger: logger)
            throw .genericError
        }

        guard let responseBodyData = response.responseBodyData else {
            owsFailDebug("Missing response body data fetching assertion challenge!", logger: logger)
            throw .genericError
        }

        struct AssertionChallengeResponseBody: Decodable {
            let challenge: String
        }
        let responseBody: AssertionChallengeResponseBody
        do {
            responseBody = try JSONDecoder().decode(
                AssertionChallengeResponseBody.self,
                from: responseBodyData
            )
        } catch {
            owsFailDebug("Failed to decode response body fetching assertion challenge! \(error)", logger: logger)
            throw .genericError
        }

        return responseBody.challenge
    }

    // MARK: - Persistence

    private enum StoreKeys {
        static let keyId = "keyId"
    }

    /// Returns the identifier of a key for this device that has previously
    /// passed attestation, if one exists.
    private func readAttestedKeyId() -> String? {
        return db.read { tx in
            return kvStore.getString(StoreKeys.keyId, transaction: tx)
        }
    }

    /// Save the given key id, which represents a key for this device
    /// that has passed attestation.
    private func saveAttestedKeyId(_ keyIdentifier: String) async {
        await db.awaitableWrite { tx in
            kvStore.setString(keyIdentifier, key: StoreKeys.keyId, transaction: tx)
        }
    }
}

// MARK: -

private extension TSRequest {
    static func getAssertionChallenge(
        action: AppAttestManager.AttestationAction,
    ) -> TSRequest {
        return TSRequest(
            url: URL(string: "v1/devicecheck/assert?action=\(action.rawValue)")!,
            method: "GET",
        )
    }

    static func performAttestationAction(
        keyIdData: Data,
        assertedRequestData: Data,
        assertion: Data,
    ) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/devicecheck/assert?keyId=\(keyIdData.asBase64Url)&request=\(assertedRequestData.asBase64Url)")!,
            method: "POST",
            body: .data(assertion)
        )
        request.headers["Content-Type"] = "application/octet-stream"
        return request
    }

    static func getAttestationChallenge() -> TSRequest {
        return TSRequest(
            url: URL(string: "v1/devicecheck/attest")!,
            method: "GET",
            parameters: nil
        )
    }

    static func attestAndRegisterKey(
        keyIdData: Data,
        keyAttestation: Data,
    ) -> TSRequest {
        var request = TSRequest(
            url: URL(string: "v1/devicecheck/attest?keyId=\(keyIdData.asBase64Url)")!,
            method: "PUT",
            body: .data(keyAttestation)
        )
        request.headers["Content-Type"] = "application/octet-stream"
        return request
    }
}
