//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

public import SignalServiceKit
public import SignalUI

final public class RegistrationNavigationController: OWSNavigationController {

    private let appReadiness: AppReadinessSetter
    private let coordinator: RegistrationCoordinator

    public static func withCoordinator(
        _ coordinator: RegistrationCoordinator,
        appReadiness: AppReadinessSetter
    ) -> RegistrationNavigationController {
        let vc = RegistrationNavigationController(coordinator: coordinator, appReadiness: appReadiness)
        return vc
    }

    private init(coordinator: RegistrationCoordinator, appReadiness: AppReadinessSetter) {
        self.appReadiness = appReadiness
        self.coordinator = coordinator
        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.isEnabled = false
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if viewControllers.isEmpty, !isLoading {
            Logger.info("Performing initial load")
            pushNextController(Guarantee.wrapAsync { await self.coordinator.nextStep() })
        }

        let submitLogsGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(didRequestToSubmitDebugLogs)
        )
        submitLogsGesture.numberOfTapsRequired = 8
        submitLogsGesture.delaysTouchesEnded = false
        view.addGestureRecognizer(submitLogsGesture)
    }

    private var isLoading = false

    private func pushNextController(
        _ step: Guarantee<RegistrationStep>,
        loadingMode: RegistrationLoadingViewController.RegistrationLoadingMode? = .generic
    ) {
        guard !isLoading else {
            owsFailDebug("Parallel loads not allowed")
            return
        }

        if let loadingMode, step.isSealed.negated {
            Logger.info("Pushing loading controller")
            isLoading = true

            switch loadingMode {
            case .restoringBackup(let progressModal):
                present(
                    progressModal,
                    animated: true
                ) { [weak self] in
                    self?._pushNextController(step)
                }
            default:
                pushViewController(
                    RegistrationLoadingViewController(mode: loadingMode),
                    animated: false
                ) { [weak self] in
                    self?._pushNextController(step)
                }
            }
        } else {
            Logger.info("Skipping loading controller for \(String(describing: try? step.result?.get().logSafeString))")
            _pushNextController(step)
        }
    }

    private func _pushNextController(_ step: Guarantee<RegistrationStep>) {
        isLoading = true
        Task { @MainActor [self] in
            let step = await step.awaitable()

            if let progressModal = self.presentedViewController as? BackupProgressModal {
                Logger.info("Dismissing progress view")
                await progressModal.completeAndDismiss()
            }

            Logger.info("Pushing registration step: \(step.logSafeString)")

            self.isLoading = false
            guard let controller = self.controller(for: step) else {
                Logger.info("No controller for \(step.logSafeString)")
                return
            }
            var controllerToPush: UIViewController?
            for viewController in self.viewControllers.reversed() {
                // If we already have this controller available, update it and pop to it.
                if type(of: viewController) == controller.viewType {
                    if let newController = controller.updateViewController(viewController) {
                        Logger.info("Pushing new version of existing controller for \(step.logSafeString)")
                        controllerToPush = newController
                    } else {
                        Logger.info("Popping to existing controller for \(step.logSafeString)")
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
                Logger.info("Pushing splash view and controller for \(step.logSafeString)")
                let splashController = self.registrationSplashController()
                let newViewControllers = [splashController.makeViewController(self), vc]
                self.setViewControllers(self.viewControllers + newViewControllers, animated: true)
                return
            }

            Logger.info("Pushing controller for \(step.logSafeString)")
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
            update: ((T) -> T?)?
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
            update: nil
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
                update: nil
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
                update: nil
            )
        case .scanQuickRegistrationQrCode:
            return Controller(
                type: RegistrationQuickRestoreQRCodeViewController.self,
                canCancel: true,
                make: { presenter in
                    return RegistrationQuickRestoreQRCodeViewController(
                        presenter: presenter
                    )
                },
                // State never changes.
                update: nil
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
                    }
                )
            case .changingNumber(let changingNumberMode):
                switch changingNumberMode {
                case .initialEntry(let initialEntryState):
                    return Controller(
                        type: RegistrationChangePhoneNumberViewController.self,
                        make: { presenter in
                            return RegistrationChangePhoneNumberViewController(
                                state: initialEntryState,
                                presenter: presenter
                            )
                        },
                        update: { controller in
                            controller.updateState(initialEntryState)
                            return nil
                        }
                    )
                case .confirmation(let confirmationState):
                    return Controller(
                        type: RegistrationChangePhoneNumberConfirmationViewController.self,
                        make: { presenter in
                            return RegistrationChangePhoneNumberConfirmationViewController(
                                state: confirmationState,
                                presenter: presenter
                            )
                        },
                        update: { controller in
                            controller.updateState(confirmationState)
                            return nil
                        }
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
                }
            )
        case .transferSelection:
            return Controller(
                type: RegistrationTransferChoiceViewController.self,
                make: { presenter in
                    return RegistrationTransferChoiceViewController(presenter: presenter)
                },
                // No state to update.
                update: nil
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
                }
            )
        case .pinAttemptsExhaustedWithoutReglock(let state):
            return Controller(
                type: RegistrationPinAttemptsExhaustedAndMustCreateNewPinViewController.self,
                make: { presenter in
                    return RegistrationPinAttemptsExhaustedAndMustCreateNewPinViewController(
                        state: state,
                        presenter: presenter
                    )
                },
                update: {
                    $0.updateState(state)
                    return nil
                }
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
                }
            )
        case .setupProfile(let state):
            return Controller(
                type: RegistrationProfileViewController.self,
                make: { presenter in
                    return RegistrationProfileViewController(state: state, presenter: presenter)
                },
                // No state to update.
                update: nil
            )
        case .chooseRestoreMethod(let restorePath):
            return Controller(
                type: RegistrationChooseRestoreMethodViewController.self,
                make: { presenter in
                    return RegistrationChooseRestoreMethodViewController(
                        presenter: presenter,
                        restorePath: restorePath,
                    )
                },
                update: nil
            )
        case .confirmRestoreFromBackup(let state):
            return Controller(
                type: RegistrationRestoreFromBackupConfirmationViewController.self,
                make: { presenter in
                    return RegistrationRestoreFromBackupConfirmationViewController(state: state, presenter: presenter)
                },
                update: nil
            )
        case .deviceTransfer(let state):
            return Controller(
                type: RegistrationTransferStatusViewController.self,
                make: { presenter in
                    return RegistrationTransferStatusViewController(state: state, presenter: presenter)
                },
                // No state to update.
                update: nil
            )
        case .phoneNumberDiscoverability(let state):
            return Controller(
                type: RegistrationPhoneNumberDiscoverabilityViewController.self,
                make: { presenter in
                    return RegistrationPhoneNumberDiscoverabilityViewController(state: state, presenter: presenter)
                },
                update: nil
            )
        case .reglockTimeout(let state):
            return Controller(
                type: RegistrationReglockTimeoutViewController.self,
                make: { presenter in
                    return RegistrationReglockTimeoutViewController(state: state, presenter: presenter)
                },
                // No state to update.
                update: nil
            )
        case .enterRecoveryKey(let state):
            return Controller(
                type: RegistrationEnterAccountEntropyPoolViewController.self,
                make: { presenter in
                    return RegistrationEnterAccountEntropyPoolViewController(state: state, presenter: presenter)
                },
                // No state to update.
                update: nil
            )

        case let .showErrorSheet(errorSheet):
            let title: String?
            let message: String
            switch errorSheet {
            case .becameDeregistered(let reregParams):
                handleDeregistrationReset(reregParams)
                return nil

            case .verificationCodeSubmissionUnavailable:
                title = nil
                message = OWSLocalizedString(
                    "REGISTRATION_SUBMIT_CODE_ATTEMPTS_EXHAUSTED_ALERT",
                    comment: "Alert shown when running out of attempts at submitting a verification code."
                )
            case .submittingVerificationCodeBeforeAnyCodeSent:
                title = nil
                message = OWSLocalizedString(
                    "REGISTRATION_VERIFICATION_ERROR_INVALID_VERIFICATION_CODE",
                    comment: "During registration and re-registration, users may have to enter a code to verify ownership of their phone number. If they enter an invalid code, they will see this error message."
                )
            case .networkError:
                title = OWSLocalizedString(
                    "REGISTRATION_NETWORK_ERROR_TITLE",
                    comment: "A network error occurred during registration, and an error is shown to the user. This is the title on that error sheet."
                )
                message = OWSLocalizedString(
                    "REGISTRATION_NETWORK_ERROR_BODY",
                    comment: "A network error occurred during registration, and an error is shown to the user. This is the body on that error sheet."
                )
            case .sessionInvalidated, .genericError:
                title = nil
                message = CommonStrings.somethingWentWrongTryAgainLaterError
            }
            let actionSheet = ActionSheetController(title: title, message: message)
            actionSheet.addAction(.init(title: CommonStrings.okButton, style: .default, handler: { [weak self] _ in
                guard let self else { return }
                self.pushNextController(Guarantee.wrapAsync { await self.coordinator.nextStep() })
            }))
            // We explicitly don't want the user to be able to dismiss.
            actionSheet.isCancelable = false
            self.presentActionSheet(actionSheet)
            return nil
        case .appUpdateBanner:
            present(UIAlertController.registrationAppUpdateBanner(), animated: true)
            return nil
        case .done:
            Logger.info("Finished with registration!")
            SignalApp.shared.showConversationSplitView(appReadiness: appReadiness)
            return nil
        }
    }

    private func handleDeregistrationReset(_ reregParams: RegistrationMode.ReregistrationParams) {
        let actionSheet = ActionSheetController(
            title: OWSLocalizedString(
                "DEREGISTRATION_NOTIFICATION",
                comment: "Notification warning the user that they have been de-registered."
            ),
            message: nil
        )
        actionSheet.addAction(.init(
            title: OWSLocalizedString(
                "SETTINGS_REREGISTER_BUTTON",
                comment: "Label for re-registration button."
            ),
            style: .default,
            handler: { [weak self, appReadiness] _ in
                guard let self else { return }
                let loader = RegistrationCoordinatorLoaderImpl(dependencies: .from(self))
                SignalApp.shared.showRegistration(loader: loader, desiredMode: .reRegistering(reregParams), appReadiness: appReadiness)
            }
        ))
        // We explicitly don't want the user to be able to dismiss.
        actionSheet.isCancelable = false
        self.presentActionSheet(actionSheet)
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
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
            DebugLogs.submitLogs(supportTag: "Registration", dumper: .fromGlobals())
        }
    }
}

