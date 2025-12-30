//
// Copyright 2025 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import CryptoKit
import DeviceCheck

/// Responsible for managing paid-tier Backup entitlements for TestFlight users,
/// who aren't able to use StoreKit or perform real-money transactions.
public protocol BackupTestFlightEntitlementManager {
    func acquireEntitlement() async throws

    func setRenewEntitlementIsNecessary(tx: DBWriteTransaction)
    func renewEntitlementIfNecessary() async throws
}

// MARK: -

final class BackupTestFlightEntitlementManagerImpl: BackupTestFlightEntitlementManager {
    private enum StoreKeys {
        static let lastEntitlementRenewalDate = "lastEntitlementRenewalDate"
    }

    private let appAttestManager: AppAttestManager
    private let backupPlanManager: BackupPlanManager
    private let backupSubscriptionIssueStore: BackupSubscriptionIssueStore
    private let backupSubscriptionManager: BackupSubscriptionManager
    private let dateProvider: DateProvider
    private let db: DB
    private let logger: PrefixedLogger
    private let kvStore: KeyValueStore
    private let serialTaskQueue: ConcurrentTaskQueue
    private let tsAccountManager: TSAccountManager

    init(
        backupPlanManager: BackupPlanManager,
        backupSubscriptionIssueStore: BackupSubscriptionIssueStore,
        backupSubscriptionManager: BackupSubscriptionManager,
        dateProvider: @escaping DateProvider,
        db: DB,
        networkManager: NetworkManager,
        tsAccountManager: TSAccountManager,
    ) {
        self.logger = PrefixedLogger(prefix: "[Backups]")

        self.appAttestManager = AppAttestManager(
            attestationService: .shared,
            db: db,
            logger: logger,
            networkManager: networkManager,
        )
        self.backupPlanManager = backupPlanManager
        self.backupSubscriptionIssueStore = backupSubscriptionIssueStore
        self.backupSubscriptionManager = backupSubscriptionManager
        self.dateProvider = dateProvider
        self.db = db
        self.kvStore = KeyValueStore(collection: "BackupTestFlightEntitlementManager")
        self.serialTaskQueue = ConcurrentTaskQueue(concurrentLimit: 1)
        self.tsAccountManager = tsAccountManager
    }

    // MARK: -

    func acquireEntitlement() async throws {
        try await serialTaskQueue.run {
            try await _acquireEntitlement()
        }
    }

    private func _acquireEntitlement() async throws {
        owsPrecondition(BuildFlags.Backups.avoidStoreKitForTesters)

        guard TSConstants.isUsingProductionService else {
            // If we're on Staging, no need to do anything – all accounts on
            // Staging get the entitlement automatically.
            logger.info("Skipping acquiring Backup entitlement: on Staging!")
            return
        }

        guard !BuildFlags.Backups.avoidAppAttestForDevs else {
            // If we're on a dev build, we can't use AppAttest. If you're a dev
            // who needs the entitlement (i.e., paid-tier Backup auth
            // credentials), make sure you've gotten it for your account via
            // another path.
            logger.warn("WARNING! Skipping acquiring Backup entitlement: AppAttest not supported. Make sure your account has the entitlement via other means, if necessary.")
            return
        }

        try await Retry.performWithBackoff(
            maxAttempts: 5,
            isRetryable: { error in
                return error.isNetworkFailureOrTimeout
                    || error.is5xxServiceResponse
                    // TODO: Back off for the amount specified in the retry-after
                    || error.httpStatusCode == 429
            },
        ) {
            try await appAttestManager.performAttestationAction(.acquireBackupEntitlement)
        }

        logger.info("Successfully acquired Backup entitlement!")
    }

    // MARK: -

    func setRenewEntitlementIsNecessary(tx: DBWriteTransaction) {
        kvStore.removeValue(forKey: StoreKeys.lastEntitlementRenewalDate, transaction: tx)
    }

