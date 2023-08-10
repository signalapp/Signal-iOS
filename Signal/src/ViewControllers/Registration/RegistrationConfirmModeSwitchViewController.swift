//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging
import SignalUI

protocol RegistrationConfimModeSwitchPresenter: AnyObject {

    func confirmSwitchToDeviceLinkingMode()
}

class RegistrationConfirmModeSwitchViewController: OWSViewController {
    var warningText: String?

    weak var presenter: RegistrationConfimModeSwitchPresenter?

    public init(presenter: RegistrationConfimModeSwitchPresenter) {
        self.presenter = presenter
        super.init()
    }

    override func loadView() {
        view = UIView()

        view.backgroundColor = Theme.backgroundColor

        let titleText = OWSLocalizedString("ONBOARDING_MODE_SWITCH_TITLE_REGISTERING",
                                      comment: "header text indicating to the user they're switching from registering to linking flow")
        let explanationText = OWSLocalizedString("ONBOARDING_MODE_SWITCH_EXPLANATION_REGISTERING",
                                            comment: "explanation to the user they're switching from registering to linking flow")

        let nextButtonText = OWSLocalizedString("ONBOARDING_MODE_SWITCH_BUTTON_REGISTERING",
                                           comment: "button indicating that the user will link their phone")

        warningText = OWSLocalizedString("ONBOARDING_MODE_SWITCH_WARNING_REGISTERING",
                                        comment: "warning to the user that linking a phone is not recommended")

        let titleLabel = UILabel.titleLabelForRegistration(text: titleText)

        let explanationLabel = UILabel.explanationLabelForRegistration(text: explanationText)

        let nextButton = OWSFlatButton.primaryButtonForRegistration(
            title: nextButtonText,
            target: self,
            selector: #selector(didPressNext)
        )
        nextButton.accessibilityIdentifier = "onboarding.modeSwitch.nextButton"
        let primaryButtonView = ProvisioningBaseViewController.horizontallyWrap(primaryButton: nextButton)

        let topSpacer = UIView.vStretchingSpacer(minHeight: 12)
        let bottomSpacer = UIView.vStretchingSpacer(minHeight: 12)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 12),
            explanationLabel,
            topSpacer,
            bottomSpacer,
            primaryButtonView
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12
        view.addSubview(stackView)

        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        stackView.autoPinEdgesToSuperviewMargins()
    }

    @objc
    func didPressNext() {
        let actionSheet = ActionSheetController(message: warningText)

        let continueAction = ActionSheetAction(
            title: CommonStrings.continueButton,
            accessibilityIdentifier: "onboarding.modeSwitch.continue",
            handler: { [weak self] _ in
                self?.presenter?.confirmSwitchToDeviceLinkingMode()
            }
        )
        actionSheet.addAction(continueAction)
        actionSheet.addAction(OWSActionSheets.cancelAction)

        presentActionSheet(actionSheet)
    }
}
