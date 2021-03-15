//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import Foundation

public protocol PaymentsRestoreWalletDelegate: class {
    func restoreWalletDidComplete()
}

// MARK: -

@objc
public class PaymentsRestoreWalletSplashViewController: OWSViewController {

    private weak var restoreWalletDelegate: PaymentsRestoreWalletDelegate?

    public required init(restoreWalletDelegate: PaymentsRestoreWalletDelegate) {
        self.restoreWalletDelegate = restoreWalletDelegate

        super.init()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_TITLE",
                                  comment: "Title for the 'restore payments wallet' view of the app settings.")

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done,
                                                           target: self,
                                                           action: #selector(didTapDismiss),
                                                           accessibilityIdentifier: "dismiss")
        createContents()
    }

    private func createContents() {

        view.backgroundColor = Theme.tableViewBackgroundColor

        let heroImage = UIImageView(image: UIImage(named: "recovery-phrase"))

        let titleLabel = UILabel()
        titleLabel.text = NSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_SPLASH_TITLE",
                                            comment: "Title for the first step of the 'restore payments wallet' views.")
        titleLabel.font = UIFont.ows_dynamicTypeTitle2Clamped.ows_semibold
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.textAlignment = .center

        let explanationAttributed = NSMutableAttributedString()
        explanationAttributed.append(NSLocalizedString("SETTINGS_PAYMENTS_RESTORE_WALLET_SPLASH_EXPLANATION",
                                                       comment: "Explanation of the 'restore payments wallet' process payments settings."),
                                     attributes: [
                                        .font: UIFont.ows_dynamicTypeBody2Clamped,
                                        .foregroundColor: Theme.secondaryTextAndIconColor
                                     ])
        explanationAttributed.append(" ",
                                     attributes: [
                                        .font: UIFont.ows_dynamicTypeBody2Clamped
                                     ])
        explanationAttributed.append(CommonStrings.learnMore,
                                     attributes: [
                                        .font: UIFont.ows_dynamicTypeBody2Clamped.ows_semibold,
                                        .foregroundColor: Theme.primaryTextColor
                                     ])

        let explanationLabel = UILabel()
        explanationLabel.attributedText = explanationAttributed
        explanationLabel.textAlignment = .center
        explanationLabel.numberOfLines = 0
        explanationLabel.lineBreakMode = .byWordWrapping
        explanationLabel.isUserInteractionEnabled = true
        explanationLabel.addGestureRecognizer(UITapGestureRecognizer(target: self,
                                                                     action: #selector(didTapExplanation)))

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

        let rootView = UIStackView(arrangedSubviews: [
            spacerFactory.buildVSpacer(),
            topStack,
            spacerFactory.buildVSpacer(),
            startButton,
            UIView.spacer(withHeight: 8)
        ])
        rootView.axis = .vertical
        rootView.alignment = .fill
        view.addSubview(rootView)
        rootView.autoPin(toTopLayoutGuideOf: self, withInset: 0)
        rootView.autoPin(toBottomLayoutGuideOf: self, withInset: 0)
        rootView.autoPinWidthToSuperviewMargins()

        spacerFactory.finalizeSpacers()
    }

    // MARK: - Events

    @objc
    func didTapDismiss() {
        dismiss(animated: true, completion: nil)
    }

    @objc
    func didTapStartButton() {
        guard let restoreWalletDelegate = restoreWalletDelegate else {
            owsFailDebug("Missing restoreWalletDelegate.")
            dismiss(animated: true, completion: nil)
            return
        }
        // Start by entering the first word of the partial passphrase.
        let view = PaymentsRestoreWalletWordViewController(restoreWalletDelegate: restoreWalletDelegate,
                                                           partialPassphrase: PartialPaymentsPassphrase.empty,
                                                           wordIndex: 0)
        navigationController?.pushViewController(view, animated: true)
    }

    @objc
    private func didTapExplanation() {
        // TODO: Need a support article link.
    }
}
