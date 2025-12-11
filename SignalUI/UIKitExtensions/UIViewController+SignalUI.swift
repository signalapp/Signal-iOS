//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit
import SignalServiceKit

public extension UIViewController {

    var owsNavigationController: OWSNavigationController? {
        return navigationController as? OWSNavigationController
    }

    func findFrontmostViewController(ignoringAlerts: Bool) -> UIViewController {
        var visitedViewControllers = Set<UIViewController>()
        var viewController = self

        while true {
            visitedViewControllers.insert(viewController)

            if let nextViewController = viewController.presentedViewController {
                let isNextViewControllerAlert =
                (nextViewController is ActionSheetController) || (nextViewController is UIAlertController)

                if !ignoringAlerts || !isNextViewControllerAlert {
                    guard visitedViewControllers.insert(nextViewController).inserted else {
                        return viewController
                    }
                    viewController = nextViewController
                    continue
                }
            }

            guard let navigationController = viewController as? UINavigationController,
                  let nextViewController = navigationController.topViewController else { break }

            guard visitedViewControllers.insert(nextViewController).inserted else {
                return viewController
            }

            viewController = nextViewController
        }

        return viewController
    }
}

// MARK: -

public extension UIViewController {

    func presentActionSheet(
        _ actionSheet: ActionSheetController,
        animated: Bool = true,
        completion: (() -> Void)? = nil
    ) {
        present(actionSheet, animated: animated, completion: completion)
    }

    /// A convenience function to present a modal view full screen, not using
    /// the default card style added in iOS 13.
    func presentFullScreen(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        viewControllerToPresent.modalPresentationStyle = .fullScreen
        present(viewControllerToPresent, animated: animated, completion: completion)
    }

    func presentFormSheet(_ viewControllerToPresent: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        // Presenting form sheet on iPhone should always use the default presentation style.
        // We get this for free, except on phones with the regular width size class (big phones
        // in landscape, XR, XS Max, 8+, etc.)
        if UIDevice.current.isIPad {
            viewControllerToPresent.modalPresentationStyle = .formSheet
        }
        present(viewControllerToPresent, animated: animated, completion: completion)
    }
}

// MARK: -

public extension UINavigationController {

    func pushViewController(
        _ viewController: UIViewController,
        animated: Bool,
        completion: @escaping () -> Void
    ) {
        pushViewController(viewController, animated: animated)
        addCompletion(animated: animated, completion: completion)
    }

    func popViewController(
        animated: Bool,
        completion: @escaping () -> Void
    ) {
        popViewController(animated: animated)
        addCompletion(animated: animated, completion: completion)
    }

    func popToViewController(
        _ viewController: UIViewController,
        animated: Bool,
        completion: @escaping () -> Void
    ) {
        self.popToViewController(viewController, animated: animated)
        addCompletion(animated: animated, completion: completion)
    }

    private func addCompletion(animated: Bool, completion: @escaping () -> Void) {
        guard animated else { return completion() }
        guard let transitionCoordinator else {
            owsFailBeta("Missing transitionCoordinator even though transition is animated")
            return completion()
        }
        transitionCoordinator.animate(alongsideTransition: nil) { _ in
            completion()
        }
    }

    func awaitablePush(_ viewController: UIViewController, animated: Bool) async {
        await withCheckedContinuation { continuation in
            self.pushViewController(viewController, animated: animated) {
                continuation.resume()
            }
        }
    }
}

// MARK: -

public extension UIViewController {
    func awaitableDismiss(animated: Bool) async {
        await withCheckedContinuation { continuation in
            self.dismiss(animated: animated) {
                continuation.resume()
            }
        }
    }

    func awaitablePresent(_ viewController: UIViewController, animated: Bool) async {
        await withCheckedContinuation { continuation in
            self.present(viewController, animated: animated) {
                continuation.resume()
            }
        }
    }

    func awaitablePresentFormSheet(_ viewController: UIViewController, animated: Bool) async {
        await withCheckedContinuation { continuation in
            self.presentFormSheet(viewController, animated: animated) {
                continuation.resume()
            }
        }
    }
}
