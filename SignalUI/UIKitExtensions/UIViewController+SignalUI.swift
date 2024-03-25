//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

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

    func pushViewController(_ viewController: UIViewController,
                            animated: Bool,
                            completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        pushViewController(viewController, animated: animated)
        CATransaction.commit()
    }

    func popViewController(animated: Bool,
                           completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        popViewController(animated: animated)
        CATransaction.commit()
    }

    func popToViewController(_ viewController: UIViewController,
                             animated: Bool,
                             completion: (() -> Void)?) {
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)
        self.popToViewController(viewController, animated: animated)
        CATransaction.commit()
    }
}
