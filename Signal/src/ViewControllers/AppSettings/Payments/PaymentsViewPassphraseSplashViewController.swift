//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import SignalMessaging

public protocol PaymentsViewPassphraseDelegate: AnyObject {
    func viewPassphraseDidComplete()
}

// MARK: -

@objc
public class PaymentsViewPassphraseSplashViewController: OWSViewController {

    private let passphrase: PaymentsPassphrase

    private let shouldShowConfirm: Bool

    private weak var viewPassphraseDelegate: PaymentsViewPassphraseDelegate?

    private let rootView = UIStackView()

    public required init(passphrase: PaymentsPassphrase,
                         shouldShowConfirm: Bool,
                         viewPassphraseDelegate: PaymentsViewPassphraseDelegate) {
        self.passphrase = passphrase
        self.shouldShowConfirm = shouldShowConfirm
        self.viewPassphraseDelegate = viewPassphraseDelegate

        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_TITLE",
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
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                           target: self,
                                                           action: #selector(didTapDismiss),
                                                           accessibilityIdentifier: "dismiss")
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
        titleLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_VIEW_PASSPHRASE_START_TITLE",
                                            comment: "Title for the first step of the 'view payments passphrase' views.")
        titleLabel.font = UIFont.ows_dynamicTypeTitle2Clamped.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center

        let explanationLabel = PaymentsViewUtils.buildTextWithLearnMoreLinkTextView(
            text: NSLocalizedString("SETTINGS_PAYMENTS_PASSPHRASE_EXPLANATION",
                                    comment: "Explanation of the 'payments passphrase' in the 'view payments passphrase' settings."),
            font: .ows_dynamicTypeBody2Clamped,
            learnMoreUrl: "https://support.signal.org/hc/en-us/articles/360057625692#payments_wallet_view_passphrase")
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

        let startButton = OWSFlatButton.button(title: CommonStrings.startButton,
                                               font: UIFont.ows_dynamicTypeBody.ows_semibold,
                                               titleColor: .white,
                                               backgroundColor: .ows_accentBlue,
                                               target: self,
                                               selector: #selector(didTapStartButton))
        startButton.autoSetHeightUsingFont()

        let spacerFactory = SpacerFactory()

        rootView.removeAllSubviews()
        rootView.addArrangedSubviews([
            spacerFactory.buildVSpacer(),
            topStack,
            spacerFactory.buildVSpacer(),
            startButton,
            UIView.spacer(withHeight: 8)
        ])

        spacerFactory.finalizeSpacers()
    }

    // MARK: - Events

    @objc
    func didTapDismiss() {
        dismiss(animated: true, completion: nil)
    }

    @objc
    func didTapStartButton() {
        didTapNextButton()
    }

    @objc
    func didTapNextButton() {
        AssertIsOnMainThread()

        guard let viewPassphraseDelegate = viewPassphraseDelegate else {
            dismiss(animated: false, completion: nil)
            return
        }

        let view = PaymentsViewPassphraseGridViewController(passphrase: passphrase,
                                                            viewPassphraseDelegate: viewPassphraseDelegate)
        navigationController?.pushViewController(view, animated: true)
    }
}
