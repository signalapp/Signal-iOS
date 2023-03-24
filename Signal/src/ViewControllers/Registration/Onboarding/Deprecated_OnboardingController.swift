//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalServiceKit

@objc
public class Deprecated_OnboardingNavigationController: OWSNavigationController {
    private(set) var onboardingController: Deprecated_OnboardingController!

    @objc
    public init(onboardingController: Deprecated_OnboardingController) {
        self.onboardingController = onboardingController
        super.init()
        if let nextMilestone = onboardingController.nextMilestone {
            setViewControllers([onboardingController.nextViewController(milestone: nextMilestone)], animated: false)
        }
    }

    public required init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        let superOrientations = super.supportedInterfaceOrientations
        let onboardingOrientations: UIInterfaceOrientationMask = UIDevice.current.isIPad ? .all : .portrait

        return superOrientations.intersection(onboardingOrientations)
    }
}

// MARK: -

// TODO[Registration]: pull out the parts of this related to secondary device
// linking into simpler classes and delete the rest once once new registration rolls out.
@objc
public class Deprecated_OnboardingController: NSObject {

    public enum OnboardingMode {
        case provisioning
        case registering
    }

    public static let defaultOnboardingMode: OnboardingMode = UIDevice.current.isIPad ? .provisioning : .registering
    public var onboardingMode: OnboardingMode
    private let context: ViewControllerContext

    public class func ascertainOnboardingMode() -> OnboardingMode {
        if tsAccountManager.isRegisteredPrimaryDevice {
            return .registering
        } else if tsAccountManager.isRegistered {
            return .provisioning
        } else {
            return defaultOnboardingMode
        }
    }

    convenience override init() {
        // TODO[ViewContextPiping]
        let context = ViewControllerContext.shared
        let onboardingMode = Deprecated_OnboardingController.ascertainOnboardingMode()
        self.init(context: context, onboardingMode: onboardingMode)
    }

    init(context: ViewControllerContext, onboardingMode: OnboardingMode) {
        self.onboardingMode = onboardingMode
        self.context = context
        super.init()
        Logger.info("onboardingMode: \(onboardingMode), requiredMilestones: \(requiredMilestones), completedMilestones: \(completedMilestones), nextMilestone: \(nextMilestone as Optional)")
    }

    // MARK: -

    enum OnboardingMilestone {
        case verifiedPhoneNumber
        case verifiedLinkedDevice
        case restorePin
        case phoneNumberDiscoverability
        case setupProfile
        case setupPin
    }

    var requiredMilestones: [OnboardingMilestone] {
        switch onboardingMode {
        case .provisioning:
            return [.verifiedLinkedDevice]
        case .registering:
            var milestones: [OnboardingMilestone] = [.verifiedPhoneNumber, .phoneNumberDiscoverability, .setupProfile]

            let hasPendingPinRestoration = context.db.read {
                context.keyBackupService.hasPendingRestoration(transaction: $0)
            }

            if hasPendingPinRestoration {
                milestones.insert(.restorePin, at: 0)
            }

            if FeatureFlags.pinsForNewUsers || hasPendingPinRestoration {
                let hasBackupKeyRequestFailed = context.db.read {
                    context.keyBackupService.hasBackupKeyRequestFailed(transaction: $0)
                }

                if hasBackupKeyRequestFailed {
                    Logger.info("skipping setupPin since a previous request failed")
                } else if hasPendingPinRestoration {
                    milestones.insert(.setupPin, at: 1)
                } else {
                    milestones.append(.setupPin)
                }
            }

            return milestones
        }
    }

    var isComplete: Bool {
        guard !tsAccountManager.isOnboarded() else {
            Logger.debug("previously completed onboarding")
            return true
        }

        guard nextMilestone != nil else {
            Logger.debug("no remaining milestones")
            return true
        }

        return false
    }

    var nextMilestone: OnboardingMilestone? {
        requiredMilestones.first { !completedMilestones.contains($0) }
    }

