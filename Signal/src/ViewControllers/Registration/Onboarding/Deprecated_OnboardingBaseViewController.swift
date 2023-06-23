//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

public class Deprecated_OnboardingBaseViewController: Deprecated_RegistrationBaseViewController {

    // Unlike a delegate, we can and should retain a strong reference to the OnboardingController.
    let onboardingController: Deprecated_OnboardingController

    public init(onboardingController: Deprecated_OnboardingController) {
        self.onboardingController = onboardingController

        super.init()
    }

    func shouldShowBackButton() -> Bool {
        return onboardingController.onboardingMode != Deprecated_OnboardingController.defaultOnboardingMode
    }

    // MARK: - View Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        if shouldShowBackButton() {
            let backButton = UIButton()
            backButton.setTemplateImage(UIImage(imageLiteralResourceName: "NavBarBack"), tintColor: Theme.secondaryTextAndIconColor)
            backButton.addTarget(self, action: #selector(navigateBack), for: .touchUpInside)

            view.addSubview(backButton)
            backButton.autoSetDimensions(to: CGSize(square: 40))
            backButton.autoPinEdge(toSuperviewMargin: .leading)
            backButton.autoPinEdge(toSuperviewMargin: .top)
        }
    }
}
