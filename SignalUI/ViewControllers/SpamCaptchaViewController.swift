//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import UIKit

public class SpamCaptchaViewController: UIViewController, CaptchaViewDelegate {

    private lazy var captchaView: CaptchaView = {
        let view = CaptchaView(context: .challenge)
        view.delegate = self
        return view
    }()

    var completionHandler: ((String?) -> Void)?

    fileprivate init() {
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        view.addSubview(captchaView)
        captchaView.autoPinEdgesToSuperviewEdges()
        captchaView.loadCaptcha()

        isModalInPresentation = true
        navigationItem.title = OWSLocalizedString("SPAM_CAPTCHA_VIEW_CONTROLLER", comment: "Title for the captcha view controller")
        navigationItem.leftBarButtonItem = .systemItem(.stop) { [weak self] in
            self?.completionHandler?(nil)
            self?.completionHandler = nil
        }
    }

    override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.isIPad ? .all : .portrait
    }

    // MARK: - CaptchaViewDelegate

    public func captchaView(_: CaptchaView, didCompleteCaptchaWithToken token: String) {
        completionHandler?(token)
        completionHandler = nil
    }

    public func captchaViewDidFailToCompleteCaptcha(_: CaptchaView) {
        captchaView.loadCaptcha()
    }

    // MARK: - Presentation

    public static func presentActionSheet(from fromVC: UIViewController) {
        let sheet = ActionSheetController(
            title: OWSLocalizedString(
                "SPAM_CAPTCHA_SHEET_TITLE",
                comment: "Title for action sheet explaining captcha requirement.",
            ),
            message: OWSLocalizedString(
                "SPAM_CAPTCHA_SHEET_BODY",
                comment: "Body for action sheet explaining captcha requirement.",
            ),
        )
        sheet.addAction(
            ActionSheetAction(
                title: CommonStrings.continueButton,
                handler: { _ in
                    presentCaptchaVC(from: fromVC)
                },
            ),
        )
        sheet.addAction(
            ActionSheetAction(
                title: CommonStrings.notNowButton,
                style: .cancel,
                handler: { _ in
                    let confirmationSheet = ActionSheetController(
                        title: OWSLocalizedString(
                            "SPAM_CAPTCHA_DISMISS_CONFIRMATION_TITLE",
                            comment: "Title for confirmation dialog confirming to ignore verification.",
                        ),
                        message: OWSLocalizedString(
                            "SPAM_CAPTCHA_DISMISS_CONFIRMATION_MESSAGE",
                            comment: "Message for confirmation dialog confirming to ignore verification.",
                        ),
                    )

                    confirmationSheet.addAction(
                        ActionSheetAction(
                            title: OWSLocalizedString("SPAM_CAPTCHA_SKIP_VERIFICATION_ACTION", comment: "Action to skip verification"),
                            style: .destructive,
                        ),
                    )
                    confirmationSheet.addAction(
                        ActionSheetAction(
                            title: CommonStrings.cancelButton,
                            style: .cancel,
                            handler: { _ in
                                presentActionSheet(from: fromVC)
                            },
                        ),
                    )
                    fromVC.present(confirmationSheet, animated: true, completion: nil)
                },
            ),
        )

        fromVC.present(sheet, animated: true, completion: nil)
    }

    static func presentCaptchaVC(from fromVC: UIViewController) {
        let vc = SpamCaptchaViewController()
        vc.completionHandler = { token in
            if let token {
                fromVC.presentToast(
                    text: OWSLocalizedString(
                        "SPAM_CAPTCHA_COMPLETED_TOAST",
                        comment: "Text for toast presented after spam verification has been completed",
                    ),
                )
                SSKEnvironment.shared.spamChallengeResolverRef.handleIncomingCaptchaChallengeToken(token)
            }
            vc.dismiss(animated: true)
        }
        let navVC = OWSNavigationController(rootViewController: vc)
        fromVC.present(navVC, animated: true, completion: nil)
    }
}

#if DEBUG

@available(iOS 17, *)
#Preview {
    SpamCaptchaViewController()
}

#endif
