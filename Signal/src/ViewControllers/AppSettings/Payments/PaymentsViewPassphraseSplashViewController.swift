//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalUI
import SignalMessaging

public protocol PaymentsViewPassphraseDelegate: AnyObject {
    func viewPassphraseDidCancel(viewController: PaymentsViewPassphraseSplashViewController)
    func viewPassphraseDidComplete()
}

// MARK: -

@objc
public class PaymentsViewPassphraseSplashViewController: OWSViewController {

    public enum Style: Int, CaseIterable {
        /// From settings menu when user has not completed recovery phrase
        case view
        /// From settings menu after user has completed recovery phrase
        case reviewed
        /// When balance becomes non-zero for the first time
        case fromBalance
        /// From the help card on payments settings
        case fromHelpCard
        /// When dismissing the help card on payments settings
        case fromHelpCardDismiss
    }

    public let style: Style

    private let passphrase: PaymentsPassphrase

    private weak var viewPassphraseDelegate: PaymentsViewPassphraseDelegate?

    private let rootView = UIStackView()

    public required init(passphrase: PaymentsPassphrase,
                         style: Style,
                         viewPassphraseDelegate: PaymentsViewPassphraseDelegate) {
        self.passphrase = passphrase
        self.style = style
        self.viewPassphraseDelegate = viewPassphraseDelegate

        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = OWSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_TITLE",
                                  comment: "Title for the 'view payments passphrase' view of the app settings.")

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

        updateContents()
    }

    private func updateNavbar() {
        let closeButton = UIImage(named: "x-24")?.withRenderingMode(.alwaysTemplate)
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: closeButton,
            landscapeImagePhone: nil,
            style: .plain,
            target: self,
            action: #selector(didTapDismiss),
            accessibilityIdentifier: "dismiss"
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

        let heroImage = UIImageView(image: UIImage(named: "recovery-phrase"))

        let titleLabel = UILabel()
        titleLabel.text = style.title
        titleLabel.font = UIFont.dynamicTypeTitle2Clamped.semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center

        let explanationLabel = PaymentsViewUtils.buildTextWithLearnMoreLinkTextView(
            text: self.style.explanationText,
            font: .dynamicTypeBody2Clamped,
            learnMoreUrl: self.style.explanationUrl)
        explanationLabel.textAlignment = .center

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

        let nextButton = OWSFlatButton.insetButton(
            title: CommonStrings.nextButton,
            font: UIFont.dynamicTypeBody.semibold(),
            titleColor: .white,
            backgroundColor: .ows_accentBlue,
            target: self,
            selector: #selector(didTapNextButton)
        )

        nextButton.autoSetHeightUsingFont()
        nextButton.cornerRadius = 14

        let cancelButton = OWSFlatButton.insetButton(
            title: CommonStrings.notNowButton,
            font: UIFont.dynamicTypeBody.semibold(),
            titleColor: .ows_accentBlue,
            backgroundColor: .clear,
            target: self,
            selector: #selector(didTapDismiss)
        )

        cancelButton.autoSetHeightUsingFont()

        let spacerFactory = SpacerFactory()

        rootView.removeAllSubviews()
        rootView.addArrangedSubviews([
            spacerFactory.buildVSpacer(),
            topStack,
            spacerFactory.buildVSpacer(),
            nextButton,
            cancelButton,
            UIView.spacer(withHeight: 8)
        ])

        spacerFactory.finalizeSpacers()
    }

    func showDismissConfirmation() {
        let actionSheet = ActionSheetController(title: OWSLocalizedString("SETTINGS_PAYMENTS_PASSPHRASE_DISCARD_CONFIRMATION_TITLE",
                                                                         comment: "Title of confirmation alert when discarding recovery phrase."),
                                                message: OWSLocalizedString("SETTINGS_PAYMENTS_PASSPHRASE_DISCARD_CONFIRMATION_MESSAGE",
                                                                           comment: "Message of confirmation alert when discarding recovery phrase."))
        actionSheet.addAction(ActionSheetAction(
            title: OWSLocalizedString("SETTINGS_PAYMENTS_PASSPHRASE_DISCARD_CONFIRMATION_BUTTON",
                                     comment: "Button when discarding recovery phrase."),
            style: .destructive,
            handler: { [weak self] _ in
                self?.notifyCancelled()
            }
        ))
        actionSheet.addAction(ActionSheetAction(
            title: CommonStrings.cancelButton,
            style: .cancel,
            handler: nil
        ))
        self.presentActionSheet(actionSheet)
    }

    private func notifyCancelled() {
        viewPassphraseDelegate?.viewPassphraseDidCancel(viewController: self)
    }

    // MARK: - Events

    @objc
    func didTapDismiss() {
        if style.shouldConfirmCancel {
            showDismissConfirmation()
        } else {
            notifyCancelled()
        }
    }

    @objc
    func didTapNextButton() {
        AssertIsOnMainThread()

        guard let viewPassphraseDelegate = viewPassphraseDelegate else {
            dismiss(animated: false, completion: nil)
            return
        }

        if OWSPaymentsLock.shared.isPaymentsLockEnabled() {
            OWSPaymentsLock.shared.tryToUnlock { [weak self] outcome in
                guard let self = self else { return }
                guard outcome == OWSPaymentsLock.LocalAuthOutcome.success else {
                    PaymentActionSheets.showBiometryAuthFailedActionSheet { _ in
                        self.dismiss(animated: false, completion: nil)
                    }
                    return
                }

                let view = PaymentsViewPassphraseGridViewController(
                    passphrase: self.passphrase,
                    viewPassphraseDelegate: viewPassphraseDelegate)
                self.navigationController?.pushViewController(view, animated: true)
            }
        } else {
            let view = PaymentsViewPassphraseGridViewController(
                passphrase: passphrase,
                viewPassphraseDelegate: viewPassphraseDelegate)
            navigationController?.pushViewController(view, animated: true)
        }
    }
}

