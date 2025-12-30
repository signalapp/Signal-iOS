//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalServiceKit
import SignalUI

// MARK: - RegistrationCaptchaPresenter

protocol RegistrationCaptchaPresenter: AnyObject {
    func submitCaptcha(_ token: String)
}

// MARK: - RegistrationCaptchaViewController

class RegistrationCaptchaViewController: OWSViewController {
    private weak var presenter: RegistrationCaptchaPresenter?

    init(presenter: RegistrationCaptchaPresenter) {
        self.presenter = presenter

        super.init()

        navigationItem.hidesBackButton = true
    }

    @available(*, unavailable)
    override init() {
        owsFail("This should not be called")
    }

    // MARK: - Rendering

    private lazy var captchaView: CaptchaView = {
        let result = CaptchaView(context: .registration)
        result.delegate = self
        return result
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "REGISTRATION_CAPTCHA_TITLE",
            comment: "During registration, users may be shown a CAPTCHA to verify that they're human. This text is shown above the CAPTCHA.",
        ))
        titleLabel.setContentHuggingHigh()
        titleLabel.accessibilityIdentifier = "registration.captcha.titleLabel"

        addStaticContentStackView(arrangedSubviews: [titleLabel, captchaView])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captchaView.loadCaptcha()
    }
}

// MARK: - CaptchaViewDelegate

extension RegistrationCaptchaViewController: CaptchaViewDelegate {
    func captchaView(_: CaptchaView, didCompleteCaptchaWithToken token: String) {
        presenter?.submitCaptcha(token)
    }

    func captchaViewDidFailToCompleteCaptcha(_ captchaView: CaptchaView) {
        captchaView.loadCaptcha()
    }
}

// MARK: -

#if DEBUG

private class PreviewRegistrationCaptchaPresenter: RegistrationCaptchaPresenter {
    func submitCaptcha(_ token: String) {
        print("submitCaptcha")
    }
}

@available(iOS 17, *)
#Preview {
    let presenter = PreviewRegistrationCaptchaPresenter()
    return UINavigationController(
        rootViewController: RegistrationCaptchaViewController(
            presenter: presenter,
        ),
    )
}

#endif