extension RegistrationNavigationController: RegistrationSplashPresenter {

    public func continueFromSplash() {
        pushNextController(coordinator.continueFromSplash())
    }

    public func setHasOldDevice(_ hasOldDevice: Bool) {
        pushNextController(coordinator.setHasOldDevice(hasOldDevice))
    }

    public func switchToDeviceLinkingMode() {
        Logger.info("Pushing device linking")
        let controller = RegistrationConfirmModeSwitchViewController(presenter: self)
        pushViewController(controller, animated: true)
    }
}

extension RegistrationNavigationController: RegistrationConfimModeSwitchPresenter {

    public func confirmSwitchToDeviceLinkingMode() {
        guard coordinator.switchToSecondaryDeviceLinking() else {
            owsFailBeta("Can't switch to secondary device linking")
            return
        }
        SignalApp.shared.showSecondaryProvisioning(appReadiness: appReadiness)
    }
}

extension RegistrationNavigationController: RegistrationChangeNumberSplashPresenter {}

extension RegistrationNavigationController: RegistrationPermissionsPresenter {
    func requestPermissions() async {
        let guarantee = coordinator.requestPermissions()
        pushNextController(guarantee, loadingMode: nil)
        await guarantee.asVoid().awaitable()
    }
}

extension RegistrationNavigationController: RegistrationPhoneNumberPresenter {

