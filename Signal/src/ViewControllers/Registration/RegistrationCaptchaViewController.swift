//
// Copyright 2023 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import SignalCoreKit
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
    }

    @available(*, unavailable)
    public override init() {
        owsFail("This should not be called")
    }

    // MARK: - Rendering

    private lazy var titleLabel: UILabel = {
        let result = UILabel.titleLabelForRegistration(text: OWSLocalizedString(
            "REGISTRATION_CAPTCHA_TITLE",
            comment: "During registration, users may be shown a CAPTCHA to verify that they're human. This text is shown above the CAPTCHA."
        ))
        result.accessibilityIdentifier = "registration.captcha.titleLabel"
        return result
    }()

    private lazy var captchaView: CaptchaView = {
        let result = CaptchaView(context: .registration)
        result.delegate = self
        return result
    }()

    public override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.setHidesBackButton(true, animated: false)

        initialRender()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captchaView.loadCaptcha()
    }

    public override func themeDidChange() {
        super.themeDidChange()
        render()
    }

    private func initialRender() {
        let stackView = UIStackView(arrangedSubviews: [titleLabel, captchaView])
        stackView.axis = .vertical
        stackView.distribution = .fill
        stackView.spacing = 12

        titleLabel.setContentHuggingHigh()

        view.addSubview(stackView)
        stackView.autoPinEdgesToSuperviewMargins()

        render()
    }

    private func render() {
        view.backgroundColor = Theme.backgroundColor
        titleLabel.textColor = .colorForRegistrationTitleLabel
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
