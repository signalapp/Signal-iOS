//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

import UIKit
import WebKit

@objc
public class OnboardingCaptchaViewController: OnboardingBaseViewController {

    private var webView: WKWebView?

    override public func loadView() {
        view = UIView()
        view.addSubview(primaryView)
        primaryView.autoPinEdgesToSuperviewEdges()

        view.backgroundColor = Theme.backgroundColor

        let titleLabel = self.titleLabel(text: NSLocalizedString("ONBOARDING_CAPTCHA_TITLE", comment: "Title of the 'onboarding Captcha' view."))
        titleLabel.accessibilityIdentifier = "onboarding.captcha." + "titleLabel"

        let titleRow = UIStackView(arrangedSubviews: [
            titleLabel
            ])
        titleRow.axis = .vertical
        titleRow.alignment = .fill
        titleRow.layoutMargins = UIEdgeInsets(top: 10, left: 0, bottom: 0, right: 0)
        titleRow.isLayoutMarginsRelativeArrangement = true

        // We want the CAPTCHA web content to "fill the screen (honoring margins)".
        // The way to do this with WKWebView is to inject a javascript snippet that
        // manipulates the viewport.
        let jscript = "var meta = document.createElement('meta'); meta.setAttribute('name', 'viewport'); meta.setAttribute('content', 'width=device-width'); document.getElementsByTagName('head')[0].appendChild(meta);"
        let userScript = WKUserScript(source: jscript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        let wkUController = WKUserContentController()
        wkUController.addUserScript(userScript)
        let wkWebConfig = WKWebViewConfiguration()
        wkWebConfig.userContentController = wkUController
        let webView = WKWebView(frame: self.view.bounds, configuration: wkWebConfig)
        self.webView = webView
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = false
        webView.customUserAgent = "Signal iOS (+https://signal.org/download)"
        webView.allowsLinkPreview = false
        webView.scrollView.contentInset = .zero
        webView.layoutMargins = .zero
        webView.accessibilityIdentifier = "onboarding.captcha." + "webView"

        let stackView = UIStackView(arrangedSubviews: [
            titleRow,
            webView
            ])
        stackView.axis = .vertical
        stackView.alignment = .fill
        primaryView.addSubview(stackView)

        stackView.autoPinEdgesToSuperviewEdges(with: .zero, excludingEdge: .bottom)
        autoPinView(toBottomOfViewControllerOrKeyboard: stackView, avoidNotch: true)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(didBecomeActive),
                                               name: .OWSApplicationDidBecomeActive,
                                               object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        loadContent()

        webView?.scrollView.contentOffset = .zero
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        webView?.scrollView.contentOffset = .zero
    }

    fileprivate let contentUrl = "https://signalcaptchas.org/registration/generate.html"

    private func loadContent() {
        guard let webView = webView else {
            owsFailDebug("Missing webView.")
            return
        }
        guard let url = URL(string: contentUrl) else {
            owsFailDebug("Invalid URL.")
            return
        }
        webView.load(URLRequest(url: url))
        webView.scrollView.contentOffset = .zero
    }

    // MARK: - Notifications

    @objc func didBecomeActive() {
        AssertIsOnMainThread()

        loadContent()
    }

    // MARK: -

    private func parseCaptchaAndRequestVerification(url: URL) {
        Logger.info("")

        guard let captchaToken = parseCaptcha(url: url) else {
            owsFailDebug("Could not parse captcha token: \(url)")
            // TODO: Alert?
            //
            // Reload content so user can try again.
            loadContent()
            return
        }
        onboardingController.update(captchaToken: captchaToken)

        onboardingController.requestVerification(fromViewController: self, isSMS: true)
    }

    private func parseCaptcha(url: URL) -> String? {
        Logger.info("")

        // Example URL:
        // signalcaptcha://03AF6jDqXgf1PocNNrWRJEENZ9l6RAMIsUoESi2dFKkxTgE2qjdZGVjEW6SZNFQqeRRTgGqOii6zHGG--uLyC1HnhSmRt8wHeKxHcg1hsK4ucTusANIeFXVB8wPPiV7U_0w2jUFVak5clMCvW9_JBfbfzj51_e9sou8DYfwc_R6THuTBTdpSV8Nh0yJalgget-nSukCxh6FPA6hRVbw7lP3r-me1QCykHOfh-V29UVaQ4Fs5upHvwB5rtiViqT_HN8WuGmdIdGcaWxaqy1lQTgFSs2Shdj593wZiXfhJnCWAw9rMn3jSgIZhkFxdXwKOmslQ2E_I8iWkm6
        guard let host = url.host,
            host.count > 0 else {
                owsFailDebug("Missing host.")
                return nil
        }

        return host
    }
}

// MARK: -

extension OnboardingCaptchaViewController: WKNavigationDelegate {
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
                self.parseCaptchaAndRequestVerification(url: url)
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
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Logger.verbose("navigation: \(String(describing: navigation))")
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Logger.verbose("navigation: \(String(describing: navigation))")
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Logger.verbose("navigation: \(String(describing: navigation)), error: \(error)")
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Logger.verbose("")
    }
}
