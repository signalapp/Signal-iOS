//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation

public class RegistrationNavigationController: OWSNavigationController {

    private let coordinator: RegistrationCoordinator

    public init(coordinator: RegistrationCoordinator) {
        self.coordinator = coordinator
        super.init()
    }

    public func pushNextController() {
        if self.viewControllers.isEmpty {
            pushViewController(RegistrationLoadingViewController(mode: .initialLoad), animated: false, completion: nil)
        }
        coordinator.nextStep().done(on: DispatchQueue.main) { [weak self] step in
            guard let self else {
                return
            }
            self.pushViewController(self.controller(for: step), animated: true, completion: nil)
        }
    }

    private func controller(for step: RegistrationStep) -> UIViewController {
        switch step {
        case .splash:
            return RegistrationSplashViewController()
        case .permissions:
            fatalError("Unimplemented")
        case .phoneNumberEntry:
            fatalError("Unimplemented")
        case .verificationCodeEntry:
            fatalError("Unimplemented")
        case .transferSelection:
            fatalError("Unimplemented")
        case .pinEntry:
            fatalError("Unimplemented")
        case .captchaChallenge:
            fatalError("Unimplemented")
        case .phoneNumberDiscoverability:
            fatalError("Unimplemented")
        case .setupProfile:
            fatalError("Unimplemented")
        case .showGenericError:
            fatalError("Unimplemented")
        case .appUpdateBanner:
            fatalError("Unimplemented")
        case .done:
            fatalError("Unimplemented")
        }
    }

    @available(*, unavailable)
    required init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        fatalError("init(nibName:bundle:) has not been implemented")
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        let superOrientations = super.supportedInterfaceOrientations
        let onboardingOrientations: UIInterfaceOrientationMask = UIDevice.current.isIPad ? .all : .portrait

        return superOrientations.intersection(onboardingOrientations)
    }
}
