//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import LibSignalClient
public import SignalServiceKit
public import SignalUI

public class RegistrationNavigationController: OWSNavigationController {

    private let coordinator: RegistrationCoordinator
    private var logger: PrefixedLogger { coordinator.logger }
    private var userActionLogger: PrefixedLogger { coordinator.logger.prefixedWith(with: "[Action]") }

    public static func withCoordinator(_ coordinator: RegistrationCoordinator) -> RegistrationNavigationController {
        let vc = RegistrationNavigationController(coordinator: coordinator)
        return vc
    }

    private init(coordinator: RegistrationCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.isEnabled = false
        if #available(iOS 26.0, *) {
            interactiveContentPopGestureRecognizer?.isEnabled = false
        }
        if #unavailable(iOS 26) {
            navigationBar.tintColor = .Signal.accent
        }
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if viewControllers.isEmpty, !isLoading {
            logger.info("Performing initial load")
            pushNextStepController()
        }

        let submitLogsGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(didRequestToSubmitDebugLogs),
        )
        submitLogsGesture.numberOfTapsRequired = 8
        submitLogsGesture.delaysTouchesEnded = false
        view.addGestureRecognizer(submitLogsGesture)
    }

    private var isLoading = false

    private func pushNextController(
        _ step: Guarantee<RegistrationStep>,
        loadingMode: RegistrationLoadingViewController.RegistrationLoadingMode? = .generic,
    ) {
        guard !isLoading else {
            owsFailDebug("Parallel loads not allowed", logger: logger)
            return
        }

        if let loadingMode, !step.isSealed {
            logger.info("Pushing loading controller")
            isLoading = true

            switch loadingMode {
            case .restoringBackup(let progressModal):
                present(
                    progressModal,
                    animated: true,
                ) { [weak self] in
                    self?._pushNextController(step)
                }
            default:
                pushViewController(
                    RegistrationLoadingViewController(mode: loadingMode),
                    animated: false,
                ) { [weak self] in
                    self?._pushNextController(step)
                }
            }
        } else {
            logger.info("Skipping loading controller for \(String(describing: try? step.result?.get()))")
            _pushNextController(step)
        }
    }

    private func pushNextStepController(
        loadingMode: RegistrationLoadingViewController.RegistrationLoadingMode? = .generic,
    ) {
        pushNextController(
            Guarantee.wrapAsync { [coordinator] in await coordinator.nextStep() },
            loadingMode: loadingMode,
        )
    }

    private func _pushNextController(_ step: Guarantee<RegistrationStep>) {
        isLoading = true
        Task { @MainActor [self] in
            let step = await step.awaitable()

            if let progressModal = self.presentedViewController as? BackupRestoreProgressModal {
                logger.info("Dismissing progress view")
                await progressModal.completeAndDismiss()
            }

            logger.info("Pushing registration step: \(step)")

            self.isLoading = false
            guard let controller = self.controller(for: step) else {
                logger.info("No controller for \(step)")
                return
            }
            var controllerToPush: UIViewController?
            for viewController in self.viewControllers.reversed() {
                // If we already have this controller available, update it and pop to it.
                if type(of: viewController) == controller.viewType {
                    if let newController = controller.updateViewController(viewController) {
                        logger.info("Pushing new version of existing controller for \(step)")
                        controllerToPush = newController
                    } else {
                        logger.info("Popping to existing controller for \(step)")
                        let animatePop = !(self.topViewController is RegistrationLoadingViewController)
                        self.popToViewController(viewController, animated: animatePop)
                        return
                    }
                }
            }

            // If we got here, there were no matches and we should push.
            let vc = controllerToPush ?? controller.makeViewController(self)

            if
                controller.canCancel,
                !self.viewControllers.contains(where: { $0 is RegistrationSplashViewController })
            {
                // Cancellable controllers need to have a splash view behind
                logger.info("Pushing splash view and controller for \(step)")
                let splashController = self.registrationSplashController()
                let newViewControllers = [splashController.makeViewController(self), vc]
                self.setViewControllers(self.viewControllers + newViewControllers, animated: true)
                return
            }

            logger.info("Pushing controller for \(step)")
            self.pushViewController(vc, animated: true)
        }
    }

    private struct Controller<T: UIViewController>: AnyController {
        private let type: T.Type
        // If a controller can cancel, then it needs to have a splash screen behind it to go back to
        let canCancel: Bool
        let make: (RegistrationNavigationController) -> UIViewController
        // Return a new controller to push, or nil if it should reuse the same controller.
        let update: ((T) -> T?)?

        init(
            type: T.Type,
            canCancel: Bool = false,
            make: @escaping (RegistrationNavigationController) -> UIViewController,
            update: ((T) -> T?)?,
        ) {
            self.type = type
            self.canCancel = canCancel
            self.make = make
            self.update = update
        }

        var viewType: UIViewController.Type { T.self }

        func makeViewController(_ presenter: RegistrationNavigationController) -> UIViewController {
            return make(presenter)
        }

        func updateViewController<U>(_ vc: U) -> U? where U: UIViewController {
            guard let vc = vc as? T else {
                owsFailDebug("Invalid view controller type")
                return nil
            }
            if let newController = update?(vc) as? U {
                return newController
            }
            return nil
        }
    }

    private func registrationSplashController() -> Controller<RegistrationSplashViewController> {
        Controller(
            type: RegistrationSplashViewController.self,
            make: { presenter in
                return RegistrationSplashViewController(presenter: presenter)
            },
            // No state to update.
            update: nil,
        )
    }

    private func controller(for step: RegistrationStep) -> AnyController? {
        switch step {
        case .registrationSplash:
            return self.registrationSplashController()
        case .changeNumberSplash:
            return Controller(
                type: RegistrationChangeNumberSplashViewController.self,
                make: { presenter in
                    return RegistrationChangeNumberSplashViewController(presenter: presenter)
                },
                // No state to update.
                update: nil,
            )
        case .signalLoginSplash(let state):
            return Controller(
                type: RegistrationSignalLoginSplashViewController.self,
                make: { presenter in
                    return RegistrationSignalLoginSplashViewController(state: state, presenter: presenter)
                },
                update: nil,
            )
        case .permissions:
            return Controller(
                type: RegistrationPermissionsViewController.self,
                make: { presenter in
                    RegistrationPermissionsViewController(requestingContactsAuthorization: true, presenter: presenter)
                },
                // The state never changes here. In theory we would build
                // state update support in the permissions controller,
                // but its overkill so we have not.
                update: nil,
            )
        case .scanQuickRegistrationQrCode:
            return Controller(
                type: RegistrationQuickRestoreQRCodeViewController.self,
                canCancel: true,
                make: { presenter in
                    return RegistrationQuickRestoreQRCodeViewController(
                        presenter: presenter,
                    )
                },
                // State never changes.
                update: nil,
            )
        case .phoneNumberEntry(let state):
            switch state {
            case .registration(let registrationMode):
                return Controller(
                    type: RegistrationPhoneNumberViewController.self,
                    canCancel: true,
                    make: { presenter in
                        return RegistrationPhoneNumberViewController(state: registrationMode, presenter: presenter)
                    },
                    update: { controller in
                        controller.updateState(registrationMode)
                        return nil
                    },
                )
            case .changingNumber(let changingNumberMode):
                switch changingNumberMode {
                case .initialEntry(let initialEntryState):
                    return Controller(
                        type: RegistrationChangePhoneNumberViewController.self,
                        make: { presenter in
                            return RegistrationChangePhoneNumberViewController(
                                state: initialEntryState,
                                presenter: presenter,
                            )
                        },
                        update: { controller in
                            controller.updateState(initialEntryState)
                            return nil
                        },
                    )
                case .confirmation(let confirmationState):
                    return Controller(
                        type: RegistrationChangePhoneNumberConfirmationViewController.self,
                        make: { presenter in
                            return RegistrationChangePhoneNumberConfirmationViewController(
                                state: confirmationState,
                                presenter: presenter,
                            )
                        },
                        update: { controller in
                            controller.updateState(confirmationState)
                            return nil
                        },
                    )
                }
            }
        case .verificationCodeEntry(let state):
            return Controller(
                type: RegistrationVerificationViewController.self,
                make: { presenter in
                    return RegistrationVerificationViewController(state: state, presenter: presenter)
                },
                update: { controller in
                    controller.updateState(state)
                    return nil
                },
            )
        case .promptForLogin(let state):
            return Controller(
                type: RegistrationSignalLoginViewController.self,
                make: { presenter in
                    return RegistrationSignalLoginViewController(
                        state: state,
                        goToNextStep: { [unowned presenter] in presenter.pushNextStepController() },
                    )
                },
                update: nil,
            )
        case .pinEntry(let state):
            return Controller(
                type: RegistrationPinViewController.self,
                make: { presenter in
                    return RegistrationPinViewController(state: state, presenter: presenter)
                },
                update: { [weak self] controller in
                    switch (controller.state.operation, state.operation) {
                    case
                        (.creatingNewPin, .creatingNewPin),
                        (.confirmingNewPin, .confirmingNewPin),
                        (.enteringExistingPin, .enteringExistingPin):
                        controller.updateState(state)
                        return nil
                    default:
                        guard let self else { return nil }
                        return RegistrationPinViewController(state: state, presenter: self)
                    }
                },
            )
        case .pinAttemptsExhaustedWithoutReglock(let state):
            return Controller(
                type: RegistrationPinAttemptsExhaustedAndMustCreateNewPinViewController.self,
                make: { presenter in
                    return RegistrationPinAttemptsExhaustedAndMustCreateNewPinViewController(
                        state: state,
                        presenter: presenter,
                    )
                },
                update: {
                    $0.updateState(state)
                    return nil
                },
            )
        case .captchaChallenge:
            return Controller(
                type: RegistrationCaptchaViewController.self,
                make: { presenter in
                    return RegistrationCaptchaViewController(presenter: presenter)
                },
                update: { [weak self] _ in
                    guard let self else {
                        return nil
                    }
                    // Show a fresh captcha controller if we get repeated captcha requests.
                    return RegistrationCaptchaViewController(presenter: self)
                },
            )
        case .setupProfile(let state):
            return Controller(
                type: RegistrationProfileViewController.self,
                make: { presenter in
                    return RegistrationProfileViewController(state: state, presenter: presenter)
                },
                // No state to update.
                update: nil,
            )
        case .chooseRestoreMethod(let restorePath):
            return Controller(
                type: RegistrationChooseRestoreMethodViewController.self,
                make: { [securityScopedBookmarkAccess = coordinator.securityScopedBookmarkAccess] presenter in
                    return RegistrationChooseRestoreMethodViewController(
                        presenter: presenter,
                        restorePath: restorePath,
                        securityScopedBookmarkAccess: securityScopedBookmarkAccess,
                    )
                },
                update: nil,
            )
        case .confirmRestoreFromBackup(let state):
            return Controller(
                type: RegistrationRestoreFromBackupConfirmationViewController.self,
                make: { presenter in
                    return RegistrationRestoreFromBackupConfirmationViewController(state: state, presenter: presenter)
                },
                update: nil,
            )
        case .deviceTransfer(let coordinator):
            return Controller(
                type: RegistrationDeviceTransferStatusViewController.self,
                make: { presenter in
                    return RegistrationDeviceTransferStatusViewController(
                        coordinator: coordinator,
                        presenter: presenter,
                    )
                },
                // No state to update.
                update: nil,
            )
        case .phoneNumberDiscoverability(let state):
            return Controller(
                type: RegistrationPhoneNumberDiscoverabilityViewController.self,
                make: { presenter in
                    return RegistrationPhoneNumberDiscoverabilityViewController(state: state, presenter: presenter)
                },
                update: nil,
            )
        case .reglockTimeout(let state):
            return Controller(
                type: RegistrationReglockTimeoutViewController.self,
                make: { presenter in
                    return RegistrationReglockTimeoutViewController(state: state, presenter: presenter)
                },
                // No state to update.
                update: nil,
            )
        case .reviewAndConfirmSignalLogin(let state):
            return Controller(
                type: RegistrationSignalLoginDetailsViewController.self,
                make: { presenter in
                    return RegistrationSignalLoginDetailsViewController(
                        state: state,
                        goToNextStep: { [unowned presenter] in presenter.pushNextStepController() },
                    )
                },
                update: nil,
            )
        case .enterRecoveryKey(let state):
            return Controller(
                type: RegistrationEnterAccountEntropyPoolViewController.self,
                make: { presenter in
                    return RegistrationEnterAccountEntropyPoolViewController(
                        state: state,
                        presenter: presenter,
                    )
                },
                // No state to update.
                update: nil,
            )
        case .showError(let error):
            let title: String?
            let message: String
            do {
                throw error
            } catch is AppExpiredError, is Registration.UnknownChallengeError {
                present(UIAlertController.registrationAppUpdateBanner(), animated: true)
                return nil
            } catch Registration.VerificationCodeError.providerFailure {
                title = nil
                message = OWSLocalizedString(
                    "REGISTRATION_PROVIDER_FAILURE_MESSAGE_PERMANENT",
                    comment: "Error shown if an SMS/call service provider is unable to send a verification code to the provided number.",
                )
            } catch let error as Registration.BecameDeregisteredError {
                handleDeregistrationReset(localIdentifiers: error.localIdentifiers)
                return nil
            } catch Registration.VerificationCodeError.tooManyAttempts {
                title = nil
                message = OWSLocalizedString(
                    "REGISTRATION_SUBMIT_CODE_ATTEMPTS_EXHAUSTED_ALERT",
                    comment: "Alert shown when running out of attempts at submitting a verification code.",
                )
            } catch Registration.VerificationCodeError.wrongCode {
                title = nil
                message = OWSLocalizedString(
                    "REGISTRATION_VERIFICATION_ERROR_INVALID_VERIFICATION_CODE",
                    comment: "During registration and re-registration, users may have to enter a code to verify ownership of their phone number. If they enter an invalid code, they will see this error message.",
                )
            } catch where error.isNetworkFailureOrTimeout {
                title = OWSLocalizedString(
                    "REGISTRATION_NETWORK_ERROR_TITLE",
                    comment: "A network error occurred during registration, and an error is shown to the user. This is the title on that error sheet.",
                )
                message = OWSLocalizedString(
                    "REGISTRATION_NETWORK_ERROR_BODY",
                    comment: "A network error occurred during registration, and an error is shown to the user. This is the body on that error sheet.",
                )
            } catch {
                title = nil
                message = CommonStrings.somethingWentWrongTryAgainLaterError
            }
            let actionSheet = ActionSheetController(title: title, message: message)
            actionSheet.addAction(.init(title: CommonStrings.okButton, style: .default, handler: { [weak self] _ in
                self?.pushNextStepController()
            }))
            // We explicitly don't want the user to be able to dismiss.
            actionSheet.isCancelable = false
            self.presentActionSheet(actionSheet)
            return nil
        case .done:
            logger.info("Finished with registration!")
            SignalApp.shared.showHomeTabBarController()
            return nil
        }
    }

    private func handleDeregistrationReset(localIdentifiers: ReregisteringLocalIdentifiers) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "DEREGISTRATION_NOTIFICATION",
                comment: "Notification warning the user that they have been de-registered.",
            ),
            message: nil,
        )
        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "SETTINGS_REREGISTER_BUTTON",
                comment: "Label for re-registration button.",
            ),
            style: .default,
            handler: { [weak self] _ in
                guard let self else { return }
                let loader = RegistrationCoordinatorLoaderImpl(dependencies: .from(self))
                SignalApp.shared.showRegistration(loader: loader, desiredMode: .reRegistering(localIdentifiers))
            },
        ))
        // We explicitly don't want the user to be able to dismiss.
        actionSheet.isCancelable = false
        self.presentActionSheet(actionSheet)
    }

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        let superOrientations = super.supportedInterfaceOrientations
        let onboardingOrientations: UIInterfaceOrientationMask = UIDevice.current.isIPad ? .all : .portrait

        return superOrientations.intersection(onboardingOrientations)
    }

    @objc
    private func didRequestToSubmitDebugLogs() {
        if DebugFlags.internalSettings {
            let navVc = UINavigationController(rootViewController: InternalSettingsViewController(
                mode: .registration,
            ))
            self.present(navVc, animated: true)
        } else {
            let logs = DebugLogs(dumper: .fromGlobals())
            logs.promptToSubmitLogs(from: self, supportTag: "Registration")
        }
    }
}

