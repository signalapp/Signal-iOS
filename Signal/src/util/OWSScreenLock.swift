//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

import Foundation
import LocalAuthentication

@objc public class OWSScreenLock: NSObject {

    let TAG = "[OWSScreenLock]"

    public enum OWSScreenLockOutcome {
        case success
        case cancel
        case failure(error:String)
    }

    @objc public static let ScreenLockDidChange = Notification.Name("ScreenLockDidChange")

    let primaryStorage: OWSPrimaryStorage
    let dbConnection: YapDatabaseConnection

    private let OWSScreenLock_Collection = "OWSScreenLock_Collection"
    private let OWSScreenLock_Key_IsScreenLockEnabled = "OWSScreenLock_Key_IsScreenLockEnabled"
    private let OWSScreenLock_Key_ScreenLockTimeoutSeconds = "OWSScreenLock_Key_ScreenLockTimeoutSeconds"

    // MARK - Singleton class

    @objc(sharedManager)
    public static let shared = OWSScreenLock()

    private override init() {
        self.primaryStorage = OWSPrimaryStorage.shared()
        self.dbConnection = self.primaryStorage.newDatabaseConnection()

        super.init()

        SwiftSingletons.register(self)
    }

    // MARK: - Properties

    @objc public func isScreenLockEnabled() -> Bool {
        AssertIsOnMainThread()

        if !OWSStorage.isStorageReady() {
            owsFail("\(TAG) accessed screen lock state before storage is ready.")
            return false
        }

        return self.dbConnection.bool(forKey: OWSScreenLock_Key_IsScreenLockEnabled, inCollection: OWSScreenLock_Collection, defaultValue: false)
    }

    private func setIsScreenLockEnabled(value: Bool) {
        AssertIsOnMainThread()
        assert(OWSStorage.isStorageReady())

        self.dbConnection.setBool(value, forKey: OWSScreenLock_Key_IsScreenLockEnabled, inCollection: OWSScreenLock_Collection)

        NotificationCenter.default.postNotificationNameAsync(OWSScreenLock.ScreenLockDidChange, object: nil)
    }

    @objc public func screenLockTimeout() -> TimeInterval {
        AssertIsOnMainThread()

        if !OWSStorage.isStorageReady() {
            owsFail("\(TAG) accessed screen lock state before storage is ready.")
            return 0
        }

        return self.dbConnection.double(forKey: OWSScreenLock_Key_ScreenLockTimeoutSeconds, inCollection: OWSScreenLock_Collection, defaultValue: 0)
    }

    private func setIsScreenLockEnabled(value: TimeInterval) {
        AssertIsOnMainThread()
        assert(OWSStorage.isStorageReady())

        self.dbConnection.setDouble(value, forKey: OWSScreenLock_Key_ScreenLockTimeoutSeconds, inCollection: OWSScreenLock_Collection)

        NotificationCenter.default.postNotificationNameAsync(OWSScreenLock.ScreenLockDidChange, object: nil)
    }

    // MARK: - Methods

//    @objc public func isScreenLockSupported() -> Bool {
//        AssertIsOnMainThread()
//
//        let context = screenLockContext()
//
//        var authError: NSError?
//        let result = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError)
//        guard authError == nil else {
//            Logger.error("\(TAG) could not determine if screen lock is supported: \(String(describing: authError))")
//            return false
//        }
//        return result
//    }

//    @objc public func supportedBiometryType() -> LABiometryType {
//        AssertIsOnMainThread()
//
//        let context = screenLockContext()
//
//        var authError: NSError?
//        let result = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError)
//        guard authError == nil else {
//            Logger.error("\(TAG) could not determine if screen lock is supported: \(String(describing: authError))")
//            return .none
//        }
//        guard let biometryType = context.biometryType else {
//            return .none
//        }
//        return biometryType
//    }

    // On failure, completion is called with an error argument.
    // On success or cancel, completion is called with nil argument.
    // Success and cancel can be differentiated by consulting
    // isScreenLockEnabled.
    @objc public func tryToEnableScreenLock(completion: @escaping ((Error?) -> Void)) {
        tryToVerifyLocalAuthentication(defaultReason: NSLocalizedString("SCREEN_LOCK_REASON_ENABLE_SCREEN_LOCK",
                                                                        comment: "Description of how and why Signal iOS uses Touch ID/Face ID to enable 'screen lock'."),
                                       touchIdReason: NSLocalizedString("SCREEN_LOCK_REASON_ENABLE_SCREEN_LOCK_TOUCH_ID",
                                                                        comment: "Description of how and why Signal iOS uses Touch ID to enable 'screen lock'."),
                                       faceIdReason: NSLocalizedString("SCREEN_LOCK_REASON_ENABLE_SCREEN_LOCK_FACE_ID",
                                                                       comment: "Description of how and why Signal iOS uses Face ID to enable 'screen lock'."),

                                       completion: { (outcome: OWSScreenLockOutcome) in
                                        AssertIsOnMainThread()

                                        switch outcome {
                                        case .failure(let error):
                                            completion(self.authenticationError(errorDescription: error))
                                        case .success:
                                            self.setIsScreenLockEnabled(value: true)
                                            completion(nil)
                                        case .cancel:
                                            completion(nil)
                                        }
        })
    }

