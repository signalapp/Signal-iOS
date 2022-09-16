//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import Foundation

public extension TSAccountManager {

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
    var isRegisteredPrimaryDevice: Bool {
        isRegistered && isPrimaryDevice
    }

    @objc
    var isPrimaryDevice: Bool {
        storedDeviceId() == OWSDevicePrimaryDeviceId
    }

    @objc
    func isPrimaryDevice(transaction: SDSAnyReadTransaction) -> Bool {
        storedDeviceId(with: transaction) == OWSDevicePrimaryDeviceId
    }

    @objc
    var storedServerUsername: String? {
        guard let serviceIdentifier = self.localAddress?.serviceIdentifier else {
            return nil
        }

        return isRegisteredPrimaryDevice ? serviceIdentifier : "\(serviceIdentifier).\(storedDeviceId())"
    }

    @objc
    func localAccountId(transaction: SDSAnyReadTransaction) -> AccountId? {
        guard let localAddress = localAddress else { return nil }
        return OWSAccountIdFinder.accountId(forAddress: localAddress, transaction: transaction)
    }

    // MARK: - Account Attributes & Capabilities

    private static var needsAccountAttributesUpdateKey: String { "TSAccountManager_NeedsAccountAttributesUpdateKey" }

    // Sets the flag to force an account attributes update,
    // then returns a promise for the current attempt.
    @objc
    @available(swift, obsoleted: 1.0)
    @discardableResult
    func updateAccountAttributes() -> AnyPromise {
        return AnyPromise(updateAccountAttributes())
    }

    func updateAccountAttributes() -> Promise<Void> {
        Self.databaseStorage.write { transaction in
            self.keyValueStore.setDate(Date(),
                                       key: Self.needsAccountAttributesUpdateKey,
                                       transaction: transaction)
        }
        return updateAccountAttributesIfNecessaryAttempt()
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
            updateAccountAttributesIfNecessaryAttempt()
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
    private func updateAccountAttributesIfNecessaryAttempt() -> Promise<Void> {
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
        let currentAppVersion4 = appVersion.currentAppVersion4

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
        let promise: Promise<Void> = firstly(on: .global()) { () -> Promise<Void> in
            let client = SignalServiceRestClient()
            return (self.isPrimaryDevice
                        ? client.updatePrimaryDeviceAccountAttributes()
                        : client.updateSecondaryDeviceCapabilities())
        }.then(on: DispatchQueue.global()) {
            self.profileManager.fetchLocalUsersProfilePromise()
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
        registerForPushNotifications(pushToken: pushToken,
                                     voipToken: voipToken,
                                     success: success,
                                     failure: failure,
                                     remainingRetries: 3)
    }

    @objc
    open func registerForPushNotifications(pushToken: String,
                                           voipToken: String?,
                                           success: @escaping () -> Void,
                                           failure: @escaping (Error) -> Void,
                                           remainingRetries: Int) {

        let request = OWSRequestFactory.registerForPushRequest(withPushIdentifier: pushToken,
                                                               voipIdentifier: voipToken)
        firstly {
            networkManager.makePromise(request: request)
        }.done(on: .global()) { _ in
            success()
        }.catch(on: .global()) { error in
            if remainingRetries > 0 {
                self.registerForPushNotifications(pushToken: pushToken,
                                                  voipToken: voipToken,
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
        }.map(on: .global()) { response in
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
        }.catch(on: .global()) { error in
            failure(Self.processRegistrationError(error))
        }
    }

    @objc
    open func verifyChangePhoneNumber(request: TSRequest,
                                      success: @escaping (Any?) -> Void,
                                      failure: @escaping (Error) -> Void) {
        firstly {
            networkManager.makePromise(request: request)
        }.map(on: .global()) { response in
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
        }.catch(on: .global()) { error in
            failure(Self.processRegistrationError(error))
        }
    }

    private static func processRegistrationError(_ error: Error) -> Error {
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
        }.done(on: .global()) { _ in
            Logger.verbose("Successfully unregistered.")
            success()

            // This is called from `[AppSettingsViewController proceedToUnregistration]` whose
            // success handler calls `[Environment resetAppData]`.
            // This method, after calling that success handler, fires
            // `RegistrationStateDidChangeNotification` which is only safe to fire after
            // the data store is reset.

            Self.tsAccountManager.postRegistrationStateDidChangeNotification()
        }.catch(on: .global()) { error in
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