extension RegistrationNavigationController: RegistrationSplashPresenter {

    public func continueFromSplash() {
        coordinator.continueFromSplash()
        pushNextStepController()
    }

    public func setHasOldDevice(_ hasOldDevice: Bool) {
        coordinator.setHasOldDevice(hasOldDevice)
        pushNextStepController()
    }

    public func switchToDeviceLinkingMode() {
        logger.info("Pushing device linking")
        let controller = RegistrationConfirmModeSwitchViewController(presenter: self)
        pushViewController(controller, animated: true)
    }
}

extension RegistrationNavigationController: RegistrationConfimModeSwitchPresenter {

    public func confirmSwitchToDeviceLinkingMode() {
        beginSecondaryDeviceLinking(startingAtQRCode: false)
    }

    fileprivate func beginSecondaryDeviceLinking(startingAtQRCode: Bool) {
        guard coordinator.switchToSecondaryDeviceLinking() else {
            owsFailBeta("Can't switch to secondary device linking")
            return
        }
        SignalApp.shared.showSecondaryProvisioning(skipOnboarding: startingAtQRCode)
    }
}

extension RegistrationNavigationController: RegistrationChangeNumberSplashPresenter {
    func canChangeNumber() -> ChangeNumberAllowedResult {
        return coordinator.canChangeNumber()
    }
}

