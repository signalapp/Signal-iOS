//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation
import SignalCoreKit
import UIKit

@objc
public extension RegistrationUtils {

    static func reregister(fromViewController: UIViewController) {
        AssertIsOnMainThread()

        guard tsAccountManager.resetForReregistration(),
              let phoneNumber = Self.tsAccountManager.reregistrationPhoneNumber()?.nilIfEmpty else {
            owsFailDebug("could not reset for re-registration.")
            return
        }

        Logger.info("phoneNumber: \(phoneNumber)")

        Self.preferences.unsetRecordedAPNSTokens()

        let onboardingController = OnboardingController()
        owsAssertDebug(!onboardingController.isComplete)
        signalApp.showOnboardingView(onboardingController)

        AppUpdateNag.shared.showAppUpgradeNagIfNecessary()

        UIViewController.attemptRotationToDeviceOrientation()
    }
}