    func renewEntitlementIfNecessary() async throws {
        let (
            isRegisteredPrimaryDevice,
            isCurrentlyTesterBuild,
            currentBackupPlan,
            lastEntitlementRenewalDate,
        ): (
            Bool,
            Bool,
            BackupPlan,
            Date?,
        ) = db.read { tx in
            (
                tsAccountManager.registrationState(tx: tx).isRegisteredPrimaryDevice,
                BuildFlags.Backups.avoidStoreKitForTesters,
                backupPlanManager.backupPlan(tx: tx),
                kvStore.getDate(StoreKeys.lastEntitlementRenewalDate, transaction: tx),
            )
        }

        guard isRegisteredPrimaryDevice else {
            return
        }

        let optimizeLocalStorage: Bool
        switch currentBackupPlan {
        case .disabled, .disabling, .free, .paid, .paidExpiringSoon:
            // If we're not a paid-tier tester, nothing to do.
            return
        case .paidAsTester(let _optimizeLocalStorage):
            optimizeLocalStorage = _optimizeLocalStorage
        }

        guard isCurrentlyTesterBuild else {
            try await downgradeForNoLongerTestFlight(
                hadOptimizeLocalStorage: optimizeLocalStorage,
            )
            return
        }

        if
            let lastEntitlementRenewalDate,
            lastEntitlementRenewalDate.addingTimeInterval(3 * .day) > dateProvider()
        {
            return
        }

        try await acquireEntitlement()

        await db.awaitableWrite { tx in
            kvStore.setDate(
                dateProvider(),
                key: StoreKeys.lastEntitlementRenewalDate,
                transaction: tx,
            )
        }
    }

