//
// Copyright 2019 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

import Foundation
import WebKit
import SignalServiceKit

public protocol CaptchaViewDelegate: NSObjectProtocol {
    func captchaView(_: CaptchaView, didCompleteCaptchaWithToken: String)
    func captchaViewDidFailToCompleteCaptcha(_: CaptchaView)
}

public enum CaptchaContext {
    case registration, challenge

    fileprivate var url: URL {
        switch self {
        case .registration:
            return URL(string: TSConstants.registrationCaptchaURL)!
        case .challenge:
            return URL(string: TSConstants.challengeCaptchaURL)!
        }
    }
}

public class CaptchaView: UIView {

    private let context: CaptchaContext

    public init(context: CaptchaContext) {
        self.context = context

        super.init(frame: .zero)

        addSubview(webView)
        webView.autoPinEdgesToSuperviewEdges()

        webView.navigationDelegate = self

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didBecomeActive),
            name: .OWSApplicationDidBecomeActive,
            object: nil)
    }

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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public weak var delegate: CaptchaViewDelegate?

    public func loadCaptcha() {
        webView.load(URLRequest(url: context.url))
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
            delegate?.captchaView(self, didCompleteCaptchaWithToken: token)
        } else {
            owsFailDebug("Could not parse captcha token: \(url)")
            delegate?.captchaViewDidFailToCompleteCaptcha(self)
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
            self.delegate?.captchaViewDidFailToCompleteCaptcha(self)
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
            self.delegate?.captchaViewDidFailToCompleteCaptcha(self)
        }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Logger.verbose("")
        DispatchQueue.main.async {
            self.delegate?.captchaViewDidFailToCompleteCaptcha(self)
        }
    }
}