    var completedMilestones: [OnboardingMilestone] {
        var milestones: [OnboardingMilestone] = []

        if tsAccountManager.isRegisteredPrimaryDevice {
            milestones.append(.verifiedPhoneNumber)
        } else if tsAccountManager.isRegistered {
            milestones.append(.verifiedLinkedDevice)
        }

        if !FeatureFlags.phoneNumberDiscoverability || tsAccountManager.hasDefinedIsDiscoverableByPhoneNumber() {
            milestones.append(.phoneNumberDiscoverability)
        }

        if profileManager.hasProfileName {
            milestones.append(.setupProfile)
        }

        if context.keyBackupService.hasMasterKey {
            milestones.append(.restorePin)
            milestones.append(.setupPin)
        }

        return milestones
    }

    @objc
    public func markAsOnboarded() {
        guard !tsAccountManager.isOnboarded() else { return }
        self.databaseStorage.asyncWrite {
            Logger.info("completed onboarding")
            self.tsAccountManager.setIsOnboarded(true, transaction: $0)
        }
    }

    func showNextMilestone(navigationController: UINavigationController) {
        guard let nextMilestone = nextMilestone else {
            SignalApp.shared().showConversationSplitView()
            markAsOnboarded()
            return
        }

        let viewController = nextViewController(milestone: nextMilestone)

        // *replace* the existing VC's. There's no going back once you've passed a milestone.
        navigationController.setViewControllers([viewController], animated: true)
    }

    fileprivate func nextViewController(milestone: OnboardingMilestone) -> UIViewController {
        Logger.info("milestone: \(milestone)")
        switch milestone {
        case .verifiedPhoneNumber, .verifiedLinkedDevice:
            return Deprecated_OnboardingSplashViewController(onboardingController: self)
        case .setupProfile:
            return Deprecated_OnboardingProfileCreationViewController(onboardingController: self)
        case .restorePin:
            return Deprecated_Onboarding2FAViewController(onboardingController: self, isUsingKBS: true)
        case .setupPin:
            return buildPinSetupViewController()
        case .phoneNumberDiscoverability:
            return Deprecated_RegistrationPhoneNumberDiscoverabilityViewController(onboardingController: self)
        }
    }

    // MARK: - Transitions

    public func onboardingSplashDidComplete(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        pushPermissionsViewOrSkipToRegistration(onto: viewController)
    }

    public func onboardingSplashRequestedModeSwitch(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        let view = Deprecated_OnboardingModeSwitchConfirmationViewController(onboardingController: self)
        viewController.navigationController?.pushViewController(view, animated: true)
    }

    public func overrideDefaultRegistrationMode(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        if FeatureFlags.useNewRegistrationFlow, onboardingMode == .provisioning {
            let loader = RegistrationCoordinatorLoaderImpl(dependencies: .from(self))
            signalApp.showRegistration(loader: loader, desiredMode: .registering)
            return
        }

        switch Self.defaultOnboardingMode {
        case .registering:
            onboardingMode = .provisioning
        case .provisioning:
            onboardingMode = .registering
        }

        pushPermissionsViewOrSkipToRegistration(onto: viewController)
    }

    public func onboardingPermissionsDidComplete(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = viewController.navigationController else {
            owsFailDebug("navigationController was unexpectedly nil")
            return
        }

        pushStartDeviceRegistrationView(onto: navigationController)
    }

    func pushStartDeviceRegistrationView(onto navigationController: UINavigationController) {
        AssertIsOnMainThread()

        if onboardingMode == .provisioning {
            let view = Deprecated_OnboardingTransferChoiceViewController(onboardingController: self)
            navigationController.pushViewController(view, animated: true)
        } else {
            let view = Deprecated_RegistrationPhoneNumberViewController(onboardingController: self)
            navigationController.pushViewController(view, animated: true)
        }
    }

    private func pushPermissionsViewOrSkipToRegistration(
        onto oldViewController: UIViewController
    ) {
        // Disable interaction during the asynchronous operation.
        oldViewController.view.isUserInteractionEnabled = false

        let newViewController = Deprecated_OnboardingPermissionsViewController(onboardingController: self)

        firstly(on: DispatchQueue.sharedUserInitiated) {
            newViewController.needsToAskForAnyPermissions()
        }.timeout(
            // If we don't get an answer quickly, assume we need to ask. We don't
            // expect to hit this timeout, but we really don't want to keep users
            // waiting during registration.
            seconds: 1,
            substituteValue: true
        ).recover(on: DispatchQueue.main) { error in
            // This could only happen if something rejects, which we don't expect.
            // However, because it's registration, we assume we need to ask instead of
            // crashing—that's better than preventing registration.
            owsFailDebug("\(error)")
            return .value(true)
        }.done(on: DispatchQueue.main) { (needsToAskForAnyPermissions: Bool) in
            // Always re-enable interaction in case the user restart registration.
            oldViewController.view.isUserInteractionEnabled = true

            if needsToAskForAnyPermissions {
                oldViewController.navigationController?.pushViewController(newViewController, animated: true)
            } else {
                self.onboardingPermissionsDidComplete(viewController: oldViewController)
            }
        }
    }

