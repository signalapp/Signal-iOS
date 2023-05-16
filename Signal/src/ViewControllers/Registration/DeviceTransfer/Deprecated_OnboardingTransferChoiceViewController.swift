//
// Copyright 2020 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import UIKit

public class Deprecated_OnboardingTransferChoiceViewController: Deprecated_OnboardingBaseViewController {

    public override var primaryLayoutMargins: UIEdgeInsets {
        var defaultMargins = super.primaryLayoutMargins

        switch traitCollection.horizontalSizeClass {
        case .unspecified, .compact:
            // we want the choice buttons to have less padding on the left and right.
            // on iPhone. consequently, we will need to add an extra 16 to all the text
            // on this page.
            defaultMargins.left = 16
            defaultMargins.right = 16
        case .regular:
            break
        @unknown default:
            break
        }

        return defaultMargins
    }

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.createTitleLabel(
            text: OWSLocalizedString("DEVICE_TRANSFER_CHOICE_TITLE",
                                    comment: "The title for the device transfer 'choice' view")
        )
        titleLabel.accessibilityIdentifier = "onboarding.transferChoice." + "titleLabel"

        let explanationText: String
        let transferTitle: String
        let transferBody: String
        let registerTitle: String
        let registerBody: String
        switch onboardingController.onboardingMode {
        case .provisioning:
            explanationText = OWSLocalizedString("DEVICE_TRANSFER_CHOICE_LINKED_EXPLANATION",
                                                comment: "The explanation for the device transfer 'choice' view when linking a device")

            transferTitle = OWSLocalizedString("DEVICE_TRANSFER_CHOICE_TRANSFER_LINKED_TITLE",
                                              comment: "The title for the device transfer 'choice' view 'transfer' option when linking a device")
            transferBody = OWSLocalizedString("DEVICE_TRANSFER_CHOICE_TRANSFER_LINKED_BODY",
                                             comment: "The body for the device transfer 'choice' view 'transfer' option when linking a device")

            registerTitle = OWSLocalizedString("DEVICE_TRANSFER_CHOICE_REGISTER_LINKED_TITLE",
                                              comment: "The title for the device transfer 'choice' view 'register' option when linking a device")
            registerBody = OWSLocalizedString("DEVICE_TRANSFER_CHOICE_REGISTER_LINKED_BODY",
                                             comment: "The body for the device transfer 'choice' view 'register' option when linking a device")
        case .registering:
            explanationText = OWSLocalizedString("DEVICE_TRANSFER_CHOICE_EXPLANATION",
                                                comment: "The explanation for the device transfer 'choice' view")

            transferTitle = OWSLocalizedString("DEVICE_TRANSFER_CHOICE_TRANSFER_TITLE",
                                              comment: "The title for the device transfer 'choice' view 'transfer' option")
            transferBody = OWSLocalizedString("DEVICE_TRANSFER_CHOICE_TRANSFER_BODY",
                                             comment: "The body for the device transfer 'choice' view 'transfer' option")

            registerTitle = OWSLocalizedString("DEVICE_TRANSFER_CHOICE_REGISTER_TITLE",
                                              comment: "The title for the device transfer 'choice' view 'register' option")
            registerBody = OWSLocalizedString("DEVICE_TRANSFER_CHOICE_REGISTER_BODY",
                                             comment: "The body for the device transfer 'choice' view 'register' option")
        }

        let explanationLabel = self.createExplanationLabel(explanationText: explanationText)
        explanationLabel.accessibilityIdentifier = "onboarding.transferChoice." + "explanationLabel"

        let warningLabel = self.createExplanationLabel(
            explanationText: OWSLocalizedString("DEVICE_TRANSFER_CHOICE_WARNING",
                                               comment: "A warning for the device transfer 'choice' view indicating you can only have one device registered with your number")
        )
        warningLabel.accessibilityIdentifier = "onboarding.transferChoice." + "warningLabel"

        let transferButton = choiceButton(
            title: transferTitle,
            body: transferBody,
            iconName: Theme.iconName(.transfer),
            selector: #selector(didSelectTransfer)
        )
        transferButton.accessibilityIdentifier = "onboarding.transferChoice." + "transferButton"

        let registerButton = choiceButton(
            title: registerTitle,
            body: registerBody,
            iconName: Theme.iconName(.register),
            selector: #selector(didSelectRegister)
        )
        registerButton.accessibilityIdentifier = "onboarding.transferChoice." + "registerButton"

