//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit
import SignalUI

// MARK: - RegistrationChangePhoneNumberConfirmationPresenter

protocol RegistrationChangePhoneNumberConfirmationPresenter: AnyObject {
    func confirmChangeNumber(newE164: E164)

    func returnToPhoneNumberEntry()
}

// MARK: - RegistrationChangePhoneNumberConfirmationViewController

final class RegistrationChangePhoneNumberConfirmationViewController: OWSViewController, OWSNavigationChildController {

    public var preferredNavigationBarStyle: OWSNavigationBarStyle {
        return .solid
    }

    public var navbarBackgroundColorOverride: UIColor? {
        return view.backgroundColor
    }

    private var state: RegistrationPhoneNumberViewState.ChangeNumberConfirmation
    private weak var presenter: RegistrationChangePhoneNumberConfirmationPresenter?

    private let rootView = UIStackView()

    public init(
        state: RegistrationPhoneNumberViewState.ChangeNumberConfirmation,
        presenter: RegistrationChangePhoneNumberConfirmationPresenter
    ) {
        self.state = state
        self.presenter = presenter
        super.init()
    }

    public func updateState(_ state: RegistrationPhoneNumberViewState.ChangeNumberConfirmation) {
        self.state = state
        updateContents()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_VIEW_TITLE",
                                  comment: "Title for the 'change phone number' views in settings.")

        rootView.axis = .vertical
        rootView.alignment = .fill
        rootView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rootView)
        NSLayoutConstraint.activate([
            rootView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            rootView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            rootView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            rootView.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
        ])

        updateContents()
    }

    private var rateLimitErrorTimer: Timer?

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateContents()

        // We only need this timer if the user has been rate limited, but it's simpler to always
        // start it.
        rateLimitErrorTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateContents()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)

        rateLimitErrorTimer?.invalidate()
        rateLimitErrorTimer = nil
    }

    public override func themeDidChange() {
        super.themeDidChange()

        updateContents()
    }

    private func updateContents() {
        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)

        let descriptionFormat = OWSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_CONFIRM_DESCRIPTION_FORMAT",
                                                  comment: "Format for the description text in the 'change phone number splash' view. Embeds: {{ %1$@ the old phone number, %2$@ the new phone number }}.")
        let oldPhoneNumberFormatted = PhoneNumber.bestEffortLocalizedPhoneNumber(e164: state.oldE164.stringValue)
        let newPhoneNumberFormatted = PhoneNumber.bestEffortLocalizedPhoneNumber(e164: state.newE164.stringValue)
        let descriptionText = String(
            format: descriptionFormat,
            oldPhoneNumberFormatted,
            newPhoneNumberFormatted
        )
        let descriptionAttributedText = NSMutableAttributedString(string: descriptionText)
        descriptionAttributedText.setAttributes(
            [.foregroundColor: Theme.primaryTextColor],
            forSubstring: oldPhoneNumberFormatted
        )
        descriptionAttributedText.setAttributes(
            [.foregroundColor: Theme.primaryTextColor],
            forSubstring: newPhoneNumberFormatted
        )

        let descriptionLabel = UILabel()
        descriptionLabel.font = .dynamicTypeBody
        descriptionLabel.textColor = Theme.secondaryTextAndIconColor
        descriptionLabel.attributedText = descriptionAttributedText
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping

        let phoneNumberLabel = UILabel()
        phoneNumberLabel.font = .dynamicTypeTitle2.semibold()
        phoneNumberLabel.textColor = Theme.primaryTextColor
        phoneNumberLabel.text = newPhoneNumberFormatted
        phoneNumberLabel.textAlignment = .center
        let phoneNumberStack = UIStackView(arrangedSubviews: [phoneNumberLabel])
        phoneNumberStack.axis = .vertical
        phoneNumberStack.alignment = .center
        phoneNumberStack.isLayoutMarginsRelativeArrangement = true
        phoneNumberStack.layoutMargins = UIEdgeInsets(hMargin: 24, vMargin: 24)
        let phoneNumberBackground = phoneNumberStack.addBackgroundView(withBackgroundColor: Theme.backgroundColor)
        phoneNumberBackground.layer.cornerRadius = 10

        let continueButton = OWSFlatButton.button(title: OWSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_CONFIRM_BUTTON",
                                                                           comment: "Label for the 'confirm change phone number' button in the 'change phone number' views."),
                                                  font: UIFont.dynamicTypeBody.semibold(),
                                                  titleColor: .ows_white,
                                                  backgroundColor: .ows_accentBlue,
                                                  target: self,
                                                  selector: #selector(didTapContinue))
        continueButton.autoSetHeightUsingFont()
        continueButton.cornerRadius = 8
        continueButton.setEnabled(state.rateLimitedError?.canSubmit(e164: self.state.newE164, dateProvider: Date.provider) ?? true)

        let editButton = OWSFlatButton.button(title: OWSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_BACK_TO_EDIT_BUTTON",
                                                                         comment: "Label for the 'edit phone number' button in the 'change phone number' views."),
                                                font: UIFont.dynamicTypeBody,
                                                titleColor: .ows_accentBlue,
                                                backgroundColor: .clear,
                                                target: self,
                                                selector: #selector(didTapEdit))
        editButton.autoSetHeightUsingFont()
        editButton.cornerRadius = 8

        rootView.removeAllSubviews()
        rootView.addArrangedSubviews([
            UIView.spacer(withHeight: 24),
            descriptionLabel,
            UIView.spacer(withHeight: 20),
            phoneNumberStack
        ])

        let now = Date()
        if let rateLimitedError = state.rateLimitedError, !rateLimitedError.canSubmit(e164: self.state.newE164, dateProvider: { now }) {
            let warningLabel = UILabel()
            warningLabel.textColor = .ows_accentRed
            warningLabel.numberOfLines = 0
            warningLabel.font = UIFont.dynamicTypeSubheadlineClamped
            warningLabel.accessibilityIdentifier = "registration.phonenumber.validationWarningLabel"
            warningLabel.text = rateLimitedError.warningLabelText(dateProvider: { now })

            rootView.addArrangedSubview(UIView.spacer(withHeight: 12))
            rootView.addArrangedSubview(warningLabel)
        }

        rootView.addArrangedSubviews([
            UIView.vStretchingSpacer(),
            continueButton,
            UIView.spacer(withHeight: 20),
            editButton
        ])
    }

    @objc
    private func didTapEdit(_ sender: UIButton) {
        AssertIsOnMainThread()

        presenter?.returnToPhoneNumberEntry()
    }

    @objc
    private func didTapContinue(_ sender: UIButton) {
        AssertIsOnMainThread()

        guard state.rateLimitedError?.canSubmit(e164: self.state.newE164, dateProvider: Date.provider) != false else {
            return
        }

        presenter?.confirmChangeNumber(newE164: state.newE164)
    }
}
