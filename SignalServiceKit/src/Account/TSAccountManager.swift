//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public extension TSAccountManager {

    // MARK: - Initialization

    @objc
    internal func warmCaches() {
        owsAssertDebug(GRDBSchemaMigrator.areMigrationsComplete)

        loadAccountStateWithSneakyTransaction().log()
    }

    // MARK: -

    @objc
    private class func getLocalThread(transaction: SDSAnyReadTransaction) -> TSThread? {
        guard let localAddress = self.localAddress(with: transaction) else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        return TSContactThread.getWithContactAddress(localAddress, transaction: transaction)
    }

    @objc
    private class func getLocalThreadWithSneakyTransaction() -> TSThread? {
        return databaseStorage.read { transaction in
            return getLocalThread(transaction: transaction)
        }
    }

    @objc
    class func getOrCreateLocalThread(transaction: SDSAnyWriteTransaction) -> TSThread? {
        guard let localAddress = self.localAddress(with: transaction) else {
            owsFailDebug("Missing localAddress.")
            return nil
        }
        return TSContactThread.getOrCreateThread(withContactAddress: localAddress, transaction: transaction)
    }

    @objc
    class func getOrCreateLocalThreadWithSneakyTransaction() -> TSThread? {
        assert(!Thread.isMainThread)

        if let thread = getLocalThreadWithSneakyTransaction() {
            return thread
        }

        return databaseStorage.write { transaction in
            return getOrCreateLocalThread(transaction: transaction)
        }
    }

    @objc
    var registrationState: OWSRegistrationState {
        registrationState(for: getOrLoadAccountStateWithSneakyTransaction())
    }

    @objc
    func registrationState(transaction: SDSAnyReadTransaction) -> OWSRegistrationState {
        registrationState(for: getOrLoadAccountState(with: transaction))
    }

    private func registrationState(for state: TSAccountState) -> OWSRegistrationState {
        if state.isRegistered {
            if isDeregistered(state: state) {
                if state.isReregistering {
                    return .reregistering
                }
                return .deregistered
            }
            return .registered
        }
        return .unregistered
    }

    func localIdentifiers(transaction: SDSAnyReadTransaction) -> LocalIdentifiers? {
        getOrLoadAccountState(with: transaction).localIdentifiers
    }

    @objc
    var isRegistered: Bool {
        getOrLoadAccountStateWithSneakyTransaction().isRegistered
    }

    @objc
    func isRegistered(transaction: SDSAnyReadTransaction) -> Bool {
        getOrLoadAccountState(with: transaction).isRegistered
    }

    @objc
    var isRegisteredAndReady: Bool {
        registrationState == .registered
    }

    @objc
    func isRegisteredAndReady(transaction: SDSAnyReadTransaction) -> Bool {
        registrationState(transaction: transaction) == .registered
    }

    @objc
    var isRegisteredPrimaryDevice: Bool {
        isRegistered && isPrimaryDevice
    }

    @objc
    var isPrimaryDevice: Bool {
        storedDeviceId == OWSDevice.primaryDeviceId
    }

    @objc
    func isPrimaryDevice(transaction: SDSAnyReadTransaction) -> Bool {
        storedDeviceId(transaction: transaction) == OWSDevice.primaryDeviceId
    }

    @objc
    var storedServerUsername: String? {
        guard let serviceId = self.localAddress?.uuidString else {
            return nil
        }

        return isRegisteredPrimaryDevice ? serviceId : "\(serviceId).\(storedDeviceId)"
    }

    @objc
    func localAccountId(transaction: SDSAnyReadTransaction) -> AccountId? {
        guard let localAddress = localAddress else { return nil }
        return OWSAccountIdFinder.accountId(forAddress: localAddress, transaction: transaction)
    }

    @objc
    func registrationDate(transaction: SDSAnyReadTransaction) -> Date? {
        getOrLoadAccountState(with: transaction).registrationDate
    }

    @objc
    var isOnboarded: Bool {
        getOrLoadAccountStateWithSneakyTransaction().isOnboarded
    }

    @objc
    func isOnboarded(transaction: SDSAnyReadTransaction) -> Bool {
        getOrLoadAccountState(with: transaction).isOnboarded
    }

    @objc
    var storedServerAuthToken: String? {
        getOrLoadAccountStateWithSneakyTransaction().serverAuthToken
    }

    @objc
    func storedServerAuthToken(transaction: SDSAnyReadTransaction) -> String? {
        getOrLoadAccountState(with: transaction).serverAuthToken
    }

    @objc
    var storedDeviceId: UInt32 {
        getOrLoadAccountStateWithSneakyTransaction().deviceId
    }

    @objc
    func storedDeviceId(transaction: SDSAnyReadTransaction) -> UInt32 {
        getOrLoadAccountState(with: transaction).deviceId
    }

    @objc
    var reregistrationPhoneNumber: String? {
        getOrLoadAccountStateWithSneakyTransaction().reregistrationPhoneNumber
    }

    @objc
    var reregistrationUUID: UUID? {
        getOrLoadAccountStateWithSneakyTransaction().reregistrationUUID
    }

    @objc
    var isReregistering: Bool {
        getOrLoadAccountStateWithSneakyTransaction().isReregistering
    }

    @objc
    var isTransferInProgress: Bool {
        get { getOrLoadAccountStateWithSneakyTransaction().isTransferInProgress }
        set {
            if newValue == isTransferInProgress {
                return
            }
            databaseStorage.write { transaction in
                objc_sync_enter(self)
                defer { objc_sync_exit(self) }

                keyValueStore.setBool(newValue, key: TSAccountManager_IsTransferInProgressKey, transaction: transaction)
                loadAccountState(with: transaction)
            }
            postRegistrationStateDidChangeNotification()
        }
    }

    @objc
    var wasTransferred: Bool {
        get { getOrLoadAccountStateWithSneakyTransaction().wasTransferred }
        set {
            databaseStorage.write { transaction in
                objc_sync_enter(self)
                defer { objc_sync_exit(self) }

                keyValueStore.setBool(newValue, key: TSAccountManager_WasTransferredKey, transaction: transaction)
                loadAccountState(with: transaction)
            }
            postRegistrationStateDidChangeNotification()
        }
    }

    @objc
    func storeLocalNumber(
        _ newLocalNumber: E164ObjC,
        aci newAci: ServiceIdObjC,
        pni newPni: ServiceIdObjC?,
        transaction: SDSAnyWriteTransaction
    ) {
        func setIdentifier(_ newValue: String, for key: String) {
            let oldValue = keyValueStore.getString(key, transaction: transaction)
            if oldValue != newValue {
                Logger.info("\(key): \(oldValue ?? "nil") -> \(newValue)")
            }
            keyValueStore.setString(newValue, key: key, transaction: transaction)
        }

        do {
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }

            setIdentifier(newLocalNumber.stringValue, for: TSAccountManager_RegisteredNumberKey)
            setIdentifier(newAci.uuidValue.uuidString, for: TSAccountManager_RegisteredUUIDKey)
            if let newPni {
                setIdentifier(newPni.uuidValue.uuidString, for: TSAccountManager_RegisteredPNIKey)
            }

            keyValueStore.setDate(Date(), key: TSAccountManager_RegistrationDateKey, transaction: transaction)
            keyValueStore.removeValue(forKey: TSAccountManager_IsDeregisteredKey, transaction: transaction)
            keyValueStore.removeValue(forKey: TSAccountManager_ReregisteringPhoneNumberKey, transaction: transaction)
            keyValueStore.removeValue(forKey: TSAccountManager_ReregisteringUUIDKey, transaction: transaction)

            // Discard sender certificates whenever local phone number changes.
            udManager.removeSenderCertificates(transaction: transaction)
            identityManager.clearShouldSharePhoneNumberForEveryone(transaction: transaction)
            versionedProfiles.clearProfileKeyCredentials(transaction: transaction)
            groupsV2.clearTemporalCredentials(transaction: transaction)

            loadAccountState(with: transaction)

            phoneNumberAwaitingVerification = nil
            uuidAwaitingVerification = nil
            pniAwaitingVerification = nil
        }

        didStoreLocalNumber?(LocalIdentifiersObjC(LocalIdentifiers(
            aci: newAci.wrappedValue,
            pni: newPni?.wrappedValue,
            phoneNumber: newLocalNumber.stringValue
        )))

        let localRecipient = DependenciesBridge.shared.recipientMerger.applyMergeForLocalAccount(
            aci: newAci.wrappedValue,
            pni: newPni?.wrappedValue,
            phoneNumber: newLocalNumber.wrappedValue,
            tx: transaction.asV2Write
        )
        localRecipient.markAsRegistered(transaction: transaction)
    }

    // MARK: - Deregistration

    @objc
    var isDeregistered: Bool {
        get { isDeregistered(state: getOrLoadAccountStateWithSneakyTransaction()) }
        set {
            if newValue && !isRegisteredAndReady {
                Logger.warn("Ignoring; not registered and ready.")
                return
            }
            if getOrLoadAccountStateWithSneakyTransaction().isDeregistered == newValue {
                return
            }
            Logger.warn("Updating isDeregistered \(newValue)")
            databaseStorage.write { transaction in
                objc_sync_enter(self)
                defer { objc_sync_exit(self) }

                if getOrLoadAccountState(with: transaction).isDeregistered == newValue {
                    return
                }

                keyValueStore.setBool(newValue, key: TSAccountManager_IsDeregisteredKey, transaction: transaction)
                loadAccountState(with: transaction)

                if newValue {
                    notificationPresenter?.notifyUserOfDeregistration(transaction: transaction)
                }
            }
            postRegistrationStateDidChangeNotification()
        }
    }

    /// Checks if the account is "deregistered".
    ///
    /// An account is deregistered if a device transfer is in progress, a device
    /// transfer was just completed to another device, or we received an HTTP
    /// 401/403 error that indicates we're no longer registered.
    ///
    /// If an account is deregistered due to an HTTP 401/403 error, the user
    /// should complete re-registration to re-mark the account as "registered".
    @objc
    func isDeregistered(transaction: SDSAnyReadTransaction) -> Bool {
        return isDeregistered(state: getOrLoadAccountState(with: transaction))
    }

    private func isDeregistered(state: TSAccountState) -> Bool {
        // An in progress transfer is treated as being deregistered.
        return state.isTransferInProgress || state.wasTransferred || state.isDeregistered
    }

    // MARK: - Account Attributes & Capabilities

    private static var aciRegistrationIdKey: String { "TSStorageLocalRegistrationId" }
    private static var pniRegistrationIdKey: String { "TSStorageLocalPniRegistrationId" }
    private static var needsAccountAttributesUpdateKey: String { "TSAccountManager_NeedsAccountAttributesUpdateKey" }

    @objc
    func getOrGenerateRegistrationId(transaction: SDSAnyWriteTransaction) -> UInt32 {
        getOrGenerateRegistrationId(
            forStorageKey: Self.aciRegistrationIdKey,
            nounForLogging: "ACI registration ID",
            transaction: transaction
        )
    }

    @objc
    func getOrGeneratePniRegistrationId(transaction: SDSAnyWriteTransaction) -> UInt32 {
        getOrGenerateRegistrationId(
            forStorageKey: Self.pniRegistrationIdKey,
            nounForLogging: "PNI registration ID",
            transaction: transaction
        )
    }

    /// Set the PNI registration ID.
    ///
    /// Values passed here should have already been provided to the service.
    func setPniRegistrationId(
        newRegistrationId: UInt32,
        transaction: SDSAnyWriteTransaction
    ) {
        keyValueStore.setUInt32(
            newRegistrationId,
            key: Self.pniRegistrationIdKey,
            transaction: transaction
        )
    }

    private func getOrGenerateRegistrationId(
        forStorageKey key: String,
        nounForLogging: String,
        transaction: SDSAnyWriteTransaction
    ) -> UInt32 {
        let storedId = keyValueStore.getUInt32(key, transaction: transaction) ?? 0
        if storedId == 0 {
            let result = Self.generateRegistrationId()
            Logger.info("Generated a new \(nounForLogging): \(result)")
            keyValueStore.setUInt32(result, key: key, transaction: transaction)
            return result
        } else {
            return storedId
        }
    }

    /// Generate a registration ID, suitable for regular registration IDs or PNI ones.
    static func generateRegistrationId() -> UInt32 { UInt32.random(in: 1...0x3fff) }

    // Sets the flag to force an account attributes update,
    // then returns a promise for the current attempt.
    @objc
    @available(swift, obsoleted: 1.0)
    @discardableResult
    func updateAccountAttributes() -> AnyPromise {
        return AnyPromise(updateAccountAttributes())
    }

    @discardableResult
    func updateAccountAttributes(authedAccount: AuthedAccount = .implicit()) -> Promise<Void> {
        Self.databaseStorage.write { transaction in
            self.keyValueStore.setDate(Date(),
                                       key: Self.needsAccountAttributesUpdateKey,
                                       transaction: transaction)
        }
        return updateAccountAttributesIfNecessaryAttempt(authedAccount: authedAccount)
    }

    // Sets the flag to force an account attributes update,
    // then initiates an attempt.
    @objc
    func updateAccountAttributes(transaction: SDSAnyWriteTransaction) {
        self.keyValueStore.setDate(Date(),
                                   key: Self.needsAccountAttributesUpdateKey,
                                   transaction: transaction)
        transaction.addAsyncCompletionOffMain {
            self.updateAccountAttributesIfNecessary()
        }
    }

    @objc
    func updateAccountAttributesIfNecessary() {
        firstly {
            updateAccountAttributesIfNecessaryAttempt(authedAccount: .implicit())
        }.done(on: DispatchQueue.global()) { _ in
            Logger.info("Success.")
        }.catch(on: DispatchQueue.global()) { error in
            Logger.warn("Error: \(error).")
        }
    }

    // Performs a single attempt to update the account attributes.
    //
    // We need to update our account attributes in a variety of scenarios:
    //
    // * Every time the user upgrades to a new version.
    // * Whenever the device capabilities change.
    //   This is useful during development and internal testing when
    //   moving between builds with different device capabilities.
    // * Whenever another component of the system requests an attribute,
    //   update e.g. during registration, after rotating the profile key, etc.
    //
    // The client will retry failed attempts:
    //
    // * On launch.
    // * When reachability changes.
    private func updateAccountAttributesIfNecessaryAttempt(authedAccount: AuthedAccount) -> Promise<Void> {
        guard isRegisteredAndReady else {
            Logger.info("Aborting; not registered and ready.")
            return Promise.value(())
        }
        guard AppReadiness.isAppReady else {
            Logger.info("Aborting; app is not ready.")
            return Promise.value(())
        }

        let deviceCapabilitiesKey = "deviceCapabilities"
        let appVersionKey = "appVersion"

        let currentDeviceCapabilities: [String: NSNumber] = OWSRequestFactory.deviceCapabilitiesForLocalDevice()
        let currentAppVersion4 = AppVersion.shared.currentAppVersion4

        var lastAttributeRequest: Date?
        let shouldUpdateAttributes = Self.databaseStorage.read { (transaction: SDSAnyReadTransaction) -> Bool in
            // Check if there's been a request for an attributes update.
            lastAttributeRequest = self.keyValueStore.getDate(Self.needsAccountAttributesUpdateKey,
                                                              transaction: transaction)
            if lastAttributeRequest != nil {
                return true
            }
            // Check if device capabilities have changed.
            let lastDeviceCapabilities = self.keyValueStore.getObject(forKey: deviceCapabilitiesKey,
                                                                      transaction: transaction) as? [String: NSNumber]
            guard lastDeviceCapabilities == currentDeviceCapabilities else {
                return true
            }
            // Check if the app version has changed.
            let lastAppVersion = self.keyValueStore.getString(appVersionKey, transaction: transaction)
            guard lastAppVersion == currentAppVersion4 else {
                return true
            }
            Logger.info("Skipping; lastAppVersion: \(String(describing: lastAppVersion)), currentAppVersion4: \(currentAppVersion4).")
            return false
        }
        guard shouldUpdateAttributes else {
            return Promise.value(())
        }
        Logger.info("Updating account attributes.")
        let promise: Promise<Void> = firstly(on: DispatchQueue.global()) { () -> Promise<Void> in
            let client = SignalServiceRestClient()
            return (self.isPrimaryDevice
                        ? client.updatePrimaryDeviceAccountAttributes()
                        : client.updateSecondaryDeviceCapabilities())
        }.then(on: DispatchQueue.global()) {
            self.profileManager.fetchLocalUsersProfilePromise(authedAccount: authedAccount)
        }.map(on: DispatchQueue.global()) { _ -> Void in
            Self.databaseStorage.write { transaction in
                self.keyValueStore.setObject(currentDeviceCapabilities,
                                             key: deviceCapabilitiesKey,
                                             transaction: transaction)
                self.keyValueStore.setString(currentAppVersion4,
                                             key: appVersionKey,
                                             transaction: transaction)

                // Clear the update request unless a new update has been requested
                // while this update was in flight.
                if lastAttributeRequest != nil,
                   lastAttributeRequest == self.keyValueStore.getDate(Self.needsAccountAttributesUpdateKey,
                                                                      transaction: transaction) {
                    self.keyValueStore.removeValue(forKey: Self.needsAccountAttributesUpdateKey,
                                                   transaction: transaction)
                }
            }

            // Primary devices should sync their configuration whenever they
            // update their account attributes.
            if self.isRegisteredPrimaryDevice {
                self.syncManager.sendConfigurationSyncMessage()
            }
        }
        return promise
    }
}

