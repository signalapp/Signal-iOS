//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

@objc
public class OnboardingCaptchaViewController: OnboardingBaseViewController, CaptchaViewDelegate {

    private var captchaView: CaptchaView?

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.createTitleLabel(text: NSLocalizedString("ONBOARDING_CAPTCHA_TITLE", comment: "Title of the 'onboarding Captcha' view."))
        titleLabel.accessibilityIdentifier = "onboarding.captcha." + "titleLabel"

        let titleRow = UIStackView(arrangedSubviews: [
            titleLabel
            ])
        titleRow.axis = .vertical
        titleRow.alignment = .fill
        titleRow.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        titleRow.isLayoutMarginsRelativeArrangement = true

        let captchaView = CaptchaView()
        self.captchaView = captchaView
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

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captchaView?.loadCaptcha()
    }

    // MARK: -

    public func captchaView(_: CaptchaView, didCompleteCaptchaWithToken token: String) {
        requestCaptchaVerification(captchaToken: token)
    }

    public func captchaViewDidFailToCompleteCaptcha(_ captchaView: CaptchaView) {
        captchaView.loadCaptcha()
    }

    private func requestCaptchaVerification(captchaToken: String) {
        Logger.info("")
        onboardingController.update(captchaToken: captchaToken)

        let progressView = AnimatedProgressView()
        view.addSubview(progressView)
        progressView.autoCenterInSuperview()
        progressView.startAnimating()

        onboardingController.requestVerification(fromViewController: self, isSMS: true) { [weak self] willDismiss, _ in
            if !willDismiss {
                // There's nothing left to do here. If onboardingController isn't taking us anywhere, let's
                // just pop back to the phone number verification controller
                self?.navigationController?.popViewController(animated: true)
            }
            UIView.animate(withDuration: 0.15) {
                progressView.alpha = 0
            } completion: { _ in
                progressView.removeFromSuperview()
            }
        }
    }
}