extension PaymentsViewPassphraseSplashViewController.Style {

    var title: String {
        switch self {
        case .reviewed:
            return OWSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_START_TITLE",
                                     comment: "Title for the first step of the 'view payments passphrase' views.")
        case .fromBalance, .fromHelpCard, .fromHelpCardDismiss, .view:
            return OWSLocalizedString("SETTINGS_PAYMENTS_SAVE_PASSPHRASE_START_TITLE",
                                     comment: "Title for the first step of the 'save payments passphrase' views.")
        }
    }

    var explanationText: String {
        switch self {
        case .view, .reviewed:
            return OWSLocalizedString("SETTINGS_PAYMENTS_PASSPHRASE_EXPLANATION",
                                     comment: "Explanation of the 'payments passphrase' in the 'view payments passphrase' settings.")
        case .fromHelpCard, .fromHelpCardDismiss:
            return OWSLocalizedString("SETTINGS_PAYMENTS_PASSPHRASE_EXPLANATION_FROM_HELP_CARD",
                                     comment: "Explanation of the 'payments passphrase' when from the help card.")
        case .fromBalance:
            return OWSLocalizedString("SETTINGS_PAYMENTS_PASSPHRASE_EXPLANATION_FROM_BALANCE",
                                     comment: "Explanation of the 'payments passphrase' when there is a balance.")
        }
    }

    var explanationUrl: String {
        return "https://support.signal.org/hc/en-us/articles/360057625692#payments_wallet_view_passphrase"
    }

    var shouldConfirmCancel: Bool {
        switch self {
        case .reviewed:
            return false
        case .fromBalance, .fromHelpCard, .fromHelpCardDismiss, .view:
            return true
        }
    }

    var shouldShowHelpCardAfterCancel: Bool {
        switch self {
        case .reviewed, .fromHelpCardDismiss:
            return false
        case .fromBalance, .fromHelpCard, .view:
            return true
        }
    }

}