    public func requestingVerificationDidSucceed(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        // TODO: Once notification work is complete, uncomment this.
        // Self.notificationPresenter.cancelIncompleteRegistrationNotification()

        let view = Deprecated_OnboardingVerificationViewController(onboardingController: self)
        viewController.navigationController?.pushViewController(view, animated: true)
    }

    public func onboardingDidRequireCaptcha(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = viewController.navigationController else {
            owsFailDebug("Missing navigationController.")
            return
        }

        // The service could demand CAPTCHA from the "phone number" view or later
        // from the "code verification" view.  The "Captcha" view should always appear
        // immediately after the "phone number" view.
        while navigationController.viewControllers.count > 1 &&
            !(navigationController.topViewController is Deprecated_RegistrationPhoneNumberViewController) {
                navigationController.popViewController(animated: false)
        }

        let view = Deprecated_OnboardingCaptchaViewController(onboardingController: self)
        navigationController.pushViewController(view, animated: true)
    }

    @objc
    public func verificationDidComplete(fromView view: UIViewController) {
        AssertIsOnMainThread()
        Logger.info("")
        guard let navigationController = view.navigationController else {
            owsFailDebug("navigationController was unexpectedly nil")
            return
        }

        // At this point, the user has been prompted for contact access
        // and has valid service credentials.
        // We start the contact fetch/intersection now so that by the time
        // they get to conversation list we can show meaningful contact in
        // the suggested contact bubble.
        contactsManagerImpl.fetchSystemContactsOnceIfAlreadyAuthorized(with: .implicit())

        showNextMilestone(navigationController: navigationController)
    }

    public func linkingDidComplete(from viewController: UIViewController) {
        guard let navigationController = viewController.navigationController else {
            owsFailDebug("navigationController was unexpectedly nil")
            return
        }

        showNextMilestone(navigationController: navigationController)
    }

    func buildPinSetupViewController() -> PinSetupViewController {
        return PinSetupViewController.onboardingCreating { [weak self] pinSetupVC, _ in
            guard let self = self else { return }

            guard let navigationController = pinSetupVC.navigationController else {
                owsFailDebug("navigationController was unexpectedly nil")
                return
            }

            self.showNextMilestone(navigationController: navigationController)
        }
    }

    private func onboardingDidRequire2FAPin(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = viewController.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        guard !(navigationController.topViewController is Deprecated_Onboarding2FAViewController) else {
            // 2fa view is already presented, we don't need to push it again.
            return
        }

        let view = Deprecated_Onboarding2FAViewController(onboardingController: self, isUsingKBS: kbsAuth != nil)
        navigationController.pushViewController(view, animated: true)
    }

    @objc
    public func profileWasSkipped(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        showConversationSplitView(view: view)
    }

    @objc
    public func profileDidComplete(fromView view: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        showConversationSplitView(view: view)
    }

    private func showConversationSplitView(view: UIViewController) {
        AssertIsOnMainThread()

        guard let navigationController = view.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        // In production, this view will never be presented in a modal.
        // During testing (debug UI, etc.), it may be a modal.
        let isModal = navigationController.presentingViewController != nil
        if isModal {
            view.dismiss(animated: true, completion: {
                SignalApp.shared().showConversationSplitView()
            })
        } else {
            SignalApp.shared().showConversationSplitView()
        }
    }

    // MARK: - State

    public private(set) var countryState: RegistrationCountryState = .defaultValue

    public private(set) var phoneNumber: Deprecated_RegistrationPhoneNumber?

    public private(set) var captchaToken: String?

    public private(set) var verificationCode: String?

    public private(set) var twoFAPin: String?

    private var kbsAuth: KBSAuthCredential?
    private var hasBackedUpKBS = false

    public private(set) var verificationRequestCount: UInt = 0

    public func update(countryState: RegistrationCountryState) {
        AssertIsOnMainThread()

        self.countryState = countryState
    }

