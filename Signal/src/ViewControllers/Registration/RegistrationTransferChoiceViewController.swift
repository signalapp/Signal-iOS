//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - RegistrationTransferChoicePresenter

protocol RegistrationTransferChoicePresenter: AnyObject {
    func transferDevice()
    func continueRegistration()
}

// MARK: - RegistrationTransferChoiceViewController

class RegistrationTransferChoiceViewController: OWSViewController {
    private weak var presenter: RegistrationTransferChoicePresenter?

    public init(presenter: RegistrationTransferChoicePresenter) {
        self.presenter = presenter

        super.init()
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    // MARK: Rendering

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "REGISTRATION_DEVICE_TRANSFER_CHOICE_TITLE",
            comment: "If a user is installing Signal on a new phone, they may be asked whether they want to transfer their account from their old device. This is the title on the screen that asks them this question."
        ))
        result.accessibilityIdentifier = "registration.transferChoice.titleLabel"
        return result
    }()

    private lazy var explanationLabel: UILabel = {
        let result = UILabel.explanationLabelForRegistration(text: OWSLocalizedString(
            "REGISTRATION_DEVICE_TRANSFER_CHOICE_EXPLANATION",
            comment: "If a user is installing Signal on a new phone, they may be asked whether they want to transfer their account from their old device. This is a description on the screen that asks them this question."
        ))
        result.accessibilityIdentifier = "registration.transferChoice.explanationLabel"
        return result
    }()

    private func choiceButton(
        title: String,
        body: String,
        iconName: String,
        selector: Selector,
        accessibilityIdentifierSuffix: String
    ) -> OWSFlatButton {
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

        let disclosureContainer = UIView()
        let disclosureView = UIImageView()
        disclosureView.setTemplateImage(
            UIImage(imageLiteralResourceName: "chevron-right-20"),
            tintColor: Theme.secondaryTextAndIconColor
        )
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
        hStack.layoutMargins = UIEdgeInsets(top: 24, leading: 16, bottom: 24, trailing: 16)
        hStack.isUserInteractionEnabled = false

        button.addSubview(hStack)
        hStack.autoPinEdgesToSuperviewEdges()

        button.addTarget(target: self, selector: selector)

        button.accessibilityIdentifier = "registration.transferChoice.\(accessibilityIdentifierSuffix)"

        return button
    }

    private lazy var transferButton = choiceButton(
        title: OWSLocalizedString(
            "DEVICE_TRANSFER_CHOICE_TRANSFER_TITLE",
            comment: "The title for the device transfer 'choice' view 'transfer' option"
        ),
        body: OWSLocalizedString(
            "DEVICE_TRANSFER_CHOICE_TRANSFER_BODY",
            comment: "The body for the device transfer 'choice' view 'transfer' option"
        ),
        iconName: Theme.iconName(.transfer),
        selector: #selector(didSelectTransfer),
        accessibilityIdentifierSuffix: "transferButton"
    )

    private lazy var registerButton = choiceButton(
        title: OWSLocalizedString(
            "DEVICE_TRANSFER_CHOICE_REGISTER_TITLE",
            comment: "The title for the device transfer 'choice' view 'register' option"
        ),
        body: OWSLocalizedString(
            "DEVICE_TRANSFER_CHOICE_REGISTER_BODY",
            comment: "The body for the device transfer 'choice' view 'register' option"
        ),
        iconName: Theme.iconName(.register),
        selector: #selector(didSelectRegister),
        accessibilityIdentifierSuffix: "registerButton"
    )

    public override func viewDidLoad() {
        super.viewDidLoad()

        initialRender()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render()
    }

    private func initialRender() {
        navigationItem.setHidesBackButton(true, animated: false)

        let scrollView = UIScrollView()
        view.addSubview(scrollView)
        scrollView.autoPinEdgesToSuperviewMargins()

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            explanationLabel,
            registerButton,
            transferButton,
            UIView.vStretchingSpacer()
        ])
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 16
        stackView.setCustomSpacing(12, after: titleLabel)
        stackView.setCustomSpacing(24, after: explanationLabel)
        scrollView.addSubview(stackView)
        stackView.autoPinWidth(toWidthOf: scrollView)
        stackView.autoPinHeightToSuperview()

        render()
    }

    private func render() {
        view.backgroundColor = Theme.backgroundColor
        titleLabel.textColor = .colorForRegistrationTitleLabel
        explanationLabel.textColor = .colorForRegistrationExplanationLabel
        // TODO: The buttons should also change color here.
    }

    // MARK: Events

    @objc
    private func didSelectTransfer() {
        Logger.info("")

        presenter?.transferDevice()
    }

    @objc
    private func didSelectRegister() {
        Logger.info("")

        presenter?.continueRegistration()
    }
}
