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

    func test_onboardingPermissionsWasSkipped_whenOnboardingModeIsRegistering_showsPhoneNumberScreen() {
        let sut = OnboardingController(onboardingMode: .registering)
        let viewController = UIViewController()
        let navigationController = UINavigationControllerSpy(rootViewController: viewController)

        sut.onboardingPermissionsWasSkipped(viewController: viewController)

        XCTAssertNotNil(navigationController.topViewController as? RegistrationPhoneNumberViewController)
    }

    func test_onboardingPermissionsDidComplete_whenOnboardingModeIsProvisioning_showsTransferChoiceScreen() {
        let sut = OnboardingController(onboardingMode: .provisioning)
        let viewController = UIViewController()
        let navigationController = UINavigationControllerSpy(rootViewController: viewController)

        sut.onboardingPermissionsDidComplete(viewController: viewController)

        XCTAssertNotNil(navigationController.topViewController as? OnboardingTransferChoiceViewController)
    }

    func test_onboardingPermissionsDidComplete_whenOnboardingModeIsRegistering_showsPhoneNumberScreen() {
        let sut = OnboardingController(onboardingMode: .registering)
        let viewController = UIViewController()
        let navigationController = UINavigationControllerSpy(rootViewController: viewController)

        sut.onboardingPermissionsDidComplete(viewController: viewController)

        XCTAssertNotNil(navigationController.topViewController as? RegistrationPhoneNumberViewController)
    }

    func test_requestingVerificationDidSucceed_showsVerificationScreen() {
        let sut = OnboardingController(onboardingMode: .registering)
        let viewController = UIViewController()
        let navigationController = UINavigationControllerSpy(rootViewController: viewController)

        sut.requestingVerificationDidSucceed(viewController: viewController)

        XCTAssertNotNil(navigationController.topViewController as? OnboardingVerificationViewController)
    }

    func test_onboardingDidRequireCaptcha_showsCaptchaScreen() {
        let sut = OnboardingController(onboardingMode: .registering)
        let viewController = UIViewController()
        let navigationController = UINavigationControllerSpy(rootViewController: viewController)

        sut.onboardingDidRequireCaptcha(viewController: viewController)

        XCTAssertNotNil(navigationController.topViewController as? OnboardingCaptchaViewController)
    }

    func test_onboardingDidRequireCaptcha_withMultipleScreensAndCurrentIsNotPhoneRegistration_goBackToInitialScreen() {
        let sut = OnboardingController(onboardingMode: .registering)
        let viewController1 = UIViewController()
        viewController1.title = "View 1"
        let viewController2 = UIViewController()
        viewController2.title = "View 2"
        let viewController3 = UIViewController()
        viewController3.title = "View 3"
        let navigationController = UINavigationControllerSpy(rootViewController: viewController1)

        navigationController.pushViewController(viewController2, animated: false)
        navigationController.pushViewController(viewController3, animated: false)
        sut.onboardingDidRequireCaptcha(viewController: viewController3)

        XCTAssertEqual(navigationController.viewControllers.count, 2)
        XCTAssertEqual(navigationController.viewControllers.first?.title, "View 1")
        XCTAssertNotNil(navigationController.topViewController as? OnboardingCaptchaViewController)
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
