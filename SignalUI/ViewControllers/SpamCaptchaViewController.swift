//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalMessaging
import UIKit

public class SpamCaptchaViewController: UIViewController, CaptchaViewDelegate {

    private var captchaView: CaptchaView?

    var completionHandler: ((String?) -> Void)?

    private init() {
        super.init(nibName: nil, bundle: nil)
    }

    override public func loadView() {
        let captchaView = CaptchaView(context: .challenge)
        captchaView.delegate = self

        let view = UIView()
        view.addSubview(captchaView)
        captchaView.autoPinEdgesToSuperviewEdges()

        self.captchaView = captchaView
        self.view = view
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        captchaView?.loadCaptcha()

        isModalInPresentation = true
        navigationItem.title = OWSLocalizedString("SPAM_CAPTCHA_VIEW_CONTROLLER", comment: "Title for the captcha view controller")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .stop,
            target: self,
            action: #selector(didTapCancel)
        )
    }

    @objc
    private func didTapCancel() {
        completionHandler?(nil)
        completionHandler = nil
    }

    public func captchaView(_: CaptchaView, didCompleteCaptchaWithToken token: String) {
        completionHandler?(token)
        completionHandler = nil
    }

    public func captchaViewDidFailToCompleteCaptcha(_: CaptchaView) {
        captchaView?.loadCaptcha()
    }

    public override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }
}

extension SpamCaptchaViewController {

    public static func presentActionSheet(from fromVC: UIViewController) {

        let titleLabel = UILabel()
        titleLabel.font = UIFont.dynamicTypeTitle2Clamped.semibold()
        titleLabel.textColor = Theme.primaryTextColor
        titleLabel.numberOfLines = 0
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.textAlignment = .center
        titleLabel.text = OWSLocalizedString("SPAM_CAPTCHA_SHEET_TITLE", comment: "Title for action sheet explaining captcha requirement.")

        let bodyLabel = UILabel()
        bodyLabel.font = .dynamicTypeBody2Clamped
        bodyLabel.textColor = Theme.primaryTextColor
        bodyLabel.numberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        bodyLabel.text = OWSLocalizedString("SPAM_CAPTCHA_SHEET_BODY", comment: "Body for action sheet explaining captcha requirement.")

        let continueButton = OWSFlatButton()
        continueButton.setTitle(
            title: CommonStrings.continueButton,
            font: UIFont.dynamicTypeBodyClamped.semibold(),
            titleColor: .white)
        continueButton.setBackgroundColors(upColor: Theme.accentBlueColor)
        continueButton.layer.cornerRadius = 8
        continueButton.layer.masksToBounds = true
        continueButton.contentEdgeInsets = UIEdgeInsets(hMargin: 4, vMargin: 14)

        let stackView = UIStackView(arrangedSubviews: [
            titleLabel,
            bodyLabel,
            UIView.spacer(withHeight: 72),
            continueButton
        ])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.distribution = .fill
        stackView.spacing = 16

        let sheet = SheetViewController()
        sheet.isHandleHidden = true
        sheet.contentView.addSubview(stackView)
        sheet.dismissHandler = { sheet in
            sheet.dismiss(animated: true)

            let confirmationSheet = ActionSheetController(
                title: OWSLocalizedString(
                    "SPAM_CAPTCHA_DISMISS_CONFIRMATION_TITLE",
                    comment: "Title for confirmation dialog confirming to ignore verification."),
                message: OWSLocalizedString(
                    "SPAM_CAPTCHA_DISMISS_CONFIRMATION_MESSAGE",
                    comment: "Message for confirmation dialog confirming to ignore verification.")
                )

            confirmationSheet.addAction(
                ActionSheetAction(
                    title: OWSLocalizedString("SPAM_CAPTCHA_SKIP_VERIFICATION_ACTION", comment: "Action to skip verification"),
                    style: .destructive
                ))
            confirmationSheet.addAction(
                ActionSheetAction(
                    title: CommonStrings.cancelButton,
                    style: .cancel,
                    handler: { _ in
                        presentActionSheet(from: fromVC)
                    }
                ))
            fromVC.present(confirmationSheet, animated: true, completion: nil)
        }

        continueButton.setPressedBlock {
            sheet.dismiss(animated: true)
            presentCaptchaVC(from: fromVC)
        }

        stackView.autoPinEdgesToSuperviewMargins(
            with: UIEdgeInsets(hMargin: 24, vMargin: 16))
        continueButton.autoPinWidthToSuperviewMargins()

        fromVC.present(sheet, animated: true, completion: nil)
    }

    static func presentCaptchaVC(from fromVC: UIViewController) {
        let vc = SpamCaptchaViewController()
        vc.completionHandler = { token in
            if let token = token {
                fromVC.presentToast(
                    text: OWSLocalizedString(
                        "SPAM_CAPTCHA_COMPLETED_TOAST",
                        comment: "Text for toast presented after spam verification has been completed"))
                spamChallengeResolver.handleIncomingCaptchaChallengeToken(token)
            }
            vc.dismiss(animated: true)
        }
        let navVC = OWSNavigationController(rootViewController: vc)
        fromVC.present(navVC, animated: true, completion: nil)
    }
}
