//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public class RegistrationNavigationController: OWSNavigationController {

    private var coordinator: RegistrationCoordinator!

    public static func withCoordinator(_ coordinator: RegistrationCoordinator) -> RegistrationNavigationController {
        let vc = RegistrationNavigationController(coordinator: coordinator)
        vc.coordinator = coordinator
        return vc
    }

    private init(coordinator: RegistrationCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    // On iOS 12, init(navigationBarClass:toolbarClass:) calls
    // init(nibName:bundle:). In the latest iOS SDK, these are both marked as
    // designated initializers, so that shouldn't be allowed. In Objective-C,
    // this resolves to the superclass implementation and behaves properly, but
    // in Swift, it results in a crash. A no-op implementation avoids the crash
    // and results in the same behavior as in Objective-C.
    //
    // Subclass are required to implement this initializer if they implement
    // any other initializer. However, the initializer should *always* be an
    // empty shim that calls `super`. The compiler will force you to initialize
    // all ivars before calling `super` -- don’t do that. Instead, make ivars
    // `var` or optional so they don’t need to be modified in this initializer.
    required init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        if #available(iOS 13, *) {
            owsFailDebug("This initializer should never be explicitly executed.")
        }
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if viewControllers.isEmpty, !isLoading {
            pushNextController(coordinator.nextStep())
        }
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
            isLoading = true
            pushViewController(RegistrationLoadingViewController(mode: loadingMode), animated: false) { [weak self] in
                self?._pushNextController(step)
            }
        } else {
            _pushNextController(step)
        }
    }

    private func _pushNextController(_ step: Guarantee<RegistrationStep>) {
        isLoading = true
        step.done(on: DispatchQueue.main) { [weak self] step in
            guard let self else {
                return
            }
            self.isLoading = false
            guard let controller = self.controller(for: step) else {
                return
            }
            var controllerToPush: UIViewController?
            for viewController in self.viewControllers.reversed() {
                // If we already have this controller available, update it and pop to it.
                if type(of: viewController) == controller.viewType {
                    if let newController = controller.updateViewController(viewController) {
                        controllerToPush = newController
                    } else {
                        self.popToViewController(viewController, animated: true)
                        return
                    }
                }
            }
            // If we got here, there were no matches and we should push.
            let vc = controllerToPush ?? controller.makeViewController(self)
            self.pushViewController(vc, animated: true, completion: nil)
        }
    }

    private struct Controller<T: UIViewController>: AnyController {
        let type: T.Type
        let make: (RegistrationNavigationController) -> UIViewController
        // Return a new controller to push, or nil if it should reuse the same controller.
        let update: ((T) -> T?)?

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

    private func controller(for step: RegistrationStep) -> AnyController? {
        switch step {
        case .splash:
            return Controller(
                type: RegistrationSplashViewController.self,
                make: { presenter in
                    return RegistrationSplashViewController(presenter: presenter)
                },
                // No state to update.
                update: nil
            )
        case .permissions(let state):
            return Controller(
                type: RegistrationPermissionsViewController.self,
                make: { presenter in
                    return RegistrationPermissionsViewController(state: state, presenter: presenter)
                },
                // The state never changes here. In theory we would build
                // state update support in the permissions controller,
                // but its overkill so we have not.
                update: nil
            )
        case .phoneNumberEntry(let state):
            return Controller(
                type: RegistrationPhoneNumberViewController.self,
                make: { presenter in
                    return RegistrationPhoneNumberViewController(state: state, presenter: presenter)
                },
                update: { controller in
                    controller.updateState(state)
                    return nil
                }
            )
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
                update: { [weak self] oldController in
                    // TODO[Registration]: apply updates to state.
                    switch (oldController.state.operation, state.operation) {
                    case (.confirmingNewPin, .confirmingNewPin):
                        return nil
                    case (.creatingNewPin, .creatingNewPin):
                        return nil
                    case (.enteringExistingPin, .enteringExistingPin):
                        return nil
                    default:
                        guard let self else { return nil }
                        return RegistrationPinViewController(state: state, presenter: self)
                    }
                }
            )
        case .captchaChallenge:
            return Controller(
                type: RegistrationCaptchaViewController.self,
                make: { presenter in
                    return RegistrationCaptchaViewController(presenter: presenter)
                },
                // No state to update.
                update: nil
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
        case let .showErrorSheet(errorSheet):
            let title: String?
            let message: String
            switch errorSheet {
            case .sessionInvalidated:
                fatalError("Unimplemented")
            case .verificationCodeSubmissionUnavailable:
                fatalError("Unimplemented")
            case .pinGuessesExhausted:
                fatalError("Unimplemented")
            case .networkError:
                title = OWSLocalizedString(
                    "REGISTRATION_NETWORK_ERROR_TITLE",
                    comment: "A network error occurred during registration, and an error is shown to the user. This is the title on that error sheet."
                )
                message = OWSLocalizedString(
                    "REGISTRATION_NETWORK_ERROR_BODY",
                    comment: "A network error occurred during registration, and an error is shown to the user. This is the body on that error sheet."
                )
            case .genericError:
                title = nil
                message = CommonStrings.somethingWentWrongTryAgainLaterError
            case .todo:
                fatalError("TODO[Registration] This should be removed")
            }
            OWSActionSheets.showActionSheet(title: title, message: message) { [weak self] _ in
                guard let self else { return }
                self.pushNextController(self.coordinator.nextStep())
            }
            return nil
        case .appUpdateBanner:
            present(UIAlertController.registrationAppUpdateBanner(), animated: true)
            return nil
        case .done:
            Logger.info("Finished with registration!")
            SignalApp.shared().showConversationSplitView()
            return nil
        }
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        let superOrientations = super.supportedInterfaceOrientations
        let onboardingOrientations: UIInterfaceOrientationMask = UIDevice.current.isIPad ? .all : .portrait

        return superOrientations.intersection(onboardingOrientations)
    }
}