    @objc
    public func update(phoneNumber: Deprecated_RegistrationPhoneNumber) {
        AssertIsOnMainThread()

        self.phoneNumber = phoneNumber
    }

    @objc
    public func update(captchaToken: String) {
        AssertIsOnMainThread()

        self.captchaToken = captchaToken
    }

    @objc
    public func update(verificationCode: String) {
        AssertIsOnMainThread()

        self.verificationCode = verificationCode
    }

    @objc
    public func update(twoFAPin: String) {
        AssertIsOnMainThread()

        self.twoFAPin = twoFAPin
    }

    // MARK: - Debug

    public class func lastRegisteredCountryCode() -> String? {
        RegistrationValues.lastRegisteredCountryCode()
    }

    private class func setLastRegisteredCountryCode(value: String) {
        RegistrationValues.setLastRegisteredCountryCode(value: value)
    }

    public class func lastRegisteredPhoneNumber() -> String? {
        RegistrationValues.lastRegisteredPhoneNumber()
    }

    private class func setLastRegisteredPhoneNumber(value: String) {
        RegistrationValues.setLastRegisteredPhoneNumber(value: value)
    }

    // MARK: - Registration

    public func presentPhoneNumberConfirmationSheet(from vc: UIViewController, number: String, completion: @escaping (_ didApprove: Bool) -> Void) {
        Deprecated_RegistrationHelper.presentPhoneNumberConfirmationSheet(from: vc, number: number, completion: completion)
    }

    public func requestVerification(
        fromViewController: UIViewController,
        isSMS: Bool,
        completion: Deprecated_RegistrationHelper.VerificationCompletion?) {

            AssertIsOnMainThread()

            guard let phoneNumber = phoneNumber else {
                owsFailDebug("Missing phoneNumber.")
                if let completion = completion {
                    DispatchQueue.main.async {
                        completion(false, OWSAssertionError("Missing newPhoneNumber."))
                    }
                }
                return
            }

            Deprecated_RegistrationHelper.requestRegistrationVerification(delegate: self,
                                                               fromViewController: fromViewController,
                                                               phoneNumber: phoneNumber,
                                                               countryState: countryState,
                                                               captchaToken: captchaToken,
                                                               isSMS: isSMS,
                                                               completion: completion)
        }

    // MARK: - Transfer

    func transferAccount(fromViewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = fromViewController.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        guard !(navigationController.topViewController is Deprecated_OnboardingTransferQRCodeViewController) else {
            // qr code view is already presented, we don't need to push it again.
            return
        }

        let view = Deprecated_OnboardingTransferQRCodeViewController(onboardingController: self)
        navigationController.pushViewController(view, animated: true)
    }

    func accountTransferInProgress(fromViewController: UIViewController, progress: Progress) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = fromViewController.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        guard !(navigationController.topViewController is Deprecated_OnboardingTransferProgressViewController) else {
            // qr code view is already presented, we don't need to push it again.
            return
        }