extension RegistrationNavigationController: RegistrationPermissionsPresenter {
    func requestPermissions() async {
        let guarantee = coordinator.requestPermissions()
        pushNextController(guarantee, loadingMode: nil)
        await guarantee.asVoid().awaitable()
    }
}

extension RegistrationNavigationController: RegistrationPhoneNumberPresenter {

    func goToNextStep(withE164 e164: E164) {
        userActionLogger.info("Submitted phone number")
        coordinator.submitE164(e164)
        pushNextStepController(loadingMode: .submittingPhoneNumber(e164: e164.stringValue))
    }

    func switchToDeviceLinking() {
        userActionLogger.info("Chose to link as secondary device")
        beginSecondaryDeviceLinking(startingAtQRCode: true)
    }

    func exitRegistration() {
        userActionLogger.info("Exited registration")
        guard coordinator.exitRegistration() else {
            owsFailBeta("Unable to exit registration")
            return
        }
        SignalApp.shared.showHomeTabBarController()
    }

    func registerWithoutNumber() {
        coordinator.registerWithoutNumber()
        pushNextStepController()
    }
}

extension RegistrationNavigationController: RegistrationChangePhoneNumberPresenter {
    func submitProspectiveChangeNumberE164(newE164: E164) {
        userActionLogger.info("Submitted prospective change-number number")
        coordinator.submitProspectiveChangeNumberE164(newE164)
        pushNextStepController(loadingMode: .submittingPhoneNumber(e164: newE164.stringValue))
    }
}

