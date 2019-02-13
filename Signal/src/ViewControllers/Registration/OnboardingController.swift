//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public protocol OnboardingController: class {
    func initialViewController() -> UIViewController

    func onboardingSplashDidComplete(viewController: UIViewController)

    func onboardingPermissionsWasSkipped(viewController: UIViewController)
    func onboardingPermissionsDidComplete(viewController: UIViewController)
}

// MARK: -

@objc
public class OnboardingControllerImpl: NSObject, OnboardingController {
    public func initialViewController() -> UIViewController {
        let view = OnboardingSplashViewController(onboardingController: self)
        return view
    }

    public func onboardingSplashDidComplete(viewController: UIViewController) {
        let view = OnboardingPermissionsViewController(onboardingController: self)
        viewController.navigationController?.pushViewController(view, animated: true)
    }

    public func onboardingPermissionsWasSkipped(viewController: UIViewController) {}

    public func onboardingPermissionsDidComplete(viewController: UIViewController) {}
}