    // On failure, completion is called with an error argument.
    // On success or cancel, completion is called with nil argument.
    // Success and cancel can be differentiated by consulting
    // isScreenLockEnabled.
    @objc public func tryToDisableScreenLock(completion: @escaping ((Error?) -> Void)) {
        tryToVerifyLocalAuthentication(defaultReason: NSLocalizedString("SCREEN_LOCK_REASON_DISABLE_SCREEN_LOCK",
                                                                        comment: "Description of how and why Signal iOS uses Touch ID/Face ID to disable 'screen lock'."),
                                       touchIdReason: NSLocalizedString("SCREEN_LOCK_REASON_DISABLE_SCREEN_LOCK_TOUCH_ID",
                                                                        comment: "Description of how and why Signal iOS uses Touch ID to disable 'screen lock'."),
                                       faceIdReason: NSLocalizedString("SCREEN_LOCK_REASON_DISABLE_SCREEN_LOCK_FACE_ID",
                                                                       comment: "Description of how and why Signal iOS uses Face ID to disable 'screen lock'."),

                                       completion: { (outcome: OWSScreenLockOutcome) in
                                        AssertIsOnMainThread()

                                        switch outcome {
                                        case .failure(let error):
                                            completion(self.authenticationError(errorDescription: error))
                                        case .success:
                                            self.setIsScreenLockEnabled(value: false)
                                            completion(nil)
                                        case .cancel:
                                            completion(nil)
                                        }
        })
    }

    @objc public func tryToUnlockScreenLock(success: @escaping (() -> Void),
                                            failure: @escaping ((Error) -> Void),
                                            cancel: @escaping (() -> Void)) {
        tryToVerifyLocalAuthentication(defaultReason: NSLocalizedString("SCREEN_LOCK_REASON_UNLOCK_SCREEN_LOCK",
                                                                        comment: "Description of how and why Signal iOS uses Touch ID/Face ID to unlock 'screen lock'."),
                                       touchIdReason: NSLocalizedString("SCREEN_LOCK_REASON_UNLOCK_SCREEN_LOCK_TOUCH_ID",
                                                                        comment: "Description of how and why Signal iOS uses Touch ID to unlock 'screen lock'."),
                                       faceIdReason: NSLocalizedString("SCREEN_LOCK_REASON_UNLOCK_SCREEN_LOCK_FACE_ID",
                                                                       comment: "Description of how and why Signal iOS uses Face ID to unlock 'screen lock'."),

                                       completion: { (outcome: OWSScreenLockOutcome) in
                                        AssertIsOnMainThread()

                                        switch outcome {
                                        case .failure(let error):
                                            failure(self.authenticationError(errorDescription: error))
                                        case .success:
                                            success()
                                        case .cancel:
                                            cancel()
                                        }
        })
    }

    // On failure, completion is called with an error argument.
    // On success or cancel, completion is called with nil argument.
    // Success and cancel can be differentiated by consulting
    // isScreenLockEnabled.
    private func tryToVerifyLocalAuthentication(defaultReason: String,
                                                     touchIdReason: String,
                                                     faceIdReason: String,
                                                     completion completionParam: @escaping ((OWSScreenLockOutcome) -> Void)) {

        // Ensure completion is always called on the main thread.
        let completion = { (outcome: OWSScreenLockOutcome) in
            switch outcome {
            case .failure(let error):
                Logger.error("\(self.TAG) enable screen lock failed with error: \(error)")
            default:
                break
            }
            DispatchQueue.main.async {
                completionParam(outcome)
            }
        }

        let context = screenLockContext()
        let defaultErrorDescription = NSLocalizedString("SCREEN_LOCK_ENABLE_UNKNOWN_ERROR",
                                                        comment: "Indicates that an unknown error occurred while using Touch ID or Face ID.")

        var authError: NSError?
        let canEvaluatePolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError)
        if !canEvaluatePolicy || authError != nil {
            Logger.error("\(TAG) could not determine if screen lock is supported: \(String(describing: authError))")

            let outcome = self.outcomeForLAError(errorParam: authError,
                                                 defaultErrorDescription: defaultErrorDescription)
            switch outcome {
            case .success:
                owsFail("\(self.TAG) unexpected success")
                completion(.failure(error:defaultErrorDescription))
            case .cancel, .failure:
                completion(outcome)
            }
            return
        }