// MARK: -

extension TSAccountManager {
    @objc
    open func registerForPushNotifications(pushToken: String,
                                           voipToken: String?,
                                           success: @escaping () -> Void,
                                           failure: @escaping (Error) -> Void) {
        let request = OWSRequestFactory.registerForPushRequest(withPushIdentifier: pushToken,
                                                               voipIdentifier: voipToken)
        registerForPushNotifications(request: request,
                                     success: success,
                                     failure: failure)
    }

    @objc
    open func registerForPushNotifications(request: TSRequest,
                                           success: @escaping () -> Void,
                                           failure: @escaping (Error) -> Void) {
        registerForPushNotifications(request: request,
                                     success: success,
                                     failure: failure,
                                     remainingRetries: 3)
    }

    @objc
    open func registerForPushNotifications(request: TSRequest,
                                           success: @escaping () -> Void,
                                           failure: @escaping (Error) -> Void,
                                           remainingRetries: Int) {
        firstly {
            networkManager.makePromise(request: request)
        }.done(on: DispatchQueue.global()) { _ in
            success()
        }.catch(on: DispatchQueue.global()) { error in
            if remainingRetries > 0 {
                self.registerForPushNotifications(request: request,
                                                  success: success,
                                                  failure: failure,
                                                  remainingRetries: remainingRetries - 1)
            } else {
                owsFailDebugUnlessNetworkFailure(error)
                failure(error)
            }
        }
    }