    func goToNextStep(withE164 e164: E164) {
        pushNextController(coordinator.submitE164(e164), loadingMode: .submittingPhoneNumber(e164: e164.stringValue))
    }

    func exitRegistration() {
        guard coordinator.exitRegistration() else {
            owsFailBeta("Unable to exit registration")
            return
        }
        Logger.info("Early exiting registration")
        SignalApp.shared.showConversationSplitView(appReadiness: appReadiness)
    }
}

extension RegistrationNavigationController: RegistrationChangePhoneNumberPresenter {
    func submitProspectiveChangeNumberE164(newE164: E164) {
        pushNextController(coordinator.submitProspectiveChangeNumberE164(newE164), loadingMode: .submittingPhoneNumber(e164: newE164.stringValue))
    }
}

extension RegistrationNavigationController: RegistrationChangePhoneNumberConfirmationPresenter {

    func confirmChangeNumber(newE164: E164) {
        pushNextController(coordinator.submitE164(newE164), loadingMode: .submittingPhoneNumber(e164: newE164.stringValue))
    }
}

extension RegistrationNavigationController: RegistrationCaptchaPresenter {

    func submitCaptcha(_ token: String) {
        pushNextController(coordinator.submitCaptcha(token))
    }
}

extension RegistrationNavigationController: RegistrationVerificationPresenter {

