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

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if viewControllers.isEmpty, !isLoading {
            pushNextController(coordinator.nextStep())
        }
    }

    private var isLoading = false

    private func pushNextController(_ step: Guarantee<RegistrationStep>) {
        guard !isLoading else {
            owsFailDebug("Parallel loads not allowed")
            return
        }

        // TODO[Registration]: we want to show loading under other circumstances, too.
        if self.viewControllers.isEmpty {
            pushViewController(RegistrationLoadingViewController(mode: .initialLoad), animated: false, completion: nil)
        }
        isLoading = true
        step.done(on: DispatchQueue.main) { [weak self] step in
            guard let self else {
                return
            }
            self.isLoading = false
            let controller = self.controller(for: step)
            for viewController in self.viewControllers.reversed() {
                // If we already have this controller available, update it and pop to it.
                if type(of: viewController) == controller.viewType {
                    controller.updateViewController(viewController)
                    self.popToViewController(viewController, animated: true)
                    return
                }
            }
            // If we got here, there were no matches and we should push.
            let vc = controller.makeViewController(self)
            self.pushViewController(vc, animated: true, completion: nil)
        }
    }

    private struct Controller<T: UIViewController>: AnyController {
        let type: T.Type
        let make: (RegistrationNavigationController) -> UIViewController
        let update: ((T) -> Void)?

        var viewType: UIViewController.Type { T.self }

        func makeViewController(_ presenter: RegistrationNavigationController) -> UIViewController {
            return make(presenter)
        }

        func updateViewController<U>(_ vc: U) where U: UIViewController {
            guard let vc = vc as? T else {
                owsFailDebug("Invalid view controller type")
                return
            }
            update?(vc)
        }
    }

    private func controller(for step: RegistrationStep) -> AnyController {
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

extension RegistrationNavigationController: RegistrationSplashPresenter {

    public func continueFromSplash() {
        pushNextController(coordinator.continueFromSplash())
    }
}

private protocol AnyController {

    var viewType: UIViewController.Type { get }

    func makeViewController(_: RegistrationNavigationController) -> UIViewController

    func updateViewController<T: UIViewController>(_: T)
}