    @objc
    open func verifyRegistration(request: TSRequest,
                                 success: @escaping (Any?) -> Void,
                                 failure: @escaping (Error) -> Void) {
        firstly {
            networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            let statusCode = response.responseStatusCode

            switch statusCode {
            case 200, 204:
                guard let json = response.responseBodyJson else {
                    throw OWSAssertionError("Missing or invalid JSON")
                }
                Logger.info("Verification code accepted.")
                success(json)
            default:
                Logger.warn("Unexpected status while verifying code: \(statusCode)")
                failure(OWSGenericError("Unexpected status while verifying code: \(statusCode)"))
            }
        }.catch(on: DispatchQueue.global()) { error in
            failure(Self.processRegistrationError(error))
        }
    }

    @objc
    open func verifyChangePhoneNumber(request: TSRequest,
                                      success: @escaping (Any?) -> Void,
                                      failure: @escaping (Error) -> Void) {
        firstly {
            networkManager.makePromise(request: request)
        }.map(on: DispatchQueue.global()) { response in
            let statusCode = response.responseStatusCode

            switch statusCode {
            case 200, 204:
                guard let json = response.responseBodyJson else {
                    throw OWSAssertionError("Missing or invalid JSON")
                }
                Logger.info("Verification code accepted.")
                success(json)
            default:
                Logger.warn("Unexpected status while verifying code: \(statusCode)")
                failure(OWSGenericError("Unexpected status while verifying code: \(statusCode)"))
            }
        }.catch(on: DispatchQueue.global()) { error in
            failure(Self.processRegistrationError(error))
        }
    }