extension RegistrationNavigationController: RegistrationChangePhoneNumberConfirmationPresenter {

    func confirmChangeNumber(newE164: E164) {
        userActionLogger.info("Confirmed new phone number")
        coordinator.submitE164(newE164)
        pushNextStepController(loadingMode: .submittingPhoneNumber(e164: newE164.stringValue))
    }
}

extension RegistrationNavigationController: RegistrationCaptchaPresenter {

    func submitCaptcha(_ token: String) {
        userActionLogger.info("Submitted captcha")
        pushNextController(coordinator.submitCaptcha(token))
    }
}

extension RegistrationNavigationController: RegistrationVerificationPresenter {

    func returnToPhoneNumberEntry() {
        userActionLogger.info("Went back to change phone number")
        coordinator.requestChangeE164()
        pushNextStepController()
    }

    func requestSMSCode() {
        userActionLogger.info("Asked for SMS code")
        coordinator.requestSMSCode()
        pushNextStepController()
    }

    func requestVoiceCode() {
        userActionLogger.info("Asked for voice code")
        coordinator.requestVoiceCode()
        pushNextStepController()
    }

    func submitVerificationCode(_ code: String) {
        userActionLogger.info("Submitted verification code")
        pushNextController(coordinator.submitVerificationCode(code), loadingMode: .submittingVerificationCode)
    }
}

