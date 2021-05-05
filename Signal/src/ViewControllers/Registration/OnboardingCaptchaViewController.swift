//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

import UIKit
import WebKit

@objc
public protocol CaptchaViewDelegate: NSObjectProtocol {
    @objc
    optional func captchaView(_: CaptchaView, didCompleteCaptchaWithToken: String)
    @objc
    optional func captchaViewDidFailToCompleteCaptcha(_: CaptchaView)

}

@objc
public class CaptchaView: UIView {

    private let captchaURL = URL(string: "https://signalcaptchas.org/registration/generate.html")!

    private var webView: WKWebView = {
        // We want the CAPTCHA web content to "fill the screen (honoring margins)".
        // The way to do this with WKWebView is to inject a javascript snippet that
        // manipulates the viewport.
        //
        // TODO: There's a long outstanding where short devices will require vertical
        // scrolling to see the entire captcha. We should manipulate the viewport to mitigate
        // this.
        let viewportInjection = WKUserScript(
            source: """
                var meta = document.createElement('meta');
                meta.setAttribute('name', 'viewport');
                meta.setAttribute('content', 'width=device-width');
                document.getElementsByTagName('head')[0].appendChild(meta);
                """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true)

        let contentController = WKUserContentController()
        contentController.addUserScript(viewportInjection)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = false
        webView.customUserAgent = "Signal iOS (+https://signal.org/download)"
        webView.allowsLinkPreview = false
        webView.scrollView.contentInset = .zero
        webView.layoutMargins = .zero
        webView.accessibilityIdentifier = "onboarding.captcha." + "webView"
        return webView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(webView)
        webView.autoPinEdgesToSuperviewEdges()

        webView.navigationDelegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public weak var delegate: CaptchaViewDelegate?

    public func loadCaptcha() {
        webView.load(URLRequest(url: captchaURL))
    }

    @objc
    private func didBecomeActive() {
        loadCaptcha()
    }

    // Example URL:
    // signalcaptcha://03AF6jDqXgf1PocNNrWRJEENZ9l6RAMIsUoESi2dFKkxTgE2qjdZGVjE
    // W6SZNFQqeRRTgGqOii6zHGG--uLyC1HnhSmRt8wHeKxHcg1hsK4ucTusANIeFXVB8wPPiV7U
    // _0w2jUFVak5clMCvW9_JBfbfzj51_e9sou8DYfwc_R6THuTBTdpSV8Nh0yJalgget-nSukCx
    // h6FPA6hRVbw7lP3r-me1QCykHOfh-V29UVaQ4Fs5upHvwB5rtiViqT_HN8WuGmdIdGcaWxaq
    // y1lQTgFSs2Shdj593wZiXfhJnCWAw9rMn3jSgIZhkFxdXwKOmslQ2E_I8iWkm6
    private func parseCaptchaResult(url: URL) {
        if let token = url.host, token.count > 0 {
            delegate?.captchaView?(self, didCompleteCaptchaWithToken: token)
        } else {
            owsFailDebug("Could not parse captcha token: \(url)")
            delegate?.captchaViewDidFailToCompleteCaptcha?(self)
        }
    }
}

extension CaptchaView: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        Logger.verbose("navigationAction: \(String(describing: navigationAction.request.url))")

        guard let url: URL = navigationAction.request.url else {
            owsFailDebug("Missing URL.")
            decisionHandler(.cancel)
            return
        }
        if url.scheme == "signalcaptcha" {
            decisionHandler(.cancel)
            DispatchQueue.main.async {
                self.parseCaptchaResult(url: url)
            }
            return
        }

        // Loading the Captcha content involves a series of actions.
        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        Logger.verbose("navigationResponse: \(String(describing: navigationResponse))")

        decisionHandler(.allow)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        Logger.verbose("navigation: \(String(describing: navigation))")
    }

    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        Logger.verbose("navigation: \(String(describing: navigation))")
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Logger.verbose("navigation: \(String(describing: navigation)), error: \(error)")
        DispatchQueue.main.async {
            self.delegate?.captchaViewDidFailToCompleteCaptcha?(self)
        }
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Logger.verbose("navigation: \(String(describing: navigation))")
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.verbose("navigation: \(String(describing: navigation))")
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.verbose("navigation: \(String(describing: navigation)), error: \(error)")
        DispatchQueue.main.async {
            self.delegate?.captchaViewDidFailToCompleteCaptcha?(self)
        }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Logger.verbose("")
        DispatchQueue.main.async {
            self.delegate?.captchaViewDidFailToCompleteCaptcha?(self)
        }
    }
}

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

@objc(OWSSpamCaptchaViewController)
class SpamCaptchaViewController: UIViewController, CaptchaViewDelegate {
    private var captchaView: CaptchaView?
    var completionHandler: ((String) -> Void)?

    private init() {
        super.init(nibName: nil, bundle: nil)
    }

    @objc
    static func presentModallyWithCompletion(_ completion: @escaping (String?) -> Void) {
        guard let frontmostVC = UIApplication.shared.frontmostViewController else {
            return completion(nil)
        }

        let vc = SpamCaptchaViewController()
        vc.completionHandler = { token in
            completion(token)
            vc.dismiss(animated: true, completion: nil)
        }

        let navVC = OWSNavigationController(rootViewController: vc)
        frontmostVC.present(navVC, animated: true, completion: nil)
    }

    override func loadView() {
        let captchaView = CaptchaView()
        captchaView.delegate = self

        let view = UIView()
        view.addSubview(captchaView)
        captchaView.autoPinEdgesToSuperviewEdges()

        self.captchaView = captchaView
        self.view = view
        view.backgroundColor = .blue
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        captchaView?.loadCaptcha()
    }

    func captchaView(_: CaptchaView, didCompleteCaptchaWithToken token: String) {
        completionHandler?(token)
        completionHandler = nil
    }

    func captchaViewDidFailToCompleteCaptcha(_: CaptchaView) {
        captchaView?.loadCaptcha()
    }

}