        let view = Deprecated_OnboardingTransferProgressViewController(onboardingController: self, progress: progress)
        navigationController.pushViewController(view, animated: true)
    }

    public func presentTransferOptions(viewController: UIViewController) {
        AssertIsOnMainThread()

        Logger.info("")

        guard let navigationController = viewController.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        guard !(navigationController.topViewController is Deprecated_OnboardingTransferChoiceViewController) else {
            // transfer view is already presented, we don't need to push it again.
            return
        }

        let view = Deprecated_OnboardingTransferChoiceViewController(onboardingController: self)
        navigationController.pushViewController(view, animated: true)
    }

    // MARK: - Verification

    // TODO: Review
    public enum VerificationOutcome: Equatable {
        case success
        case invalidVerificationCode
        case invalid2FAPin
        case invalidV2RegistrationLockPin(remainingAttempts: UInt32)
        case exhaustedV2RegistrationLockAttempts
    }

    internal var hasPendingRestoration: Bool {
        context.db.read { context.keyBackupService.hasPendingRestoration(transaction: $0) }
    }

    public func submitVerification(fromViewController: UIViewController,
                                   checkForAvailableTransfer: Bool = true,
                                   showModal: Bool = true,
                                   completion: @escaping (VerificationOutcome) -> Void) {
        AssertIsOnMainThread()

        // If we have credentials for KBS auth or we're trying to verify
        // after registering, we need to restore our keys from KBS.
        if kbsAuth != nil || hasPendingRestoration {
            guard let twoFAPin = twoFAPin else {
                owsFailDebug("We expected a 2fa attempt, but we don't have a code to try")
                return completion(.invalid2FAPin)
            }

            // Clear all cached values before doing restores during onboarding,
            // they could be stale from previous registrations.
            context.db.write { context.keyBackupService.clearKeys(transaction: $0) }

            context.keyBackupService.restoreKeysAndBackup(with: twoFAPin, and: self.kbsAuth).done {
                // If we restored successfully clear out KBS auth, the server will give it
                // to us again if we still need to do KBS operations.
                self.kbsAuth = nil
                // The above operation already does a backup; don't bother doing another one later.
                self.hasBackedUpKBS = true

                if self.hasPendingRestoration {
                    firstly {
                        self.accountManager.performInitialStorageServiceRestore()
                    }.ensure {
                        completion(.success)
                    }.catch { error in
                        owsFailDebugUnlessNetworkFailure(error)
                    }
                } else {
                    // We've restored our keys, we can now re-run this method to post our registration token
                    // We need to first mark reglock as enabled so we know to include the reglock token in our
                    // registration attempt.
                    self.databaseStorage.write { transaction in
                        self.ows2FAManager.markRegistrationLockV2Enabled(transaction: transaction)
                    }
                    self.submitVerification(fromViewController: fromViewController, completion: completion)
                }
            }.catch { error in
                guard let error = error as? KBS.KBSError else {
                    owsFailDebug("unexpected response from KBS")
                    return completion(.invalid2FAPin)
                }

                switch error {
                case .assertion:
                    owsFailDebug("unexpected response from KBS")
                    completion(.invalid2FAPin)
                case .invalidPin(let remainingAttempts):
                    Logger.warn("Invalid V2 PIN, \(remainingAttempts) attempt(s) remaining")
                    completion(.invalidV2RegistrationLockPin(remainingAttempts: remainingAttempts))
                case .backupMissing:
                    Logger.error("Invalid V2 PIN, attempts exhausted")
                    // We don't have a backup for this person, it probably
                    // was deleted due to too many failed attempts. They'll
                    // have to retry after the registration lock window expires.
                    completion(.exhaustedV2RegistrationLockAttempts)
                }
            }

            return
        }

        guard let phoneNumber = phoneNumber else {
            owsFailDebug("Missing phoneNumber.")
            return
        }
        guard let verificationCode = verificationCode else {
            completion(.invalidVerificationCode)
            return
        }

        // Ensure the account manager state is up-to-date.
        //
        // TODO: We could skip this in production.
        tsAccountManager.phoneNumberAwaitingVerification = phoneNumber.e164

        let twoFAPin = self.twoFAPin ?? {
            // Initially set the value to any stored PIN code so we try that before asking the user to
            // enter their PIN.
            if
                Self.tsAccountManager.isReregistering,
                self.phoneNumber != nil,
                self.phoneNumber?.e164 == Self.tsAccountManager.reregistrationPhoneNumber()
            {
                return Self.ows2FAManager.pinCode
            } else {
                return nil
            }
        }()

        let promise = firstly {
            self.accountManager.register(
                verificationCode: verificationCode,
                pin: twoFAPin,
                checkForAvailableTransfer: checkForAvailableTransfer)

        }.then { () -> Promise<Void> in
            // Re-enable 2FA and RegLock with the registered pin, if any
            if let pin = twoFAPin {
                self.databaseStorage.write { transaction in
                    OWS2FAManager.shared.markEnabled(pin: pin, transaction: transaction)
                }
                if OWS2FAManager.shared.mode == .V2 {
                    return OWS2FAManager.shared.enableRegistrationLockV2()
                }
            }
            return Promise.value(())
        }.then { [weak self] in
            // Do best effort to back up to KBS once we complete registration; this resets
            // the PIN guesses.
            guard let self = self, !self.hasBackedUpKBS, let twoFAPin = self.twoFAPin else {
                return Promise.value(())
            }
            return self.context.keyBackupService.restoreKeysAndBackup(with: twoFAPin)
        }

        if showModal {
            ModalActivityIndicatorViewController.present(fromViewController: fromViewController, canCancel: true) { modal in
                promise.done {
                    modal.dismiss {
                        self.verificationDidComplete(fromView: fromViewController)
                    }
                }.catch { error in
                    modal.dismiss(completion: {
                        Logger.warn("Error: \(error)")

                        self.verificationFailed(
                            fromViewController: fromViewController,
                            error: error as NSError,
                            completion: completion)
                    })
                }
            }
        } else {
            promise.done {
                self.verificationDidComplete(fromView: fromViewController)
            }.catch { error in
                Logger.warn("Error: \(error)")

                self.verificationFailed(
                    fromViewController: fromViewController,
                    error: error as NSError,
                    completion: completion)
            }
        }
    }

    private func verificationFailed(fromViewController: UIViewController,
                                    error: NSError,
                                    completion: @escaping (VerificationOutcome) -> Void) {
        AssertIsOnMainThread()

        if let registrationMissing2FAPinError = (error as Error) as? RegistrationMissing2FAPinError {

            Logger.info("Missing 2FA PIN.")

            // If we were provided KBS auth, we'll need to re-register using reg lock v2,
            // store this for that path.
            kbsAuth = KBSAuthCredential(credential: registrationMissing2FAPinError.remoteAttestationAuth)

            // Since we were told we need 2fa, clear out any stored KBS keys so we can
            // do a fresh verification.
            SDSDatabaseStorage.shared.write { transaction in
                context.keyBackupService.clearKeys(transaction: transaction.asV2Write)
                self.ows2FAManager.markRegistrationLockV2Disabled(transaction: transaction)
                self.ows2FAManager.setPinCode(nil, transaction: transaction)
            }

            completion(.invalid2FAPin)

            onboardingDidRequire2FAPin(viewController: fromViewController)
        } else if error.domain == OWSSignalServiceKitErrorDomain &&
            error.code == OWSErrorCode.registrationTransferAvailable.rawValue {
            Logger.info("Transfer available")

            presentTransferOptions(viewController: fromViewController)

            completion(.success)
        } else {
            if error.domain == OWSSignalServiceKitErrorDomain &&
                error.code == OWSErrorCode.userError.rawValue {
                completion(.invalidVerificationCode)
            }

            Logger.verbose("error: \(error.domain) \(error.code)")
            OWSActionSheets.showActionSheet(title: NSLocalizedString("REGISTRATION_VERIFICATION_FAILED_TITLE", comment: "Alert view title"),
                                message: error.userErrorDescription,
                                fromViewController: fromViewController)
        }
    }
}