extension RegistrationNavigationController: RegistrationPinPresenter {

    func cancelPinConfirmation() {
        userActionLogger.info("Cancelled confirming new PIN")
        coordinator.resetUnconfirmedPINCode()
        pushNextStepController()
    }

    func askUserToConfirmPin(_ blob: RegistrationPinConfirmationBlob) {
        userActionLogger.info("Entered a new PIN, now confirm")
        coordinator.setPINCodeForConfirmation(blob)
        pushNextStepController()
    }

    func submitPinCode(_ code: String) {
        userActionLogger.info("Submitted PIN")
        pushNextController(coordinator.submitPINCode(code))
    }

    func submitWithSkippedPin() {
        userActionLogger.info("Skipped PIN entry")
        coordinator.skipPINCode()
        pushNextStepController()
    }

    func submitWithCreateNewPinInstead() {
        userActionLogger.info("Chose to create a new PIN instead of entering")
        coordinator.skipAndCreateNewPINCode()
        pushNextStepController()
    }
}

extension RegistrationNavigationController: RegistrationPinAttemptsExhaustedAndMustCreateNewPinPresenter {
    func acknowledgePinGuessesExhausted() {
        userActionLogger.info("Acknowledged running out of PIN guesses")
        pushNextStepController()
    }
}

extension RegistrationNavigationController: RegistrationProfilePresenter {
    func goToNextStep(
        givenName: OWSUserProfile.NameComponent,
        familyName: OWSUserProfile.NameComponent?,
        avatarData: Data?,
        phoneNumberDiscoverability: PhoneNumberDiscoverability?,
    ) {
        userActionLogger.info("Submitted profile")
        coordinator.setProfileInfo(
            givenName: givenName,
            familyName: familyName,
            avatarData: avatarData,
            phoneNumberDiscoverability: phoneNumberDiscoverability,
        )
        pushNextStepController()
    }
}