    func returnToPhoneNumberEntry() {
        pushNextController(coordinator.requestChangeE164())
    }

    func requestSMSCode() {
        pushNextController(coordinator.requestSMSCode())
    }

    func requestVoiceCode() {
        pushNextController(coordinator.requestVoiceCode())
    }

    func submitVerificationCode(_ code: String) {
        pushNextController(coordinator.submitVerificationCode(code), loadingMode: .submittingVerificationCode)
    }
}

extension RegistrationNavigationController: RegistrationPinPresenter {

    func cancelPinConfirmation() {
        pushNextController(coordinator.resetUnconfirmedPINCode())
    }

    func askUserToConfirmPin(_ blob: RegistrationPinConfirmationBlob) {
        pushNextController(coordinator.setPINCodeForConfirmation(blob))
    }

    func submitPinCode(_ code: String) {
        pushNextController(coordinator.submitPINCode(code))
    }

    func submitWithSkippedPin() {
        pushNextController(coordinator.skipPINCode())
    }

    func submitWithCreateNewPinInstead() {
        pushNextController(coordinator.skipAndCreateNewPINCode())
    }
}

extension RegistrationNavigationController: RegistrationPinAttemptsExhaustedAndMustCreateNewPinPresenter {
    func acknowledgePinGuessesExhausted() {
        pushNextController(Guarantee.wrapAsync { await self.coordinator.nextStep() })
    }
}

extension RegistrationNavigationController: RegistrationTransferChoicePresenter {

    public func transferDevice() {
        Logger.info("Pushing device transfer")

        do {
            // TODO: [Backups] - Don't reach into app environment, but this should be removed
            // once Backups launches
            let url = try AppEnvironment.shared.deviceTransferServiceRef.startAcceptingTransfersFromOldDevices(
                mode: .primary
            )

            // We push these controllers right onto the same navigation stack, even though they
            // are not coordinator "steps". They have their own internal logic to proceed and go
            // back (direct calls to push and pop) and, when they complete, they will have _totally_
            // overwritten our local database, thus wiping any in progress reg coordinator state
            // and putting us into the chat list.
            pushViewController(RegistrationTransferQRCodeViewController(url: url), animated: true)
        } catch {
            // TODO: [Backups] - update this error handling
            Logger.error("Error transferring")
        }
    }

    func continueRegistration() {
        pushNextController(coordinator.skipDeviceTransfer())
    }
}

extension RegistrationNavigationController: RegistrationProfilePresenter {
    func goToNextStep(
        givenName: OWSUserProfile.NameComponent,
        familyName: OWSUserProfile.NameComponent?,
        avatarData: Data?,
        phoneNumberDiscoverability: PhoneNumberDiscoverability
    ) {
        pushNextController(
            coordinator.setProfileInfo(
                givenName: givenName,
                familyName: familyName,
                avatarData: avatarData,
                phoneNumberDiscoverability: phoneNumberDiscoverability
            )
        )
    }
}