// MARK: -

public extension UIView {
    func addBottomStroke() -> UIView {
        return addBottomStroke(color: Theme.middleGrayColor, strokeWidth: CGHairlineWidth())
    }

    func addBottomStroke(color: UIColor, strokeWidth: CGFloat) -> UIView {
        let strokeView = UIView()
        strokeView.backgroundColor = color
        addSubview(strokeView)
        strokeView.autoSetDimension(.height, toSize: strokeWidth)
        strokeView.autoPinWidthToSuperview()
        strokeView.autoPinEdge(toSuperviewEdge: .bottom)
        return strokeView
    }
}

// MARK: -

extension Deprecated_OnboardingController: Deprecated_RegistrationHelperDelegate {
    public func registrationRequestVerificationDidSucceed(fromViewController: UIViewController) {
        requestingVerificationDidSucceed(viewController: fromViewController)
    }

    public func registrationRequestVerificationDidRequireCaptcha(fromViewController: UIViewController) {
        onboardingDidRequireCaptcha(viewController: fromViewController)
    }

    public func registrationIncrementVerificationRequestCount() {
        verificationRequestCount += 1
    }
}

// MARK: -

extension Deprecated_OnboardingController: Deprecated_RegistrationPinAttemptsExhaustedViewDelegate {

    func pinAttemptsExhaustedViewDidComplete(viewController: Deprecated_RegistrationPinAttemptsExhaustedViewController) {
        guard let navigationController = viewController.navigationController else {
            owsFailDebug("Missing navigationController")
            return
        }

        if hasPendingRestoration {
            context.db.write { transaction in
                context.keyBackupService.clearPendingRestoration(transaction: transaction)
            }
            showNextMilestone(navigationController: navigationController)
        } else {
            navigationController.popToRootViewController(animated: true)
        }
    }
}