extension RegistrationNavigationController: RegistrationPhoneNumberDiscoverabilityPresenter {

    var presentedAsModal: Bool { return false }

    func setPhoneNumberDiscoverability(_ phoneNumberDiscoverability: PhoneNumberDiscoverability) {
        userActionLogger.info("Set phone number discoverability")
        coordinator.setPhoneNumberDiscoverability(phoneNumberDiscoverability)
        pushNextStepController()
    }
}

extension RegistrationNavigationController: RegistrationReglockTimeoutPresenter {

    func acknowledgeReglockTimeout() {
        userActionLogger.info("Acknowledged reglock timeout")
        switch coordinator.acknowledgeReglockTimeout() {
        case .cannotExit:
            logger.warn("Tried to exit registration from reglock timeout when unable.")
            return
        case .exitRegistration:
            logger.info("Exiting registration after reglock timeout")
            SignalApp.shared.showHomeTabBarController()
        case .restartRegistration(let nextStepGuarantee):
            pushNextController(nextStepGuarantee)
        }
    }
}

extension RegistrationNavigationController: RegistrationEnterAccountEntropyPoolPresenter {
    func next(accountEntropyPool: SignalServiceKit.AccountEntropyPool) {
        userActionLogger.info("Submitted recovery key")
        coordinator.updateAccountEntropyPool(accountEntropyPool)
        pushNextStepController()
    }