    public static func processRegistrationError(_ error: Error) -> Error {
        Logger.warn("Error: \(error)")

        let statusCode = error.httpStatusCode ?? 0

        switch statusCode {
        case 403:
            let message = OWSLocalizedString("REGISTRATION_VERIFICATION_FAILED_WRONG_CODE_DESCRIPTION",
                                            comment: "Error message indicating that registration failed due to a missing or incorrect verification code.")
            return OWSError(error: .userError,
                            description: message,
                            isRetryable: false)
        case 409:
            let message = OWSLocalizedString("REGISTRATION_TRANSFER_AVAILABLE_DESCRIPTION",
                                            comment: "Error message indicating that device transfer from another device might be possible.")
            return OWSError(error: .registrationTransferAvailable,
                            description: message,
                            isRetryable: false)
        case 413, 429:
            // In the case of the "rate limiting" error, we want to show the
            // "recovery suggestion", not the error's "description."
            let recoverySuggestion = OWSLocalizedString("REGISTER_RATE_LIMITING_BODY", comment: "")
            return OWSError(error: .userError,
                            description: recoverySuggestion,
                            isRetryable: false)
        case 423:
            Logger.error("2FA PIN required: \(error)")

            if let httpResponseHeaders = error.httpResponseHeaders {
                Logger.verbose("httpResponseHeaders: \(httpResponseHeaders.headers)")
            }

            guard let json = error.httpResponseJson as? [String: Any] else {
                return OWSAssertionError("Invalid response.")
            }

            // Check if we received KBS credentials, if so pass them on.
            // This should only ever be returned if the user was using registration lock v2
            guard let backupCredentials = json["backupCredentials"] as? [String: Any] else {
                return OWSAssertionError("Invalid response.")
            }

            do {
                let auth = try RemoteAttestation.Auth(authParams: backupCredentials)
                return RegistrationMissing2FAPinError(remoteAttestationAuth: auth)
            } catch {
                owsFailDebug("Remote attestation auth could not be parsed: \(json).")
                return OWSAssertionError("Invalid response.")
            }
        default:
            owsFailDebugUnlessNetworkFailure(error)
            return error
        }
    }
}

