//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalServiceKit
import UIKit
import SignalMessaging
import SignalUI

class ChangePhoneNumberConfirmViewController: OWSViewController {

    private let changePhoneNumberController: ChangePhoneNumberController
    private let oldPhoneNumber: PhoneNumber
    private let newPhoneNumber: PhoneNumber

    private let rootView = UIStackView()

    public init(changePhoneNumberController: ChangePhoneNumberController,
                oldPhoneNumber: PhoneNumber,
                newPhoneNumber: PhoneNumber) {
        self.changePhoneNumberController = changePhoneNumberController
        self.oldPhoneNumber = oldPhoneNumber
        self.newPhoneNumber = newPhoneNumber
        super.init()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_VIEW_TITLE",
                                  comment: "Title for the 'change phone number' views in settings.")

        createContents()
    }

    private func createContents() {
        rootView.axis = .vertical
        rootView.alignment = .fill
        rootView.isLayoutMarginsRelativeArrangement = true
        rootView.layoutMargins = UIEdgeInsets(hMargin: 20, vMargin: 0)
        view.addSubview(rootView)
        rootView.autoPinEdge(toSuperviewSafeArea: .leading)
        rootView.autoPinEdge(toSuperviewSafeArea: .trailing)
        rootView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        self.autoPinView(toBottomOfViewControllerOrKeyboard: rootView, avoidNotch: true)

        updateContents()
    }

    public override func applyTheme() {
        super.applyTheme()

        updateContents()
    }

    private func updateContents() {
        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)

        let descriptionFormat = NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_CONFIRM_DESCRIPTION_FORMAT",
                                                  comment: "Format for the description text in the 'change phone number splash' view. Embeds: {{ %1$@ the old phone number, %2$@ the new phone number }}.")
        let oldPhoneNumberFormatted = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: oldPhoneNumber.toE164())
        let newPhoneNumberFormatted = PhoneNumber.bestEffortLocalizedPhoneNumber(withE164: newPhoneNumber.toE164())
        let descriptionText = String(format: descriptionFormat,
                                     oldPhoneNumberFormatted,
                                     newPhoneNumberFormatted)
        let descriptionAttributedText = NSMutableAttributedString(string: descriptionText)
        descriptionAttributedText.setAttributes([
            .foregroundColor: Theme.primaryTextColor
        ],
                                                forSubstring: oldPhoneNumberFormatted)
        descriptionAttributedText.setAttributes([
            .foregroundColor: Theme.primaryTextColor
        ],
                                                forSubstring: newPhoneNumberFormatted)

        let descriptionLabel = UILabel()
        descriptionLabel.font = .ows_dynamicTypeBody
        descriptionLabel.textColor = Theme.secondaryTextAndIconColor
        descriptionLabel.attributedText = descriptionAttributedText
        descriptionLabel.textAlignment = .center
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping

        let phoneNumberLabel = UILabel()
        phoneNumberLabel.font = .ows_dynamicTypeTitle2.ows_semibold
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

        let continueButton = OWSFlatButton.button(title: NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_CONFIRM_BUTTON",
                                                                           comment: "Label for the 'confirm change phone number' button in the 'change phone number' views."),
                                                  font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                                  titleColor: .ows_white,
                                                  backgroundColor: .ows_accentBlue,
                                                  target: self,
                                                  selector: #selector(didTapContinue))
        continueButton.autoSetHeightUsingFont()
        continueButton.cornerRadius = 8

        let editButton = OWSFlatButton.button(title: NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_BACK_TO_EDIT_BUTTON",
                                                                         comment: "Label for the 'edit phone number' button in the 'change phone number' views."),
                                                font: UIFont.ows_dynamicTypeBody,
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
            phoneNumberStack,
            UIView.vStretchingSpacer(),
            continueButton,
            UIView.spacer(withHeight: 20),
            editButton
        ])
    }

    @objc
    private func didTapEdit(_ sender: UIButton) {
        AssertIsOnMainThread()

        navigationController?.popViewController(animated: true)
    }

    @objc
    private func didTapContinue(_ sender: UIButton) {
        AssertIsOnMainThread()

        tryToChangePhoneNumber()
    }

    private func tryToChangePhoneNumber() {
        AssertIsOnMainThread()

        showProgressUI()

        changePhoneNumberController.requestVerification(fromViewController: self,
                                                        isSMS: true) { [weak self] _, _ in
            self?.hideProgressUI()
        }
    }

    private var progressUI: UIView?

    private func hideProgressUI() {
        AssertIsOnMainThread()

        progressUI?.removeFromSuperview()
        progressUI = nil
    }

    private func showProgressUI() {
        AssertIsOnMainThread()

        hideProgressUI()

        let progressUI = UIView()
        progressUI.backgroundColor = Theme.backgroundColor
        view.addSubview(progressUI)
        progressUI.autoPinEdgesToSuperviewEdges()

        let labelFormat = NSLocalizedString("SETTINGS_CHANGE_PHONE_NUMBER_PROGRESS_FORMAT",
                                            comment: "Format for the 'change phone number' progress view. Embeds: {{ the user's new phone number }}.")
        let labelText = String(format: labelFormat, newPhoneNumber.toE164())
        let progressView = AnimatedProgressView(loadingText: labelText)
        let progressStack = UIStackView(arrangedSubviews: [progressView])
        progressStack.axis = .vertical
        progressStack.alignment = .center
        progressUI.addSubview(progressStack)
        progressStack.autoVCenterInSuperview()
        progressStack.autoPinEdge(toSuperviewSafeArea: .leading)
        progressStack.autoPinEdge(toSuperviewSafeArea: .trailing)

        progressView.startAnimating {
//            overlayView.alpha = 1
        }
    }
}