    private func downgradeForNoLongerTestFlight(
        hadOptimizeLocalStorage: Bool,
    ) async throws {
        let iapSubscription = try await backupSubscriptionManager.fetchAndMaybeDowngradeSubscription()

        // We think we're a paid-tier tester, but our current build isn't a
        // tester build! We likely went from TestFlight -> App Store builds.
        //
        // It's plausible, though, that we are still a paid-tier user by
        // virtue of having an IAP subscription either from before we were
        // on TestFlight, or from having moved to iOS from an Android on
        // which we had an IAP subscription.
        //
        // To that end, check if we have an active IAP subscription. If so,
        // set to `.paid`. If not, set to `.free`.
        let newBackupPlan: BackupPlan
        let shouldWarnDowngraded: Bool
        if let iapSubscription, iapSubscription.active {
            newBackupPlan = .paid(optimizeLocalStorage: hadOptimizeLocalStorage)
            shouldWarnDowngraded = false
        } else {
            newBackupPlan = .free
            shouldWarnDowngraded = true
        }

        await db.awaitableWrite { tx in
            backupPlanManager.setBackupPlan(newBackupPlan, tx: tx)

            if shouldWarnDowngraded {
                backupSubscriptionIssueStore.setShouldWarnTestFlightSubscriptionExpired(true, tx: tx)
            }
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
/// then limit the requests to TestFlight-flavored builds using a BuildFlag.
private struct AppAttestManager {

    /// Actions that require `DeviceCheck` attestation.
    enum AttestationAction: String {
        /// Add the "backup" entitlement to our account, as if we had redeemed a
        /// Backups subscription.
        case acquireBackupEntitlement = "backup"
    }

    enum AppAttestError: Error {
        /// Attestation is not supported on this device or app instance.
        case notSupported

        /// iOS failed to generate an assertion using a previously-attested key.
        ///
        /// Believed to be an iOS issue, indicating that the previously-attested
        /// key should be discarded.
        case failedToGenerateAssertionWithPreviouslyAttestedKey
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
        networkManager: NetworkManager,
    ) {
        self.attestationService = attestationService
        self.db = db
        self.kvStore = KeyValueStore(collection: "AppAttestationManager")
        self.logger = logger
        self.networkManager = networkManager
    }

    private func parseDCError(
        _ dcError: DCError,
        function: String = #function,
        line: Int = #line,
    ) -> Error {
        switch dcError.code {
        case .featureUnsupported:
            return AppAttestError.notSupported
        case .serverUnavailable:
            return OWSHTTPError.networkFailure(.genericFailure)
        case .unknownSystemFailure, .invalidInput, .invalidKey:
            fallthrough
        @unknown default:
            owsFailDebug("Unexpected DCError code: \(dcError.code)", logger: logger, function: function, line: line)
            return OWSGenericError("Unexpected DCError! \(dcError.code)")
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
    func performAttestationAction(
        _ action: AttestationAction,
    ) async throws {
        guard attestationService.isSupported else {
            throw AppAttestError.notSupported
        }

        logger.info("Getting attested key.")
        let attestedKey = try await getOrGenerateAttestedKey()

        logger.info("Generating assertion.")
        do {
            let requestAssertion = try await generateAssertionForAction(
                action,
                attestedKey: attestedKey,
            )

            logger.info("Performing attestation action with assertion.")
            try await _performAttestationAction(
                keyId: attestedKey.identifier,
                requestAssertion: requestAssertion,
            )
        } catch AppAttestError.failedToGenerateAssertionWithPreviouslyAttestedKey {
            // If we failed to generate an assertion with a previously-attested
            // key, throw that key away and try again.
            logger.warn("Failed to generate assertion with previously-attested key. Wiping key and starting over.")
            await wipeAttestedKeyId()
            try await performAttestationAction(action)
        }
    }

    private func _performAttestationAction(
        keyId: String,
        requestAssertion: RequestAssertion,
    ) async throws {
        guard let keyIdData = Data(base64Encoded: keyId) else {
            throw OWSAssertionError("Failed to convert keyId to data performing attestation action!", logger: logger)
        }

        let response = try await networkManager.asyncRequest(.performAttestationAction(
            keyIdData: keyIdData,
            assertedRequestData: requestAssertion.requestData,
            assertion: requestAssertion.assertion,
        ))

        switch response.responseStatusCode {
        case 204:
            break
        default:
            throw response.asError()
        }
    }

    // MARK: - Attestation

    /// Returns an identifier for a attested key. Generates and attests a new
    /// key if necessary, or returns an existing key if attestation was
    /// performed in the past.
    private func getOrGenerateAttestedKey() async throws -> AttestedKey {
        if let attestedKeyId = await readAttestedKeyId() {
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
            throw OWSAssertionError("Unexpected error generating key! \(error)", logger: logger)
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
    private func attestAndRegisterKey(newKeyId: String) async throws -> AttestedKey {
        // Get a challenge from Signal servers.
        let keyAttestationChallenge: String = try await getKeyAttestationChallenge()
        let keyAttestationChallengeHash = SHA256.hash(data: Data(keyAttestationChallenge.utf8))

        // Sign the challenge-known-to-Signal-servers using our new key (aka,
        // generate an attestation for this key).
        let keyAttestation: Data
        do {
            keyAttestation = try await attestationService.attestKey(
                newKeyId,
                clientDataHash: Data(keyAttestationChallengeHash),
            )
        } catch let dcError as DCError {
            throw parseDCError(dcError)
        } catch {
            throw OWSAssertionError("Unexpected error attesting key with Apple! \(error)", logger: logger)
        }

        // Give the signed challenge to Signal servers, who will validate that
        // the signature/attestation (and therefore the key) is valid. If this
        // succeeds, the Signal servers will record this key so we can use it
        // to generate assertions for future requests.
        try await _attestAndRegisterKey(
            keyId: newKeyId,
            keyAttestation: keyAttestation,
        )

        // Hurray! The key is valid, and reigstered with Signal servers. We can
        // now save it, so we can use it to sign future requests.
        await saveAttestedKeyId(newKeyId)

        return AttestedKey(identifier: newKeyId)
    }

    /// Get a challenge from Signal servers that we can use to attest that a new
    /// key is valid.
    private func getKeyAttestationChallenge() async throws -> String {
        let response = try await networkManager.asyncRequest(.getAttestationChallenge())

        guard
            response.responseStatusCode == 200,
            let responseBodyData = response.responseBodyData
        else {
            throw response.asError()
        }

        struct AttestationChallengeResponseBody: Decodable {
            let challenge: String
        }
        let responseBody: AttestationChallengeResponseBody
        do {
            responseBody = try JSONDecoder().decode(
                AttestationChallengeResponseBody.self,
                from: responseBodyData,
            )
        } catch {
            throw OWSAssertionError("Failed to decode response body fetching attestation challenge! \(error)", logger: logger)
        }

        return responseBody.challenge
    }

    /// Validate an attestation, or challenge signed by a new key, with Signal
    /// servers. If this succeeds, Signal servers will record this key so it can
    /// be used to generate assertions for future requests.
    private func _attestAndRegisterKey(
        keyId: String,
        keyAttestation: Data,
    ) async throws {
        guard let keyIdData = Data(base64Encoded: keyId) else {
            throw OWSAssertionError("Failed to base64-decode keyId validating key attestation!", logger: logger)
        }

        let response = try await networkManager.asyncRequest(.attestAndRegisterKey(
            keyIdData: keyIdData,
            keyAttestation: keyAttestation,
        ))

        switch response.responseStatusCode {
        case 204:
            break
        default:
            throw response.asError()
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
    ) async throws -> RequestAssertion {
        struct AssertableAttestationAction: Encodable {
            let action: String
            let challenge: String
        }
        let assertableAction = AssertableAttestationAction(
            action: action.rawValue,
            challenge: try await getRequestAssertionChallenge(action: action),
        )

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(assertableAction)
        } catch {
            throw OWSAssertionError("Failed to encode request parameters for assertion! \(error)", logger: logger)
        }

        let assertion: Data
        do {
            assertion = try await attestationService.generateAssertion(
                attestedKey.identifier,
                clientDataHash: Data(SHA256.hash(data: requestData)),
            )
        } catch let dcError as DCError {
            switch dcError.code {
            case .invalidInput, .invalidKey:
                /// There appears to be an issue with AppAttest that can cause
                /// the `.generateAssertion` API to throw `.invalidInput` when
                /// using a previously-attested key, some significant percentage
                /// of the time. Doesn't seem to be a clear pattern, and is
                /// widely reported:
                ///
                /// - https://github.com/firebase/firebase-ios-sdk/issues/12629
                /// - https://developer.apple.com/forums/thread/788405
                ///
                /// If nothing else, we know now that AppAttest considers this
                /// key invalid, so we should discard it and start over.
                ///
                /// For good measure, handle `.invalidKey` too.
                throw AppAttestError.failedToGenerateAssertionWithPreviouslyAttestedKey
            default:
                throw parseDCError(dcError)
            }
        } catch {
            throw OWSAssertionError("Unexpected error generating assertion! \(error)", logger: logger)
        }

        return RequestAssertion(
            requestData: requestData,
            assertion: assertion,
        )
    }

    /// Request a challenge from Signal servers to generate an assertion to
    /// perform the given action.
    private func getRequestAssertionChallenge(
        action: AttestationAction,
    ) async throws -> String {
        let response = try await networkManager.asyncRequest(.getAssertionChallenge(
            action: action,
        ))

        guard
            response.responseStatusCode == 200,
            let responseBodyData = response.responseBodyData
        else {
            throw response.asError()
        }

        struct AssertionChallengeResponseBody: Decodable {
            let challenge: String
        }
        let responseBody: AssertionChallengeResponseBody
        do {
            responseBody = try JSONDecoder().decode(
                AssertionChallengeResponseBody.self,
                from: responseBodyData,
            )
        } catch {
            throw OWSAssertionError("Failed to decode response body fetching assertion challenge! \(error)", logger: logger)
        }

        return responseBody.challenge
    }

    // MARK: - Persistence

    private enum StoreKeys {
        static let keyId = "keyId"
    }

    /// Returns the identifier of a key for this device that has previously
    /// passed attestation, if one exists.
    private func readAttestedKeyId() async -> String? {
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

    private func wipeAttestedKeyId() async {
        await db.awaitableWrite { tx in
            kvStore.removeValue(forKey: StoreKeys.keyId, transaction: tx)
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
        let urlPath = "v1/devicecheck/assert"
        var request = TSRequest(
            url: URL(string: "\(urlPath)?keyId=\(keyIdData.asBase64Url)&request=\(assertedRequestData.asBase64Url)")!,
            method: "POST",
            body: .data(assertion),
        )
        request.applyRedactionStrategy(.redactURL(replacement: "\(urlPath)?[REDACTED]"))
        request.headers["Content-Type"] = "application/octet-stream"
        return request
    }

    static func getAttestationChallenge() -> TSRequest {
        return TSRequest(
            url: URL(string: "v1/devicecheck/attest")!,
            method: "GET",
            parameters: nil,
        )
    }

    static func attestAndRegisterKey(
        keyIdData: Data,
        keyAttestation: Data,
    ) -> TSRequest {
        let urlPath = "v1/devicecheck/attest"
        var request = TSRequest(
            url: URL(string: "\(urlPath)?keyId=\(keyIdData.asBase64Url)")!,
            method: "PUT",
            body: .data(keyAttestation),
        )
        request.applyRedactionStrategy(.redactURL(replacement: "\(urlPath)?[REDACTED]"))
        request.headers["Content-Type"] = "application/octet-stream"
        return request
    }
}