        var localizedReason = defaultReason
        if #available(iOS 11.0, *) {
            if context.biometryType == .touchID {
                localizedReason = touchIdReason
            } else if context.biometryType == .faceID {
                localizedReason = faceIdReason
            }
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: localizedReason) { success, evaluateError in
            if success {
                Logger.info("\(self.TAG) enable screen lock succeeded.")
                completion(.success)
            } else {
                let outcome = self.outcomeForLAError(errorParam: evaluateError,
                                                     defaultErrorDescription: defaultErrorDescription)
                switch outcome {
                case .success:
                    owsFail("\(self.TAG) unexpected success")
                    completion(.failure(error:defaultErrorDescription))
                case .cancel, .failure:
                    completion(outcome)
                }
            }
        }
    }

    // MARK: - Outcome

    private func outcomeForLAError(errorParam: Error?, defaultErrorDescription: String) -> OWSScreenLockOutcome {
        if let error = errorParam {
            guard let laError = error as? LAError else {
                return .failure(error:defaultErrorDescription)
            }

            // TODO: I'm not sure this is necessary.
            if #available(iOS 11.0, *) {
                switch laError.code {
                case .biometryNotAvailable:
                    Logger.error("\(self.TAG) local authentication error: biometryNotAvailable.")
                    return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_AVAILABLE",
                                                             comment: "Indicates that Touch ID/Face ID are not available on this device."))
                case .biometryNotEnrolled:
                    Logger.error("\(self.TAG) local authentication error: biometryNotEnrolled.")
                    return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_ENROLLED",
                                                             comment: "Indicates that Touch ID/Face ID is not configured on this device."))
                case .biometryLockout:
                    Logger.error("\(self.TAG) local authentication error: biometryLockout.")
                    return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_LOCKOUT",
                                                             comment: "Indicates that Touch ID/Face ID is 'locked out' on this device due to authentication failures."))
                default:
                    // Fall through to second switch
                    break
                }
            }

            switch laError.code {
            case .authenticationFailed:
                Logger.error("\(self.TAG) local authentication error: authenticationFailed.")
                return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_FAILED",
                                                         comment: "Indicates that Touch ID/Face ID authentication failed."))
            case .userCancel, .userFallback, .systemCancel, .appCancel:
                Logger.info("\(self.TAG) local authentication cancelled.")
                return .cancel
            case .passcodeNotSet:
                Logger.error("\(self.TAG) local authentication error: passcodeNotSet.")
                return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_PASSCODE_NOT_SET",
                                                         comment: "Indicates that Touch ID/Face ID passcode is not set."))
            case .touchIDNotAvailable:
                Logger.error("\(self.TAG) local authentication error: touchIDNotAvailable.")
                return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_AVAILABLE",
                                                         comment: "Indicates that Touch ID/Face ID are not available on this device."))
            case .touchIDNotEnrolled:
                Logger.error("\(self.TAG) local authentication error: touchIDNotEnrolled.")
                return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_NOT_ENROLLED",
                                                         comment: "Indicates that Touch ID/Face ID is not configured on this device."))
            case .touchIDLockout:
                Logger.error("\(self.TAG) local authentication error: touchIDLockout.")
                return .failure(error: NSLocalizedString("SCREEN_LOCK_ERROR_LOCAL_AUTHENTICATION_LOCKOUT",
                                                         comment: "Indicates that Touch ID/Face ID is 'locked out' on this device due to authentication failures."))
            case .invalidContext:
                owsFail("\(self.TAG) context not valid.")
                break
            case .notInteractive:
                owsFail("\(self.TAG) context not interactive.")
                break
            }
            // This switch may fall through.
        }
        return .failure(error:defaultErrorDescription)
    }

    private func authenticationError(errorDescription: String) -> Error {
        return OWSErrorWithCodeDescription(.localAuthenticationError,
                                           errorDescription)
    }

    // MARK: - Context

    private func screenLockContext() -> LAContext {
        let context = LAContext()

        //        if #available(iOS 11, *) {
        //            context.biometryType = [.touchId,.faceId]
        //        }

        // Time interval for accepting a successful Touch ID or Face ID device unlock (on the lock screen) from the past.
        //
        // TODO: Review.
        context.touchIDAuthenticationAllowableReuseDuration = TimeInterval(5.0)

        // Don't set context.maxBiometryFailures.
        //
        // TODO: Review.

        return context
    }
    
    //
    //    typedef NS_ENUM(NSInteger, LAAccessControlOperation)
    //    {
    //    /// Access control will be used for item creation.
    //    LAAccessControlOperationCreateItem,
    //
    //    /// Access control will be used for accessing existing item.
    //    LAAccessControlOperationUseItem,
    //
    //    /// Access control will be used for key creation.
    //    LAAccessControlOperationCreateKey,
    //
    //    /// Access control will be used for sign operation with existing key.
    //    LAAccessControlOperationUseKeySign,
    //
    //    /// Access control will be used for data decryption using existing key.
    //    LAAccessControlOperationUseKeyDecrypt NS_ENUM_AVAILABLE(10_12, 10_0),
    //
    //    /// Access control will be used for key exchange.
    //    LAAccessControlOperationUseKeyKeyExchange NS_ENUM_AVAILABLE(10_12, 10_0),
    //    } NS_ENUM_AVAILABLE(10_11, 9_0) __WATCHOS_AVAILABLE(3.0) __TVOS_AVAILABLE(10.0);
    //
    //
    //
    //    typedef NS_ENUM(NSInteger, LAPolicy)
    //    {
    //    /// Device owner is going to be authenticated using a biometric method (Touch ID or Face ID).
    //    ///
    //    /// @discussion Biometric authentication is required. If the biometry is not available, not enrolled,
    //    ///             or locked out, then the evaluation of this policy will fail with LAErrorBiometryNotAvailable,
    //    ///             LAErrorBiometryNotEnrolled or LAErrorBiometryLockout. Biometry can't be used without a passcode,
    //    ///             i.e. when biometry is available, enrolled and not locked out but passcode is not set, then
    //    ///             the evaluation will fail with LAErrorPasscodeNotSet.
    //    ///
    //    ///             Touch ID authentication dialog contains a cancel button with default title "Cancel"
    //    ///             which can be customized using localizedCancelTitle property, and a fallback button with
    //    ///             default title "Enter Password" which can be customized using localizedFallbackTitle
    //    ///             property. Fallback button is initially hidden and shows up after first unsuccessful
    //    ///             Touch ID attempt. Tapping either button causes evaluatePolicy call to fail, returning
    //    ///             a distinct error code: LAErrorUserCancel or LAErrorUserFallback.
    //    ///
    //    ///             Face ID authentication begins with animating HUD. If it succeeds at first attempt,
    //    ///             the HUD will disappear and no other UI is shown. If the first attempt fails, then
    //    ///             LocalAuthentication will show a dialog with two buttons: "Cancel" and "Try Face ID Again".
    //    ///             After second failure, the buttons are "Cancel" and "Enter Password" with the same
    //    //              semantics as in the case of Touch ID.
    //    ///
    //    ///             Biometric authentication will get locked after 5 unsuccessful attempts. After that,
    //    ///             users have to unlock it by entering passcode. The passcode can be entered either at
    //    ///             Lock Screen or even in app by the means of LAPolicyDeviceOwnerAuthentication.
    //    ///             The Lock Screen unlock is preferred user experience because we generaly don't want users to
    //    ///             enter their passcode at app's request.
    //    LAPolicyDeviceOwnerAuthenticationWithBiometrics NS_ENUM_AVAILABLE(10_12_2, 8_0) __WATCHOS_AVAILABLE(3.0) __TVOS_AVAILABLE(10.0) = kLAPolicyDeviceOwnerAuthenticationWithBiometrics,
    //
    //    /// Device owner is going to be authenticated by biometry or device passcode.
    //    ///
    //    /// @discussion Biometric or passcode authentication is required. If the biometry is available, enrolled and
    //    ///             not locked out, users are asked for it first. Otherwise they are asked to enter device
    //    ///             passcode. If passcode is not enabled, policy evaluation will fail with LAErrorPasscodeNotSet.
    //    ///
    //    ///             Biometric authentication dialog behaves similarly as the one used by
    //    ///             LAPolicyDeviceOwnerAuthenticationWithBiometrics. However, instead of "Enter Password"
    //    ///             button there is "Enter Passcode" button which, when tapped, switches the authentication
    //    ///             method and allows users to enter device passcode.
    //    ///
    //    ///             Passcode authentication will get locked after 6 unsuccessful attempts with progressively
    //    ///             increased backoff delay.
    //    LAPolicyDeviceOwnerAuthentication NS_ENUM_AVAILABLE(10_11, 9_0) = kLAPolicyDeviceOwnerAuthentication
}
