//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit

@objc
public protocol OnboardingController: class {
    func onboardingPermissionsWasSkipped(viewController: UIViewController)
    func onboardingPermissionsDidComplete(viewController: UIViewController)
}
