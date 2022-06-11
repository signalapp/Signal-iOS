//
//  Copyright (c) 2022 Open Whisper Systems. All rights reserved.
//

import XCTest
import UIKit
@testable import Signal

class OnboardingControllerTest: SignalBaseTest {

    func test_onboardingSplashDidComplete_showsOnboardingPermissionsScreen() {
        let sut = OnboardingController(onboardingMode: .registering)
        let viewController = UIViewController()
        let navigationController = UINavigationControllerSpy(rootViewController: viewController)

        sut.onboardingSplashDidComplete(viewController: viewController)

        XCTAssertNotNil(navigationController.currentViewController as? OnboardingPermissionsViewController)
    }

    func test_onboardingSplashRequestedModeSwitch_showsConfirmationScreen() {
        let sut = OnboardingController(onboardingMode: .registering)
        let viewController = UIViewController()
        let navigationController = UINavigationControllerSpy(rootViewController: viewController)

        sut.onboardingSplashRequestedModeSwitch(viewController: viewController)

        XCTAssertNotNil(navigationController.currentViewController as? OnboardingModeSwitchConfirmationViewController)
    }
}

// MARK: - Helpers

class UINavigationControllerSpy: UINavigationController {
    var currentViewController: UIViewController?

    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        super.pushViewController(viewController, animated: false)
        currentViewController = viewController
    }
}
