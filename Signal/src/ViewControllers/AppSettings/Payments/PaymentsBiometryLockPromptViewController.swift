//
// Copyright 2022 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public protocol PaymentsBiometryLockPromptDelegate: AnyObject {
    func didEnablePaymentsLock()
    func didNotEnablePaymentsLock()
}

// MARK: -

public class PaymentsBiometryLockPromptViewController: OWSViewController {

    private var hasBeenDoubleReminded: Bool = false

    private let validBiometryType: ValidBiometryType

    private weak var delegate: PaymentsBiometryLockPromptDelegate?

    private let rootView = UIStackView()

    public required init(biometryType: ValidBiometryType, delegate: PaymentsBiometryLockPromptDelegate?) {
        self.validBiometryType = biometryType
        self.delegate = delegate

        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PAYMENTS_ENABLE_PAYMENTS_LOCK_PROMPT",
                                  comment: "Title for the 'enable payments lock' view of the payments activation flow.")

        OWSTableViewController2.removeBackButtonText(viewController: self)

        rootView.axis = .vertical
        rootView.alignment = .fill
        view.addSubview(rootView)
        rootView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        rootView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        rootView.autoPinWidthToSuperviewMargins()

        updateContents()
        updateNavbar()
    }

    public override func themeDidChange() {
        super.themeDidChange()

        self.applyTheme()
    }

    public func applyTheme() {
        updateContents()
    }

    private func updateNavbar() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "x-24")?.withRenderingMode(.alwaysTemplate),
            style: .plain,
            target: self,
            action: #selector(didTapClose),
            accessibilityIdentifier: "close"
        )
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        updateContents()
        updateNavbar()
    }

    @objc
    private func updateContents() {
        AssertIsOnMainThread()

        view.backgroundColor = OWSTableViewController2.tableBackgroundColor(isUsingPresentedStyle: true)

        let heroImage = UIImageView(image: UIImage(named: "payments-lock"))

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PAYMENTS_LOCK_PROMPT_TITLE",
                                            comment: "Title for the content section of the  'payments lock prompt' view shown after payemts activation.")
        titleLabel.font = UIFont.ows_dynamicTypeTitle2Clamped.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center

        let explanationLabel = UILabel()
        explanationLabel.text = localizedExplanationLabelText()
        explanationLabel.font = .ows_dynamicTypeBody2Clamped
        explanationLabel.textColor = Theme.primaryTextColor
        explanationLabel.textAlignment = .center
        explanationLabel.numberOfLines = 0

        let topStack = UIStackView(arrangedSubviews: [
            heroImage,
            UIView.spacer(withHeight: 20),
            titleLabel,
            UIView.spacer(withHeight: 10),
            explanationLabel
        ])
        topStack.axis = .vertical
        topStack.alignment = .center
        topStack.isLayoutMarginsRelativeArrangement = true
        topStack.layoutMargins = UIEdgeInsets(hMargin: 20, vMargin: 0)

        let enableButton = OWSFlatButton.insetButton(title: enableButtonTitle(),
                                               font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                               titleColor: .white,
                                               backgroundColor: .ows_accentBlue,
                                               target: self,
                                               selector: #selector(didTapEnableButton))
        enableButton.autoSetHeightUsingFont()

        let notNowButton = OWSFlatButton.insetButton(title: CommonStrings.notNowButton,
                                               font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                               titleColor: .ows_accentBlue,
                                               backgroundColor: .clear,
                                               target: self,
                                               selector: #selector(didTapNotNowButton))
        notNowButton.autoSetHeightUsingFont()

        let spacerFactory = SpacerFactory()

        rootView.removeAllSubviews()
        rootView.addArrangedSubviews([
            spacerFactory.buildVSpacer(),
            topStack,
            spacerFactory.buildVSpacer(),
            enableButton,
            UIView.spacer(withHeight: 16),
            notNowButton,
            UIView.spacer(withHeight: 8)
        ])

        spacerFactory.finalizeSpacers()
    }

    // MARK: - Events

    @objc
    func didTapClose() {
        guard hasBeenDoubleReminded == false else {
            dismiss(animated: true, completion: nil)
            return
        }

        showDoubleReminder()
    }

    @objc
    func didTapEnableButton() {
        databaseStorage.write { transaction in
            OWSPaymentsLock.shared.setIsPaymentsLockEnabled(true, transaction: transaction)
        }
        dismiss(animated: true, completion: nil)
    }

    @objc
    func didTapNotNowButton() {
        AssertIsOnMainThread()

        guard hasBeenDoubleReminded == false else {
            dismiss(animated: true, completion: nil)
            return
        }

        showDoubleReminder()
    }

    func showDoubleReminder() {
        AssertIsOnMainThread()

        self.hasBeenDoubleReminded = true

        let actionSheet = ActionSheetController(
            title: doubleReminderActionSheetTitle(),
            message: NSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_DOUBLE_REMINDER_MESSAGE",
                comment: "Description for the 'double reminder' action sheet in the 'payments lock prompt' view in the payment settings."))

        actionSheet.addAction(
            ActionSheetAction(
                title: CommonStrings.skipButton,
                accessibilityIdentifier: "OWSActionSheets.skip",
                style: .destructive
            ) { [weak self] _ in
                Logger.debug("User is explicitly skipping the double reminder, so dismiss the 'payments lock prompt' view entirely.")
                self?.dismiss(animated: true, completion: nil)
            }
        )

        actionSheet.addAction(
            ActionSheetAction(
                title: CommonStrings.cancelButton,
                accessibilityIdentifier: "OWSActionSheets.cancel",
                style: .cancel
            ) { _ in
                Logger.debug("User cancelled the payments lock dismissal, dismiss the action sheet so user can reconsider payments lock decision")
            }
        )

        presentActionSheet(actionSheet)
    }

    private func localizedExplanationLabelText() -> String {
        switch validBiometryType {
        case .faceId:
            return NSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_EXPLANATION_FACEID",
                comment: "Explanation of 'payments lock' with Face ID in the 'payments lock prompt' view shown after payments activation.")
        case .touchId:
            return NSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_EXPLANATION_TOUCHID",
                comment: "Explanation of 'payments lock' with Touch ID in the 'payments lock prompt' view shown after payments activation.")
        case .passcode:
            return NSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_EXPLANATION_PASSCODE",
                comment: "Explanation of 'payments lock' with passcode in the 'payments lock prompt' view shown after payments activation.")
        }
    }

    private func enableButtonTitle() -> String {
        switch validBiometryType {
        case .faceId:
            return NSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_ENABLE_BUTTON_FACEID",
                comment: "Enable Button title in Payments Lock Prompt view for Face ID.")
        case .touchId:
            return NSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_ENABLE_BUTTON_TOUCHID",
                comment: "Enable Button title in Payments Lock Prompt view for Touch ID.")
        case .passcode:
            return NSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_ENABLE_BUTTON_PASSCODE",
                comment: "Enable Button title in Payments Lock Prompt view for Passcode.")
        }
    }

    private func doubleReminderActionSheetTitle() -> String {
        switch validBiometryType {
        case .faceId:
            return NSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_DOUBLE_REMINDER_TITLE_FACEID",
                comment: "Double reminder action sheet title in Payments Lock Prompt view for Face ID.")
        case .touchId:
            return NSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_DOUBLE_REMINDER_TITLE_TOUCHID",
                comment: "Double reminder action sheet title in Payments Lock Prompt view for Touch ID.")
        case .passcode:
            return NSLocalizedString(
                "SETTINGS_PAYMENTS_PAYMENTS_LOCK_PROMPT_DOUBLE_REMINDER_TITLE_PASSCODE",
                comment: "Double reminder action sheet title in Payments Lock Prompt view for Passcode.")
        }
    }
}