// MARK: -

public extension TSAccountManager {
    @objc
    static func unregisterTextSecure(success: @escaping () -> Void,
                                     failure: @escaping (Error) -> Void) {
        let request = OWSRequestFactory.unregisterAccountRequest()
        firstly {
            Self.networkManager.makePromise(request: request)
        }.done(on: DispatchQueue.global()) { _ in
            Logger.verbose("Successfully unregistered.")
            success()

            // This is called from `[AppSettingsViewController proceedToUnregistration]` whose
            // success handler calls `[Environment resetAppData]`.
            // This method, after calling that success handler, fires
            // `RegistrationStateDidChangeNotification` which is only safe to fire after
            // the data store is reset.

            Self.tsAccountManager.postRegistrationStateDidChangeNotification()
        }.catch(on: DispatchQueue.global()) { error in
            owsFailDebugUnlessNetworkFailure(error)
            failure(error)
        }
    }

    // MARK: - Notifications

    @objc
    func postRegistrationStateDidChangeNotification() {
        NotificationCenter.default.postNotificationNameAsync(
            .registrationStateDidChange,
            object: nil
        )
    }

    @objc
    func postOnboardingStateDidChangeNotification() {
        NotificationCenter.default.postNotificationNameAsync(
            .onboardingStateDidChange,
            object: nil
        )
    }
}

