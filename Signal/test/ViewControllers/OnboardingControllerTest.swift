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

    func test_toggleModeSwitch_whenOnboardingModeIsNotOverriden_showsPermissonScreen() {
        let sut = OnboardingController(onboardingMode: .registering)
        let viewController = UIViewController()
        let navigationController = UINavigationControllerSpy(rootViewController: viewController)

        XCTAssertFalse(sut.isOnboardingModeOverriden)

        sut.toggleModeSwitch(viewController: viewController)

        XCTAssertNotNil(navigationController.topViewController as? OnboardingPermissionsViewController)
    }

    func test_toggleModeSwitch_whenOnboardingModeIsOverriden_goesBackToRootView() {
        let sut = OnboardingController(onboardingMode: .registering)
        let viewController = UIViewController()
        viewController.title = "Root View"
        let navigationController = UINavigationControllerSpy(rootViewController: viewController)

        XCTAssertFalse(sut.isOnboardingModeOverriden)
        sut.toggleModeSwitch(viewController: viewController)
        XCTAssertNotNil(navigationController.topViewController as? OnboardingPermissionsViewController)

        XCTAssertTrue(sut.isOnboardingModeOverriden)
        sut.toggleModeSwitch(viewController: viewController)

        XCTAssertEqual(navigationController.topViewController?.title, "Root View")
    }

    func test_onboardingPermissionsWasSkipped_whenOnboardingModeIsProvisioning_showsTransferChoiceScreen() {
        let sut = OnboardingController(onboardingMode: .provisioning)
        let viewController = UIViewController()
        let navigationController = UINavigationControllerSpy(rootViewController: viewController)

        sut.onboardingPermissionsWasSkipped(viewController: viewController)

        XCTAssertNotNil(navigationController.topViewController as? OnboardingTransferChoiceViewController)
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