extension RegistrationNavigationController: RegistrationPhoneNumberDiscoverabilityPresenter {

    var presentedAsModal: Bool { return false }

    func setPhoneNumberDiscoverability(_ phoneNumberDiscoverability: PhoneNumberDiscoverability) {
        pushNextController(coordinator.setPhoneNumberDiscoverability(phoneNumberDiscoverability))
    }
}

extension RegistrationNavigationController: RegistrationReglockTimeoutPresenter {

    func acknowledgeReglockTimeout() {
        switch coordinator.acknowledgeReglockTimeout() {
        case .cannotExit:
            Logger.warn("Tried to exit registration from reglock timeout when unable.")
            return
        case .exitRegistration:
            Logger.info("Exiting registration after reglock timeout")
            SignalApp.shared.showConversationSplitView(appReadiness: appReadiness)
        case .restartRegistration(let nextStepGuarantee):
            pushNextController(nextStepGuarantee)
        }
    }
}

extension RegistrationNavigationController: RegistrationEnterAccountEntropyPoolPresenter {
    func next(accountEntropyPool: AccountEntropyPool) {
        let guarantee = coordinator.updateAccountEntropyPool(accountEntropyPool)
        pushNextController(guarantee)
    }

    func cancelKeyEntry() {
        let guarantee = coordinator.cancelRecoveryKeyEntry()
        pushNextController(guarantee)
    }

    func forgotKeyAction() {
        let guarantee = coordinator.updateRestoreMethod(method: .declined)
        pushNextController(guarantee)
    }
}

extension RegistrationNavigationController: RegistrationChooseRestoreMethodPresenter {
    func didChooseRestoreMethod(method: RegistrationRestoreMethod) {
        let guarantee = coordinator.updateRestoreMethod(method: method)
        pushNextController(guarantee)
    }

    func didCancelRestoreMethodSelection() {
        let guarantee = coordinator.resetRestoreMode()
        pushNextController(guarantee)
    }
}

extension RegistrationNavigationController: RegistrationQuickRestoreQRCodePresenter {
    func didReceiveRegistrationMessage(_ message: SignalServiceKit.RegistrationProvisioningMessage) {
        let guarantee = coordinator.restoreFromRegistrationMessage(message: message)
        pushNextController(guarantee)
    }

    func cancelChosenRestoreMethod() {
        let guarantee = coordinator.resetRestoreMode()
        pushNextController(guarantee)
    }
}

extension RegistrationNavigationController: RegistrationTransferStatusPresenter {
    func cancelTransfer() {
        let guarantee = coordinator.resetRestoreMode()
        pushNextController(guarantee)
    }
}

extension RegistrationNavigationController: RegistrationRestoreFromBackupConfirmationPresenter {
    func skipRestoreFromBackup() {
        let guarantee = coordinator.updateRestoreMethod(method: .declined)
        pushNextController(guarantee)
    }

    func cancelRestoreFromBackup() {
        let guarantee = coordinator.resetRestoreMethodChoice()
        pushNextController(guarantee)
    }

    func restoreFromBackupConfirmed() {
        Task { @MainActor in
            let progressModal = BackupProgressModal(style: .backupRestore)
            let (progress, stream) = await OWSSequentialProgress<BackupRestoreProgressPhase>.createSink()
            Task { @MainActor in
                for await progress in stream {
                    progressModal.viewModel.updateBackupRestoreProgress(progress: progress)
                }
            }
            let guarantee = coordinator.confirmRestoreFromBackup(progress: progress)
            pushNextController(guarantee, loadingMode: .restoringBackup(progressModal))
        }
    }
}

private protocol AnyController {

    var canCancel: Bool { get }

    var viewType: UIViewController.Type { get }

    func makeViewController(_: RegistrationNavigationController) -> UIViewController

    func updateViewController<T: UIViewController>(_: T) -> T?
}