        let topStackView = UIStackView(arrangedSubviews: [
            titleLabel,
            UIView.spacer(withHeight: 12),
            explanationLabel
        ])
        topStackView.axis = .vertical
        topStackView.alignment = .fill
        topStackView.isLayoutMarginsRelativeArrangement = true
        topStackView.layoutMargins = UIEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)

        let bottomStackView = UIStackView(arrangedSubviews: [warningLabel])
        bottomStackView.axis = .vertical
        bottomStackView.alignment = .fill
        bottomStackView.isLayoutMarginsRelativeArrangement = true
        bottomStackView.layoutMargins = UIEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        bottomStackView.isHidden = onboardingController.onboardingMode == .provisioning

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let stackView = UIStackView(arrangedSubviews: [
            topStackView,
            topSpacer,
            transferButton,
            UIView.spacer(withHeight: 12),
            registerButton,
            bottomSpacer,
            bottomStackView
        ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        primaryView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)
    }

    func choiceButton(title: String, body: String, iconName: String, selector: Selector) -> OWSFlatButton {
        let button = OWSFlatButton()
        button.setBackgroundColors(upColor: Theme.isDarkThemeEnabled ? .ows_gray80 : .ows_gray02)
        button.layer.cornerRadius = 8
        button.clipsToBounds = true

        // Icon

        let iconContainer = UIView()
        let iconView = UIImageView(image: UIImage(named: iconName))
        iconView.contentMode = .scaleAspectFit
        iconContainer.addSubview(iconView)
        iconView.autoPinWidthToSuperview()
        iconView.autoSetDimensions(to: CGSize(square: 60))
        iconView.autoVCenterInSuperview()
        iconView.autoMatch(.height, to: .height, of: iconContainer, withOffset: 0, relation: .lessThanOrEqual)

        // Labels

        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.font = UIFont.dynamicTypeBody.semibold()
        titleLabel.textColor = Theme.primaryTextColor

        let bodyLabel = UILabel()
        bodyLabel.text = body
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.font = .dynamicTypeBody2
        bodyLabel.textColor = Theme.secondaryTextAndIconColor

        let topSpacer = UIView.vStretchingSpacer()
        let bottomSpacer = UIView.vStretchingSpacer()

        let vStack = UIStackView(arrangedSubviews: [
            topSpacer,
            titleLabel,
            bodyLabel,
            bottomSpacer
        ])
        vStack.axis = .vertical
        vStack.spacing = 8

        topSpacer.autoMatch(.height, to: .height, of: bottomSpacer)

        // Disclosure Indicator

        let disclosureIconName = CurrentAppContext().isRTL ? "chevron-left-20" : "chevron-right-20"

        let disclosureContainer = UIView()
        let disclosureView = UIImageView()
        disclosureView.setTemplateImageName(disclosureIconName, tintColor: Theme.secondaryTextAndIconColor)
        disclosureView.contentMode = .scaleAspectFit
        disclosureContainer.addSubview(disclosureView)
        disclosureView.autoPinEdgesToSuperviewEdges()
        disclosureView.autoSetDimension(.width, toSize: 20)

        let hStack = UIStackView(arrangedSubviews: [
            iconContainer,
            vStack,
            disclosureContainer
        ])
        hStack.axis = .horizontal
        hStack.spacing = 16
        hStack.isLayoutMarginsRelativeArrangement = true
        hStack.layoutMargins = UIEdgeInsets(top: 24, leading: 10, bottom: 24, trailing: 8.5)
        hStack.isUserInteractionEnabled = false

        button.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewEdges()

        button.addTarget(target: self, selector: selector)

        return button
    }

    // MARK: - Events

    @objc
    private func didSelectTransfer() {
        Logger.info("")

        switch onboardingController.onboardingMode {
        case .provisioning:
            let prepViewController = Deprecated_SecondaryLinkingPrepViewController(onboardingController: onboardingController, isTransferring: true)
            navigationController?.pushViewController(prepViewController, animated: true)
        case .registering:
            onboardingController.transferAccount(fromViewController: self)
        }
    }

    @objc
    private func didSelectRegister() {
        Logger.info("")

        switch onboardingController.onboardingMode {
        case .provisioning:
            let prepViewController = Deprecated_SecondaryLinkingPrepViewController(onboardingController: onboardingController, isTransferring: false)
            navigationController?.pushViewController(prepViewController, animated: true)
        case .registering:
            onboardingController.submitVerification(fromViewController: self, checkForAvailableTransfer: false, completion: { outcome in
                guard outcome != .success else { return }
                owsFailDebug("Unexpected error on transfer choice view \(outcome)")
            })
        }
    }
}