    func cancelKeyEntry() {
        userActionLogger.info("Backed out of recovery key entry")
        coordinator.cancelRecoveryKeyEntry()
        pushNextStepController()
    }

    func forgotKeyAction() {
        userActionLogger.info("Missing recovery key")
        coordinator.updateRestoreMethod(method: .declined)
        pushNextStepController()
    }
}

extension RegistrationNavigationController: RegistrationChooseRestoreMethodPresenter {
    func didChooseRestoreMethod(method: RegistrationRestoreMethod) {
        userActionLogger.info("Picked restore method \(method)")
        coordinator.updateRestoreMethod(method: method)
        pushNextStepController()
    }

    func didCancelRestoreMethodSelection() {
        userActionLogger.info("Backed out of picking a restore method")
        coordinator.resetRestoreMode()
        pushNextStepController()
    }
}

extension RegistrationNavigationController: RegistrationQuickRestoreQRCodePresenter {
    func didReceiveRegistrationMessage(_ message: SignalServiceKit.RegistrationProvisioningMessage) {
        userActionLogger.info("Scanned the QR code on their old device")
        coordinator.restoreFromRegistrationMessage(message: message)
        pushNextStepController()
    }

    func cancelChosenRestoreMethod() {
        userActionLogger.info("Backed out of scanning the QR code")
        coordinator.resetRestoreMode()
        pushNextStepController()
    }
}

extension RegistrationNavigationController: RegistrationTransferStatusPresenter {
    func cancelTransfer() {
        userActionLogger.info("Cancelled the device transfer")
        coordinator.resetRestoreMode()
        pushNextStepController()
    }

    func transferFailed(error: Error) {
        logger.warn("Device transfer failed: \(type(of: error))")
        coordinator.resetRestoreMode()
        pushNextStepController()
    }
}

extension RegistrationNavigationController: RegistrationRestoreFromBackupConfirmationPresenter {
    func skipRestoreFromBackup() {
        userActionLogger.info("Skipped restoring from a backup")
        coordinator.updateRestoreMethod(method: .declined)
        pushNextStepController()
    }

    func cancelRestoreFromBackup() {
        userActionLogger.info("Backed out of confirming the backup restore")
        coordinator.resetRestoreMethodChoice()
        pushNextStepController()
    }

    func restoreFromBackupConfirmed(_ backup: RegistrationRestoreFromBackupConfirmationState.AvailableBackup) {
        userActionLogger.info("Confirmed restoring from a backup")
        Task { @MainActor in
            let progressModal = BackupRestoreProgressModal(style: .backupRestore)
            let (progress, stream) = OWSSequentialProgress<BackupRestoreProgressPhase>.createSink()
            Task { @MainActor in
                for await progress in stream {
                    progressModal.viewModel.updateBackupRestoreProgress(progress: progress)
                }
            }
            coordinator.confirmRestoreFromBackup(progress: progress, selectedBackup: backup)
            pushNextStepController(loadingMode: .restoringBackup(progressModal))
        }
    }
}

extension RegistrationNavigationController: RegistrationSignalLoginSplashPresenter {
    func exitSignalLogin() {
        coordinator.exitSignalLogin()
        pushNextStepController()
    }

    func submitLoginSelection(_ selection: RegistrationSignalLoginSelection) {
        switch selection {
        case .existingLogin:
            coordinator.beginSignalLogin(useExisting: true)
            pushNextStepController()
        case .purchaseLogin:
            coordinator.beginSignalLogin(useExisting: false)
            pushNextStepController()
        }
    }
}

private protocol AnyController {

    var canCancel: Bool { get }

    var viewType: UIViewController.Type { get }

    func makeViewController(_: RegistrationNavigationController) -> UIViewController

    func updateViewController<T: UIViewController>(_: T) -> T?
}