// MARK: -

@objc
public class RegistrationMissing2FAPinError: NSObject, Error, IsRetryableProvider, UserErrorDescriptionProvider {

    public let remoteAttestationAuth: RemoteAttestation.Auth

    required init(remoteAttestationAuth: RemoteAttestation.Auth) {
        self.remoteAttestationAuth = remoteAttestationAuth
    }

    // NSError bridging: the error code within the given domain.
    public var errorUserInfo: [String: Any] {
        var result = [String: Any]()
        result[NSLocalizedDescriptionKey] = localizedDescription
        return result
    }

    public var localizedDescription: String {
        OWSLocalizedString("REGISTRATION_VERIFICATION_FAILED_WRONG_PIN",
                                                     comment: "Error message indicating that registration failed due to a missing or incorrect 2FA PIN.")
    }

    // MARK: - IsRetryableProvider

    public var isRetryableProvider: Bool { false }
}

public extension TSAccountManager {

    @objc(clearKBSKeysWithTransaction:)
    func clearKBSKeys(with transaction: SDSAnyWriteTransaction) {
        DependenciesBridge.shared.keyBackupService.clearKeys(transaction: transaction.asV2Write)
    }
}

// MARK: - Phone number discoverability

public extension TSAccountManager {
    /// This method may open a transaction.
    func hasDefinedIsDiscoverableByPhoneNumber() -> Bool {
        getOrLoadAccountStateWithSneakyTransaction().hasDefinedIsDiscoverableByPhoneNumber
    }

