//
// Copyright 2021 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import UIKit

@objc
protocol Deprecated_RegistrationCaptchaViewController: AnyObject {

    var viewModel: Deprecated_RegistrationCaptchaViewModel { get }
    var primaryView: UIView { get }

    func requestCaptchaVerification(captchaToken: String)
}

// MARK: -

@objc
class Deprecated_RegistrationCaptchaViewModel: NSObject {
    weak var viewController: Deprecated_RegistrationCaptchaViewController?

    let captchaView = CaptchaView(context: .registration)

    // MARK: - Methods

    func createViews(vc: Deprecated_RegistrationBaseViewController) {
        AssertIsOnMainThread()

        let primaryView = vc.primaryView
        primaryView.backgroundColor = Theme.backgroundColor

        let titleLabel = vc.createTitleLabel(text: NSLocalizedString("ONBOARDING_CAPTCHA_TITLE",
                                                                     comment: "Title of the 'onboarding Captcha' view."))
        titleLabel.accessibilityIdentifier = "captcha." + "titleLabel"

        let titleRow = UIStackView(arrangedSubviews: [
            titleLabel
            ])
        titleRow.axis = .vertical
        titleRow.alignment = .fill
        titleRow.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        titleRow.isLayoutMarginsRelativeArrangement = true

        captchaView.delegate = self

        let stackView = UIStackView(arrangedSubviews: [
            titleRow,
            captchaView
            ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        primaryView.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewSafeArea()
    }

    // MARK: -

    private func requestCaptchaVerification(captchaToken: String) {
        Logger.info("")

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return
        }
        viewController.requestCaptchaVerification(captchaToken: captchaToken)
    }

    func addProgressView() -> AnimatedProgressView? {
        AssertIsOnMainThread()

        guard let viewController = self.viewController else {
            owsFailDebug("Missing viewController.")
            return nil
        }
        let primaryView = viewController.primaryView

        let progressView = AnimatedProgressView()
        primaryView.addSubview(progressView)
        progressView.autoCenterInSuperview()
        progressView.startAnimating()
        return progressView
    }

    func removeProgressView(_ progressView: AnimatedProgressView?) {
        AssertIsOnMainThread()

        guard let progressView = progressView else {
            owsFailDebug("Missing progressView.")
            return
        }

        UIView.animate(withDuration: 0.15) {
            progressView.alpha = 0
        } completion: { _ in
            progressView.removeFromSuperview()
        }
    }
}

// MARK: -

extension Deprecated_RegistrationCaptchaViewModel: CaptchaViewDelegate {

    public func captchaView(_: CaptchaView, didCompleteCaptchaWithToken token: String) {
        requestCaptchaVerification(captchaToken: token)
    }

    public func captchaViewDidFailToCompleteCaptcha(_ captchaView: CaptchaView) {
        captchaView.loadCaptcha()
    }
}
