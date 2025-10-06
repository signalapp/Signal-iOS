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

    public init(presenter: RegistrationCaptchaPresenter) {
        self.presenter = presenter

        super.init()

        navigationItem.hidesBackButton = true
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    // MARK: - Rendering

    private lazy var captchaView: CaptchaView = {
        let result = CaptchaView(context: .registration)
        result.delegate = self
        return result
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .Signal.background

        let titleLabel = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "REGISTRATION_CAPTCHA_TITLE",
            comment: "During registration, users may be shown a CAPTCHA to verify that they're human. This text is shown above the CAPTCHA."
        ))
        titleLabel.setContentHuggingHigh()
        titleLabel.accessibilityIdentifier = "registration.captcha.titleLabel"

        let stackView = UIStackView(arrangedSubviews: [titleLabel, captchaView])
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 12
        view.addSubview(stackView)
        stackView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stackView.bottomAnchor.constraint(equalTo: view.layoutMarginsGuide.bottomAnchor),
            stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captchaView.loadCaptcha()
    }
}

// MARK: - CaptchaViewDelegate

extension RegistrationCaptchaViewController: CaptchaViewDelegate {
    public func captchaView(_: CaptchaView, didCompleteCaptchaWithToken token: String) {
        presenter?.submitCaptcha(token)
    }

    public func captchaViewDidFailToCompleteCaptcha(_ captchaView: CaptchaView) {
        captchaView.loadCaptcha()
    }
}