extension RegistrationNavigationController: RegistrationSplashPresenter {

    public func continueFromSplash() {
        pushNextController(coordinator.continueFromSplash())
    }
}

extension RegistrationNavigationController: RegistrationPermissionsPresenter {

    func requestPermissions() {
        pushNextController(coordinator.requestPermissions(), loadingMode: nil)
    }
}

extension RegistrationNavigationController: RegistrationPhoneNumberPresenter {

    func goToNextStep(withE164 e164: E164) {
        pushNextController(coordinator.submitE164(e164), loadingMode: .submittingPhoneNumber(e164: e164.stringValue))
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
}

extension RegistrationNavigationController: RegistrationTransferChoicePresenter {

    func transferDevice() {
        // We push these controllers right onto the same navigation stack, even though they
        // are not coordinator "steps". They have their own internal logic to proceed and go
        // back (direct calls to push and pop) and, when they complete, they will have _totally_
        // overwriten our local database, thus wiping any in progress reg coordinator state
        // and putting us into the chat list.
        pushViewController(RegistrationTransferQRCodeViewController(), animated: true, completion: nil)
    }

    func continueRegistration() {
        pushNextController(coordinator.skipDeviceTransfer())
    }
}

extension RegistrationNavigationController: RegistrationProfilePresenter {
    func goToNextStep(
        givenName: String,
        familyName: String?,
        avatarData: Data?,
        isDiscoverableByPhoneNumber: Bool
    ) {
        pushNextController(
            coordinator.setProfileInfo(
                givenName: givenName,
                familyName: familyName,
                avatarData: avatarData,
                isDiscoverableByPhoneNumber: isDiscoverableByPhoneNumber
            )
        )
    }
}

extension RegistrationNavigationController: RegistrationPhoneNumberDiscoverabilityPresenter {

    var presentedAsModal: Bool { return false }

    func setPhoneNumberDiscoverability(_ isDiscoverable: Bool) {
        pushNextController(coordinator.setPhoneNumberDiscoverability(isDiscoverable))
    }
}

extension RegistrationNavigationController: RegistrationReglockTimeoutPresenter {
    func acknowledgeReglockTimeout() {
        pushNextController(coordinator.acknowledgeReglockTimeout())
    }
}

private protocol AnyController {

    var viewType: UIViewController.Type { get }

    func makeViewController(_: RegistrationNavigationController) -> UIViewController

    func updateViewController<T: UIViewController>(_: T) -> T?
}