    func hasDefinedIsDiscoverableByPhoneNumber(with transaction: SDSAnyReadTransaction) -> Bool {
        getOrLoadAccountState(with: transaction).hasDefinedIsDiscoverableByPhoneNumber
    }

    /// This method may open a transaction.
    @objc
    func isDiscoverableByPhoneNumber() -> Bool {
        getOrLoadAccountStateWithSneakyTransaction().isDiscoverableByPhoneNumber
    }

    func isDiscoverableByPhoneNumber(with transaction: SDSAnyReadTransaction) -> Bool {
        getOrLoadAccountState(with: transaction).isDiscoverableByPhoneNumber
    }

    func lastSetIsDiscoverablyByPhoneNumberAt(with transaction: SDSAnyReadTransaction) -> Date {
        getOrLoadAccountState(with: transaction).lastSetIsDiscoverableByPhoneNumberAt
    }

    func setIsDiscoverableByPhoneNumber(
        _ isDiscoverableByPhoneNumber: Bool,
        updateStorageService: Bool,
        authedAccount: AuthedAccount,
        transaction: SDSAnyWriteTransaction
    ) {
        guard FeatureFlags.phoneNumberDiscoverability else {
            return
        }

        performWithSynchronizedSelf {
            keyValueStore.setBool(
                isDiscoverableByPhoneNumber,
                key: TSAccountManager_IsDiscoverableByPhoneNumberKey,
                transaction: transaction
            )

            keyValueStore.setDate(
                Date(),
                key: TSAccountManager_LastSetIsDiscoverableByPhoneNumberKey,
                transaction: transaction
            )

            loadAccountState(with: transaction)
        }

        transaction.addAsyncCompletionOffMain {
            self.updateAccountAttributes(authedAccount: authedAccount)

            if updateStorageService {
                self.storageServiceManager.recordPendingLocalAccountUpdates()
            }
        }
    }

    private func performWithSynchronizedSelf(block: () -> Void) {
        objc_sync_enter(self)
        block()
        objc_sync_exit(self)
    }
}
