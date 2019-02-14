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

    func onboardingPhoneNumberDidComplete(viewController: UIViewController)
}

// MARK: -

@objc
public class OnboardingControllerImpl: NSObject, OnboardingController {

    // MARK: - Factory Methods

    public func initialViewController() -> UIViewController {
        let view = OnboardingSplashViewController(onboardingController: self)
        return view
    }

    // MARK: - Transitions

    public func onboardingSplashDidComplete(viewController: UIViewController) {
        let view = OnboardingPermissionsViewController(onboardingController: self)
        viewController.navigationController?.pushViewController(view, animated: true)
    }

    public func onboardingPermissionsWasSkipped(viewController: UIViewController) {
        pushPhoneNumberView(viewController: viewController)
    }

    public func onboardingPermissionsDidComplete(viewController: UIViewController) {
        pushPhoneNumberView(viewController: viewController)
    }

    private func pushPhoneNumberView(viewController: UIViewController) {
        let view = OnboardingPhoneNumberViewController(onboardingController: self)
        viewController.navigationController?.pushViewController(view, animated: true)
    }

    public func onboardingPhoneNumberDidComplete(viewController: UIViewController) {
        //        CodeVerificationViewController *vc = [CodeVerificationViewController new];
        //        [weakSelf.navigationController pushViewController:vc animated:YES];
    }

    public func onboardingPhoneNumberDidRequireCaptcha(viewController: UIViewController) {
        let view = OnboardingCaptchaViewController(onboardingController: self)
        viewController.navigationController?.pushViewController(view, animated: true)
    }
}
